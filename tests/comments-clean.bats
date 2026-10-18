#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

check_incomplete_clean() {
	comments_fixture_baseline "$2"
	run --separate-stderr comments_start "$1"
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'New private preparation.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'New shared preparation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local local_path=$COMMENTS_LOCAL shared_path=$COMMENTS_SHARED
	git switch --quiet --discard-changes main
	run --separate-stderr git review clean feature/comments
	[ "$status" -eq 0 ]
	[ ! -e "$local_path" ]
	[ ! -e "$shared_path" ]
	[ -z "$(git for-each-ref --format='%(refname)' refs/heads/review/)" ]
	comments_assert_baseline
	[ ! -e .review/comments.md ]
}

@test "comments incomplete whole clean preserves an absent retained baseline" { check_incomplete_clean whole absent; }
@test "comments incomplete walk clean preserves an empty retained baseline" { check_incomplete_clean walk empty; }
@test "comments incomplete step clean preserves a present retained baseline" { check_incomplete_clean step present; }

@test "comments completed clean preserves later retained edits instead of republishing the old session" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'First observation.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	comments_refresh_paths
	printf '\nEdited retained result after finish.\n' >>"$COMMENTS_LOCAL"
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/expected"
	git switch --quiet main
	run --separate-stderr git review clean feature/comments
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_LOCAL"
	[ ! -e "$COMMENTS_SHARED" ]
}

@test "comments fixes only cleanup and forgetting delta leave all prose untouched" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Retained private observation.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local root
	root=$(git rev-parse --absolute-git-dir)/review-comments
	comments_inventory "$root" >"$COMMENTS_TMP/before-prose"
	git switch --quiet main
	run --separate-stderr git review clean --fixes-only feature/comments
	[ "$status" -eq 0 ]
	run --separate-stderr git review forget --delta feature/comments
	[ "$status" -eq 0 ]
	comments_inventory "$root" >"$COMMENTS_TMP/after-prose"
	cmp "$COMMENTS_TMP/before-prose" "$COMMENTS_TMP/after-prose"
	[ -n "$(git rev-parse --verify refs/heads/review/feature/comments)" ]
	[ -z "$(git for-each-ref --format='%(refname)' refs/heads/review-fixes/)" ]
}
