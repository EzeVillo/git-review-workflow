#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

check_custody_roundtrip() {
	comments_fixture_baseline "$2"
	run --separate-stderr comments_start "$1"
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'New private preparation.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	run --separate-stderr git review comments add --document shared --text 'New shared preparation.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	local local_path=$COMMENTS_LOCAL shared_path=$COMMENTS_SHARED
	cp "$local_path" "$COMMENTS_TMP/prepared-local"
	cp "$shared_path" "$COMMENTS_TMP/prepared-shared"
	printf 'reviewer code change\n' >>sample.txt
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review save
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = main ]
	[ ! -e .review/comments.md ]
	cmp "$COMMENTS_TMP/prepared-local" "$local_path"
	cmp "$COMMENTS_TMP/prepared-shared" "$shared_path"
	comments_assert_baseline
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ "$COMMENTS_LOCAL" = "$local_path" ]
	[ "$COMMENTS_SHARED" = "$shared_path" ]
	cmp "$COMMENTS_TMP/prepared-local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/prepared-shared" "$COMMENTS_SHARED"
	[ ! -e .review/comments.md ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" index staged unstaged worktree
	run --separate-stderr git review abort
	[ "$status" -eq 0 ]
	[ ! -e "$local_path" ]
	[ ! -e "$shared_path" ]
	comments_assert_baseline
	[ ! -e .review/comments.md ]
}

@test "comments whole save continue abort respects an absent baseline pair" { check_custody_roundtrip whole absent; }
@test "comments whole save continue abort respects an empty baseline pair" { check_custody_roundtrip whole empty; }
@test "comments whole save continue abort respects a present baseline pair" { check_custody_roundtrip whole present; }
@test "comments walk save continue abort respects an absent baseline pair" { check_custody_roundtrip walk absent; }
@test "comments walk save continue abort respects an empty baseline pair" { check_custody_roundtrip walk empty; }
@test "comments walk save continue abort respects a present baseline pair" { check_custody_roundtrip walk present; }
@test "comments step save continue abort respects an absent baseline pair" { check_custody_roundtrip step absent; }
@test "comments step save continue abort respects an empty baseline pair" { check_custody_roundtrip step empty; }
@test "comments step save continue abort respects a present baseline pair" { check_custody_roundtrip step present; }
