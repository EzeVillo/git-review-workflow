#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Keep this preparation after metadata loss.'
	[ "$status" -eq 0 ]
}
teardown() { comments_teardown; }

remove_custody_keys() {
	local branch=$1
	git config --unset "branch.$branch.reviewcommentscontext"
	git config --unset "branch.$branch.reviewcommentssession"
	git config --unset "branch.$branch.reviewcommentsowner"
}

@test "comments save refuses lost custody keys when its owned manifest still claims the review" {
	remove_custody_keys review/feature/comments
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review save
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments session ownership metadata is incomplete' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments forget saved refuses lost custody keys before deleting the paused branch" {
	run --separate-stderr git review save
	[ "$status" -eq 0 ]
	remove_custody_keys review-saved/feature/comments
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review forget --saved feature/comments
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments session ownership metadata is incomplete' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}
