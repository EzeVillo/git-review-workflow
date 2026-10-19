#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments init --document local
	[ "$status" -eq 0 ]
	comments_refresh_paths
	export COMMENTS_REAL_GIT
	COMMENTS_REAL_GIT=$(command -v git)
	export COMMENTS_GIT_TRACE="$COMMENTS_TMP/git-trace"
	mkdir "$COMMENTS_TMP/trace-bin"
	cat >"$COMMENTS_TMP/trace-bin/git" <<'WRAPPER'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$COMMENTS_GIT_TRACE"
case "$1" in fetch|push) printf 'unexpected network call\n' >&2; exit 83 ;; esac
exec "$COMMENTS_REAL_GIT" "$@"
WRAPPER
	chmod +x "$COMMENTS_TMP/trace-bin/git"
	export PATH="$COMMENTS_TMP/trace-bin:$PATH"
}
teardown() { comments_teardown; }

@test "comments counting one hundred entries does not add a Git process per entry" {
	printf '## 9. Single\nBody.\n' >"$COMMENTS_LOCAL"
	: >"$COMMENTS_GIT_TRACE"
	run --separate-stderr git-review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-count" {print $3}')" = 1 ]
	local single_calls
	single_calls=$(wc -l <"$COMMENTS_GIT_TRACE")
	cp "$BATS_TEST_DIRNAME/fixtures/comments/hundred.md" "$COMMENTS_LOCAL"
	: >"$COMMENTS_GIT_TRACE"
	run --separate-stderr git-review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-count" {print $3}')" = 100 ]
	[ "$(wc -l <"$COMMENTS_GIT_TRACE")" -eq "$single_calls" ]
	cmp "$BATS_TEST_DIRNAME/fixtures/comments/hundred.md" "$COMMENTS_LOCAL"
}

@test "comments renumber one hundred full bodies in either document has constant Git overhead" {
	local document path single_calls
	for document in local shared; do
		if [ "$document" = local ]; then path=$COMMENTS_LOCAL; else path=$COMMENTS_SHARED; fi
		printf '## 9. Single\nBody.\n' >"$path"
		: >"$COMMENTS_GIT_TRACE"
		run --separate-stderr git-review comments renumber --document "$document"
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		single_calls=$(wc -l <"$COMMENTS_GIT_TRACE")
		cp "$BATS_TEST_DIRNAME/fixtures/comments/hundred.md" "$path"
		: >"$COMMENTS_GIT_TRACE"
		run --separate-stderr git-review comments renumber --document "$document"
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		[ "$(wc -l <"$COMMENTS_GIT_TRACE")" -eq "$single_calls" ]
		cmp "$BATS_TEST_DIRNAME/fixtures/comments/hundred.expected.md" "$path"
	done
}
