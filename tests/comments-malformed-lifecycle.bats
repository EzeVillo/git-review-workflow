#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments malformed Shared with unavailable references still finishes and delivers exact prose bytes" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Private unaffected prose.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	printf '## 9. Manual observation\n<!-- git-review-comment v7\nbase unavailable\nhead 1111111111111111111111111111111111111111\n-->\nFree prose.\n<!-- unfinished manual HTML' >"$COMMENTS_SHARED"
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/expected"
	run --separate-stderr git review status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	cmp "$COMMENTS_TMP/expected" .review/comments.md
	[ "$(git diff --cached --name-only)" = '' ]
	comments_snapshot "$COMMENTS_TMP/before"
	comments_refresh_paths
	[ "$(printf '%s\n' "$output" | awk -F '\t' -v path="$COMMENTS_SHARED" '$1=="comments-count" && $2==path {print}')" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-diagnostic" {print $3}')" = format ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_SHARED"
}
