#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments saved preparation is discoverable read only and editable before continue" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Keep the saved observation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT path=$COMMENTS_LOCAL
	run --separate-stderr git review save
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-context" {print $2 "\t" $4}')" = "$(printf '%s\tsaved' "$context")" ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-document" && $4=="local" {print $2}')" = "$path" ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	printf '## 9. Saved manual entry\nKeep this text.\n' >"$path"
	run --separate-stderr git review comments renumber --context "$context" --document local
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	printf '## 1. Saved manual entry\nKeep this text.\n' >"$COMMENTS_TMP/expected"
	cmp "$COMMENTS_TMP/expected" "$path"
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ "$COMMENTS_LOCAL" = "$path" ]
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_LOCAL"
}

@test "comments result contexts have distinct guards and no implicit most recent selection" {
	local context
	for context in 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222; do
		comments_fixture_context "$context"
		comments_fixture_result
		printf '## 9. Retained\n%s\n' "$context" >"$COMMENTS_RESULT_DIR/local.md"
	done
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	local guards
	guards=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-context" {print $5}' | sort -u)
	[ "$(printf '%s\n' "$guards" | wc -l)" -eq 2 ]
	run --separate-stderr git review comments renumber --document local
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: select a comments context with --context' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments guarded retained renumber works while another review is active without adopting its session" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Active observation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local active_path=$COMMENTS_LOCAL active_session
	active_session=$(git config branch.review/feature/comments.reviewcommentssession)
	cp "$active_path" "$COMMENTS_TMP/active-prose"
	comments_fixture_context 2222222222222222222222222222222222222222 compare
	comments_fixture_result
	printf '## 9. Retained\nKeep this retained prose.\n' >"$COMMENTS_RESULT_DIR/local.md"
	run --separate-stderr git review comments status --context "$COMMENTS_CONTEXT" --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	local guard revision
	guard=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-context" {print $5}')
	revision=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-document" && $4=="local" {print $6}')
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments renumber --context "$COMMENTS_CONTEXT" --document local --expect-context "$guard" --expect-document "$revision"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	printf '## 1. Retained\nKeep this retained prose.\n' >"$COMMENTS_TMP/expected"
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_RESULT_DIR/local.md"
	cmp "$COMMENTS_TMP/active-prose" "$active_path"
	[ "$(git config branch.review/feature/comments.reviewcommentssession)" = "$active_session" ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" branch head refs config index raw-index.bytes staged unstaged worktree objects
}
