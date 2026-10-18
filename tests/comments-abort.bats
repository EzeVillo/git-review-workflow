#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

check_forget_saved() {
	comments_fixture_baseline "$2"
	run --separate-stderr comments_start "$1"
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Discard private preparation.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Discard shared preparation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local local_path=$COMMENTS_LOCAL shared_path=$COMMENTS_SHARED
	run --separate-stderr git review save
	[ "$status" -eq 0 ]
	# Writing while paused must neither disappear on continue nor become a new
	# durable checkpoint merely because the review itself was saved.
	printf '\nWritten while paused.\n' >>"$local_path"
	run --separate-stderr git review forget --saved feature/comments
	[ "$status" -eq 0 ]
	[ ! -e "$local_path" ]
	[ ! -e "$shared_path" ]
	[ -z "$(git for-each-ref --format='%(refname)' refs/heads/review-saved/)" ]
	[ -z "$(git for-each-ref --format='%(refname)' refs/review-saved-edits/)" ]
	comments_assert_baseline
	[ ! -e .review/comments.md ]
}

@test "comments forgetting whole saved preparation preserves an absent previous result" { check_forget_saved whole absent; }
@test "comments forgetting walk saved preparation preserves an empty previous result" { check_forget_saved walk empty; }
@test "comments forgetting step saved preparation preserves a present previous result" { check_forget_saved step present; }
