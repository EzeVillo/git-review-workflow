#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
}
teardown() { comments_teardown; }

@test "comments explicit empty or whitespace input cancels without creating storage" {
	local text
	for text in '' '   ' $'\n\t\r\n'; do
		comments_snapshot "$COMMENTS_TMP/before"
		run --separate-stderr git review comments add --document shared --text "$text"
		[ "$status" -eq 0 ]
		[ "$output" = '' ]
		[ "$stderr" = '' ]
		comments_snapshot "$COMMENTS_TMP/after"
		comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	done
}

@test "comments stdin is UTF-8 multiline data and never shell code" {
	local body
	body=$(printf '¿Por qué?\n%s\n' '$(touch EXECUTED) `touch EXECUTED` "quotes"')
	printf '%s\n' "$body" >"$COMMENTS_TMP/input"
	run --separate-stderr git review comments add --document local --stdin <"$COMMENTS_TMP/input"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	tail -n 2 "$COMMENTS_LOCAL" >"$COMMENTS_TMP/actual-body"
	cmp "$COMMENTS_TMP/input" "$COMMENTS_TMP/actual-body"
	[ ! -e EXECUTED ]
	[[ "$output" != *'touch EXECUTED'* ]]
}

@test "comments configured Git editor accepts command arguments and spaced paths" {
	mkdir "$COMMENTS_TMP/editor dir"
	cat >"$COMMENTS_TMP/editor dir/compose" <<'EDITOR'
#!/bin/sh
set -eu
[ "$1" = '--compose' ]
printf 'Editor text.\n' >"$2"
EDITOR
	chmod +x "$COMMENTS_TMP/editor dir/compose"
	export GIT_EDITOR="'$COMMENTS_TMP/editor dir/compose' --compose"
	run --separate-stderr git review comments add --document shared
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	[ "$(tail -n 1 "$COMMENTS_SHARED")" = 'Editor text.' ]
}

@test "comments editor cancellation or failure preserves the session without a document" {
	export GIT_EDITOR=true
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments add --document shared
	[ "$status" -eq 0 ]
	[ "$output" = '' ]
	[ "$stderr" = '' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	export GIT_EDITOR=false
	run --separate-stderr git review comments add --document shared
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comment could not be composed with the configured editor' ]
	comments_snapshot "$COMMENTS_TMP/failed"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/failed"
}
