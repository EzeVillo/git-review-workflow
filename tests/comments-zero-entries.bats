#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments chosen Shared with only a preamble is delivered without inventing an entry or a code commit" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments init --document shared
	[ "$status" -eq 0 ]
	comments_refresh_paths
	printf '# Comments\n\n<!-- git-review-comments v1\ncontext %s\n-->\n' "$COMMENTS_CONTEXT" >"$COMMENTS_TMP/expected"
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_SHARED"
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-count" {print $3}')" = 0 ]
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$COMMENTS_TIP" ]
	[ "$(git diff --cached --name-only)" = '' ]
	cmp "$COMMENTS_TMP/expected" .review/comments.md
}
