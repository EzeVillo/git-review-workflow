#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments init creates only chosen document and does not truncate on repeat" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments init --document local
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	[ -f "$COMMENTS_LOCAL" ]
	[ ! -e "$COMMENTS_SHARED" ]
	printf 'manual body without final LF' >>"$COMMENTS_LOCAL"
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/expected"
	run --separate-stderr git review comments init --document local
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	cmp "$COMMENTS_LOCAL" "$COMMENTS_TMP/expected"
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" branch head refs index raw-index.bytes staged unstaged worktree objects
}

@test "comments init preserves an existing empty document" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments init --document shared
	[ "$status" -eq 0 ]
	comments_refresh_paths
	: >"$COMMENTS_SHARED"
	local old_path="$COMMENTS_SHARED"
	run --separate-stderr git review comments init --document shared
	[ "$status" -eq 0 ]
	[ ! -s "$old_path" ]
}

@test "comments new context before editing keeps the previous baseline accessible" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_session
	: >"$COMMENTS_SESSION_DIR/shared.md"
	: >"$COMMENTS_SESSION_DIR/baseline/shared.md"
	local old_path="$COMMENTS_SESSION_DIR/shared.md" old_context="$COMMENTS_CONTEXT"
	run --separate-stderr git review comments init --document local --new-context
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ "$old_context" != "$COMMENTS_CONTEXT" ]
	[ -f "$old_path" ]
	[ ! -s "$old_path" ]
}

@test "comments context cannot be reassigned after new unsaved preparation" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Keep this.'
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments init --document shared --new-context
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: preserve or discard the current comments preparation before changing context' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments init and add require an active compatible session" {
	local command
	for command in init add; do
		comments_snapshot "$COMMENTS_TMP/before"
		run --separate-stderr git review comments "$command" --document local --text 'Example'
		# --text is only valid for add; init rejects it as usage before scope.
		if [ "$command" = init ]; then [ "$status" -eq 1 ]; else [ "$status" -eq 2 ]; fi
		[ "$output" = '' ]
		[[ "$stderr" == 'error: '* ]]
		comments_snapshot "$COMMENTS_TMP/after"
		comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	done
}

@test "comments fresh sessions have distinct guards even when branch and range are identical" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	local first_guard
	first_guard=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-guard" {print $2}')
	[ -n "$first_guard" ]
	run --separate-stderr git review abort
	[ "$status" -eq 0 ]
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	local second_guard
	second_guard=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-guard" {print $2}')
	[ "$first_guard" != "$second_guard" ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments add --document local --text 'Old form.' --expect-context "$first_guard" --expect-document absent
	[ "$status" -eq 4 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments context is stale' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments cancelling the second destination keeps the first and leaves the second absent" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Keep the first destination.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments add --document shared --text '   '
	[ "$status" -eq 0 ]
	[ "$output" = '' ]
	[ "$stderr" = '' ]
	[ ! -e "$COMMENTS_SHARED" ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}
