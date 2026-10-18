#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments save and continue keep both documents outside the step bank" {
	run --separate-stderr comments_start step
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Private step one.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Shared step one.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/local"
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/shared"
	local local_path=$COMMENTS_LOCAL shared_path=$COMMENTS_SHARED
	run --separate-stderr git review next
	[ "$status" -eq 0 ]
	cmp "$COMMENTS_TMP/local" "$local_path"
	cmp "$COMMENTS_TMP/shared" "$shared_path"
	run --separate-stderr git review save
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = main ]
	cmp "$COMMENTS_TMP/local" "$local_path"
	cmp "$COMMENTS_TMP/shared" "$shared_path"
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ "$COMMENTS_LOCAL" = "$local_path" ]
	[ "$COMMENTS_SHARED" = "$shared_path" ]
	cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
	[ ! -e .review/comments.md ]
	[ -z "$(git for-each-ref --format='%(refname)' refs/review-edits/)" ]
}

@test "comments compare save advances durable checkpoint without code changes or closing" {
	run --separate-stderr comments_start compare
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Saved private.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Saved shared.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/local"
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/shared"
	printf 'dirty code\n' >>sample.txt
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments save
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" head branch refs index raw-index.bytes staged unstaged worktree objects
	run --separate-stderr git review comments add --document local --text 'Discard this.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review abort
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = main ]
	run --separate-stderr git review comments status --context "$context" --porcelain
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
	[ ! -e .review/comments.md ]
	[ -z "$(git for-each-ref --format='%(refname)' refs/heads/review-saved/)" ]
}

@test "comments review abort discards only its new preparation and keeps previous result" {
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_result
	printf 'Previous private.\n' >"$COMMENTS_RESULT_DIR/local.md"
	printf 'context\t%s\nlocal\tpresent\nshared\tabsent\n' "$COMMENTS_CONTEXT" >"$COMMENTS_RESULT_DIR/manifest"
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'New private.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local session_path=$COMMENTS_LOCAL
	run --separate-stderr git review abort
	[ "$status" -eq 0 ]
	[ ! -e "$session_path" ]
	[ "$(cat "$COMMENTS_RESULT_DIR/local.md")" = 'Previous private.' ]
}

@test "comments custody mismatch stops save before any git mutation" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Keep.'
	[ "$status" -eq 0 ]
	git config branch.review/feature/comments.reviewcommentsowner "$COMMENTS_TMP/another-worktree"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review save
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments session belongs to another gitdir' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments start isolates existing results before a reviewer edits a reported path" {
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_result
	printf 'Previous private.\n' >"$COMMENTS_RESULT_DIR/local.md"
	printf 'context\t%s\nlocal\tpresent\nshared\tabsent\n' "$COMMENTS_CONTEXT" >"$COMMENTS_RESULT_DIR/manifest"
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local session_path=$COMMENTS_LOCAL
	[ "$session_path" != "$COMMENTS_RESULT_DIR/local.md" ]
	printf 'New unsaved private.\n' >"$session_path"
	run --separate-stderr git review abort
	[ "$status" -eq 0 ]
	[ ! -e "$session_path" ]
	[ "$(cat "$COMMENTS_RESULT_DIR/local.md")" = 'Previous private.' ]
}
