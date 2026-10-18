#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

remove_legacy_comments_keys() {
	git config --unset branch.review/feature/comments.reviewcommentssession
	git config --unset branch.review/feature/comments.reviewcommentsowner
	git config --unset branch.review/feature/comments.reviewcommentscontext || true
}

check_legacy_readonly() {
	run --separate-stderr comments_start "$1"
	[ "$status" -eq 0 ]
	remove_legacy_comments_keys
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-identity" {print $2}')" = fresh ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-document" {print}')" = '' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	if [ "$1" != whole ]; then
		run --separate-stderr git review next
		[ "$status" -eq 0 ]
		run --separate-stderr git review prev
		[ "$status" -eq 0 ]
	fi
	[ "$(git config branch.review/feature/comments.reviewcommentssession || true)" = '' ]
	run --separate-stderr git review comments add --document local --text 'Initialize explicitly.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	[ -f "$COMMENTS_LOCAL" ]
	[ ! -e "$COMMENTS_SHARED" ]
}

@test "comments legacy whole query does not initialize custody" { check_legacy_readonly whole; }
@test "comments legacy walk query and navigation do not initialize custody" { check_legacy_readonly walk; }
@test "comments legacy step query and navigation do not initialize custody" { check_legacy_readonly step; }

@test "comments legacy query never exposes the retained discard baseline as its editable preparation" {
	comments_fixture_baseline present
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	remove_legacy_comments_keys
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	local path
	path=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-document" && $4=="local" {print $2}')
	[ -n "$path" ]
	[ "$path" != "$COMMENTS_RESULT_DIR/local.md" ]
	[ ! -e "$path" ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	run --separate-stderr git review comments init --document local
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	cmp "$COMMENTS_TMP/baseline-local" "$COMMENTS_LOCAL"
	printf '\nNew local edits.\n' >>"$COMMENTS_LOCAL"
	run --separate-stderr git review abort
	[ "$status" -eq 0 ]
	comments_assert_baseline
}
