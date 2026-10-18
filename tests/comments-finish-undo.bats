#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Current private prose.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Current Shared prose.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	COMMENTS_ORIGINAL_SESSION_LOCAL=$COMMENTS_LOCAL
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	comments_refresh_paths
}
teardown() { comments_teardown; }

check_deleted_result() {
	local selected other
	if [ "$1" = local ]; then selected=$COMMENTS_LOCAL; other=$COMMENTS_SHARED
	else selected=$COMMENTS_SHARED; other=$COMMENTS_LOCAL
	fi
	cp "$other" "$COMMENTS_TMP/other"
	rm "$selected"
	run --separate-stderr git review finish --abort
	[ "$status" -eq 0 ]
	comments_refresh_paths
	if [ "$1" = local ]; then selected=$COMMENTS_LOCAL; other=$COMMENTS_SHARED
	else selected=$COMMENTS_SHARED; other=$COMMENTS_LOCAL
	fi
	[ ! -e "$selected" ]
	cmp "$COMMENTS_TMP/other" "$other"
	[ ! -e .review/comments.md ]
}

@test "comments finish undo respects a manually deleted retained Local instead of resurrecting it" { check_deleted_result local; }
@test "comments finish undo respects a manually deleted retained Shared instead of resurrecting it" { check_deleted_result shared; }

@test "comments finish undo keeps a deliberately empty retained Local as present" {
	: >"$COMMENTS_LOCAL"
	run --separate-stderr git review finish --abort
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ -f "$COMMENTS_LOCAL" ]
	[ ! -s "$COMMENTS_LOCAL" ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' -v path="$COMMENTS_LOCAL" '$1=="comments-count" && $2==path {print $3}')" = 0 ]
}

@test "comments finish undo preserves both versions if the original preparation was edited after closure" {
	printf '\nEdited in an older still open editor.\n' >>"$COMMENTS_ORIGINAL_SESSION_LOCAL"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review finish --abort
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments preparation changed after finish; preserve both versions before undoing it' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments forced finish undo discards later code but preserves current retained prose" {
	printf '\nRetained private edit after closure.\n' >>"$COMMENTS_LOCAL"
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/private-current"
	printf 'later code to discard\n' >>sample.txt
	run --separate-stderr git review finish --abort --force
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = review/feature/comments ]
	[ "$(git diff --name-only)" = '' ]
	comments_refresh_paths
	cmp "$COMMENTS_TMP/private-current" "$COMMENTS_LOCAL"
	[ ! -e .review/comments.md ]
}
