#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments finish conflict undo keeps general prose captured during the unresolved replay" {
	run --separate-stderr comments_start step
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Private before replay.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Shared before replay.'
	[ "$status" -eq 0 ]
	printf 'first-review\nchanged\nthird\n' >sample.txt
	run --separate-stderr git review next
	[ "$status" -eq 0 ]
	printf 'first\nchanged-review\nthird\n' >sample.txt
	run --separate-stderr git review finish
	[ "$status" -eq 1 ]
	[ "$(git config branch.review/feature/comments.reviewresume)" = conflict ]
	run --separate-stderr git review comments add --document shared --text 'General observation while resolving the replay.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/local"
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/shared"
	run --separate-stderr git review finish --abort
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/comments.reviewresume || true)" = '' ]
	comments_refresh_paths
	cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
	[ ! -e .review/comments.md ]
	run --separate-stderr git review comments diff --document shared --entry 2 --porcelain
	[ "$status" -eq 5 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comment has no reproducible historical range' ]
}
