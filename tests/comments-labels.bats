#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

assert_retained_label() {
	comments_snapshot "$COMMENTS_TMP/before-label"
	run --separate-stderr git review comments status --porcelain "$@"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-context" {print $2 "\t" $4 "\t" $6}')" = "$(printf '%s\tresult\tfeature/comments' "$COMMENTS_CONTEXT")" ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-document" && $4=="local" {print $5}')" = present ]
	comments_snapshot "$COMMENTS_TMP/after-label"
	comments_assert_snapshot "$COMMENTS_TMP/before-label" "$COMMENTS_TMP/after-label"
}

@test "comments finished result keeps source label after clean removes review branch" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Retained observation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	assert_retained_label
	run --separate-stderr git review clean --keep-fixes
	[ "$status" -eq 0 ]
	run git show-ref --verify --quiet refs/heads/review/feature/comments
	[ "$status" -eq 1 ]
	assert_retained_label --context "$COMMENTS_CONTEXT"
}

@test "comments saved comparison result keeps source label after abort" {
	run --separate-stderr comments_start compare
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Retained comparison.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	run --separate-stderr git review comments save
	[ "$status" -eq 0 ]
	run --separate-stderr git review abort
	[ "$status" -eq 0 ]
	assert_retained_label
}

@test "comments existing result uses manifest source even when source branch is gone" {
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_result
	printf 'Existing retained prose.\n' >"$COMMENTS_RESULT_DIR/local.md"
	git branch -D feature/comments
	assert_retained_label --context "$COMMENTS_CONTEXT"
}
