#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

start_prose() {
	git switch --quiet feature/comments
	mkdir .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. sample.txt
> key
> at: ignored metadata

First paragraph.

## 2. other file.txt

> key
> at: ignored metadata

Quotes " and ` and $(literal), café.
Backslashes \n and \t stay literal.

EOF
	printf 'A\tB\rC  \n\n' >>.review/walkthrough.md
	git add .review/walkthrough.md
	git commit --quiet -m prose
	git switch --quiet main
	git review start --offline feature/comments >/dev/null
}

@test "navigation includes exact selected prose with escaped framing" {
	start_prose
	run --separate-stderr git review next --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	expected=$(printf 'why\tpresent\t4\nwhy-line\t1\tQuotes " and ` and $(literal), café.\nwhy-line\t2\tBackslashes \\\\n and \\\\t stay literal.\nwhy-line\t3\t\nwhy-line\t4\tA\\tB\\rC  ')
	actual=$(printf '%s\n' "$output" | awk -F '\t' '$1=="why" || $1=="why-line"')
	[ "$actual" = "$expected" ]
	[ "$(git config branch.review/feature/comments.reviewwalkstep)" = 2 ]
	run --separate-stderr git review status --why 'other file.txt'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	expected_body=$(printf 'Quotes " and ` and $(literal), café.\nBackslashes \\n and \\t stay literal.\n\nA\tB\rC  ')
	[ "$output" = "$expected_body" ]
}

@test "missing prose is explicit while ordinary status keeps its existing surface" {
	comments_start walk >/dev/null
	# The walkthrough itself is a changed unannotated file appended to the walk.
	git review next >/dev/null
	run --separate-stderr git review next --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="why" {print $0}')" = "$(printf 'why\tabsent\t0')" ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="why-line" {n++} END {print n+0}')" = 0 ]
	run --separate-stderr git review status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="why" || $1=="why-line" {n++} END {print n+0}')" = 0 ]
}

@test "inline prose adds no parser or Git reads to the navigation reply" {
	start_prose
	export WHY_REAL_GIT="$(command -v git)" WHY_REAL_AWK="$(command -v awk)" WHY_CALLS="$COMMENTS_TMP/calls"
	mkdir "$COMMENTS_TMP/trace"
	for command in git awk; do
		cat >"$COMMENTS_TMP/trace/$command" <<'EOF'
#!/bin/sh
set -eu
name=${0##*/}
printf '%s %s\n' "$name" "$*" >>"$WHY_CALLS"
if [ "$name" = git ]; then exec "$WHY_REAL_GIT" "$@"; fi
exec "$WHY_REAL_AWK" "$@"
EOF
		chmod +x "$COMMENTS_TMP/trace/$command"
	done
	export PATH="$COMMENTS_TMP/trace:$PATH"
	run --separate-stderr sh "$BATS_TEST_DIRNAME/../bin/git-review" next --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(awk '$1=="git" && $2=="config" && $3=="--null" {n++} END {print n+0}' "$WHY_CALLS")" -eq 1 ]
	[ "$(awk '$1=="git" && $2=="show" && /:.review\/walkthrough.md$/ {n++} END {print n+0}' "$WHY_CALLS")" -eq 1 ]
	[ "$(awk '$1=="awk" && $2=="-v" && $3=="mode=fields" {n++} END {print n+0}' "$WHY_CALLS")" -eq 1 ]
	[ "$(awk '$1=="awk" && $2=="-v" && $3=="mode=why" {n++} END {print n+0}' "$WHY_CALLS")" -eq 0 ]
}
