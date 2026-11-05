#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

trace_git() {
	export PERFORMANCE_REAL_GIT="$(command -v git)"
	export PERFORMANCE_CALLS="$COMMENTS_TMP/calls"
	mkdir "$COMMENTS_TMP/trace-bin"
	cat >"$COMMENTS_TMP/trace-bin/git" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$PERFORMANCE_CALLS"
exec "$PERFORMANCE_REAL_GIT" "$@"
EOF
	chmod +x "$COMMENTS_TMP/trace-bin/git"
	export PATH="$COMMENTS_TMP/trace-bin:$PATH"
}

@test "walk status reads branch config walkthrough and range once without changing Git" {
	run --separate-stderr comments_start walk
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/before"
	trace_git
	run --separate-stderr sh "$BATS_TEST_DIRNAME/../bin/git-review" status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="entry" {n++} END {print n}')" -eq 3 ]
	[ "$(awk '$1=="config" {n++} END {print n+0}' "$PERFORMANCE_CALLS")" -eq 1 ]
	[ "$(awk '$1=="show" && /:.review\/walkthrough.md$/ {n++} END {print n+0}' "$PERFORMANCE_CALLS")" -eq 1 ]
	[ "$(awk '$1=="-c" && $3=="diff" {n++} END {print n+0}' "$PERFORMANCE_CALLS")" -eq 1 ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments status batches config while retaining the active capture guard" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	trace_git
	run --separate-stderr sh "$BATS_TEST_DIRNAME/../bin/git-review" comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(awk '$1=="config" {n++} END {print n+0}' "$PERFORMANCE_CALLS")" -eq 1 ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-capture" {n++} END {print n+0}')" -eq 1 ]
}

@test "cursor navigation snapshots config once and invalidates it before writing" {
	run --separate-stderr comments_start walk
	[ "$status" -eq 0 ]
	local before_index before_files
	before_index=$(git hash-object --no-filters "$(git rev-parse --git-path index)")
	before_files=$(git diff --no-ext-diff)
	trace_git
	run --separate-stderr sh "$BATS_TEST_DIRNAME/../bin/git-review" next
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(awk '$1=="config" && $2=="--null" {n++} END {print n+0}' "$PERFORMANCE_CALLS")" -eq 1 ]
	[ "$(awk '$1=="config" && $2!="--null" {n++} END {print n+0}' "$PERFORMANCE_CALLS")" -eq 1 ]
	[ "$(git config branch.review/feature/comments.reviewwalkstep)" = 2 ]
	[ "$(git hash-object --no-filters "$(git rev-parse --git-path index)")" = "$before_index" ]
	[ "$(git diff --no-ext-diff)" = "$before_files" ]
	run --separate-stderr sh "$BATS_TEST_DIRNAME/../bin/git-review" prev
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(git config branch.review/feature/comments.reviewwalkstep)" = 1 ]
}

@test "config snapshot preserves multiline bytes included overrides and empty versus absent" {
	local key value
	key='branch.review/feature.reviewsource'
	value=$(printf 'accent: \303\261\tbackslash: \\141\n$(touch must-not-exist)\nlast\n\nx')
	value=${value%x}
	git config --global "$key" global
	git config --file "$COMMENTS_TMP/included" "$key" included
	git config --global include.path "$COMMENTS_TMP/included"
	git config "$key" "$value"
	git config branch.review/feature.reviewempty ''
	export PERFORMANCE_KEY="$key" PERFORMANCE_LIB="$BATS_TEST_DIRNAME/../bin/git-review-lib.sh" PERFORMANCE_ACTUAL="$COMMENTS_TMP/actual"
	git config "$key" >"$COMMENTS_TMP/expected"
	run --separate-stderr sh -c '. "$PERFORMANCE_LIB"; review_config_init; [ "$_review_config_ready" -eq 1 ] || exit 9; review_config_get "$PERFORMANCE_KEY" >"$PERFORMANCE_ACTUAL"'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	cmp "$COMMENTS_TMP/expected" "$PERFORMANCE_ACTUAL"
	[ ! -e must-not-exist ]
	run --separate-stderr sh -c '. "$PERFORMANCE_LIB"; review_config_init; review_config_get branch.review/feature.reviewempty'
	[ "$status" -eq 0 ]
	[ "$output" = '' ]
	run --separate-stderr sh -c '. "$PERFORMANCE_LIB"; review_config_init; review_config_get branch.review/feature.reviewmissing'
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = '' ]
}

@test "walk snapshots are refreshed across commands and keep reviewer draft precedence" {
	run --separate-stderr comments_start walk
	[ "$status" -eq 0 ]
	local gitdir draft
	gitdir=$(git rev-parse --absolute-git-dir)
	draft="$gitdir/review-walkthrough/feature/comments.md"
	mkdir -p "${draft%/*}"
	printf '# Reading order\n\n## 1. sample.txt\n\nFirst draft body.\n\n## 2. other file.txt\n\nOther.\n' >"$draft"
	run --separate-stderr git review status --why sample.txt
	[ "$status" -eq 0 ]
	[ "$output" = 'First draft body.' ]
	[ "$stderr" = '' ]
	printf '# Reading order\n\n## 1. sample.txt\n\nChanged draft body.\n\n## 2. other file.txt\n\nOther.\n' >"$draft"
	run --separate-stderr git review status --why sample.txt
	[ "$status" -eq 0 ]
	[ "$output" = 'Changed draft body.' ]
	[ "$stderr" = '' ]
	printf ' \t\n' >"$draft"
	run --separate-stderr git review status --why sample.txt
	[ "$status" -eq 0 ]
	[ "$output" = 'Read the changed line.' ]
	[ "$stderr" = '' ]
}
