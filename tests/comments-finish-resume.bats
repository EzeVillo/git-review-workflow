#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments step retry after completed replay keeps every code ref and index entry unchanged" {
	run --separate-stderr comments_start step
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Private step observation.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Shared step observation.'
	[ "$status" -eq 0 ]
	printf 'first review correction\n' >>sample.txt
	run --separate-stderr git review next
	[ "$status" -eq 0 ]
	printf 'second review correction\n' >>'other file.txt'
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/prepared"
	comments_inject_operation mv "$COMMENTS_WORK/.review/comments.md" fail
	run --separate-stderr git-review finish
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'code was extracted but Shared comments could not be prepared'* ]]
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
	[ "$(git diff --cached --name-only)" = $'other file.txt\nsample.txt' ]
	local review_head refs index
	review_head=$(git rev-parse review/feature/comments)
	refs=$(git for-each-ref --format='%(refname) %(objectname)')
	index=$(git ls-files --stage)
	run --separate-stderr git-review finish --resume
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(git rev-parse review/feature/comments)" = "$review_head" ]
	[ "$(git for-each-ref --format='%(refname) %(objectname)')" = "$refs" ]
	[ "$(git ls-files --stage)" = "$index" ]
	cmp "$COMMENTS_TMP/prepared" .review/comments.md
	comments_snapshot "$COMMENTS_TMP/before-repeat"
	run --separate-stderr git-review comments prepare --context "$context"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_snapshot "$COMMENTS_TMP/after-repeat"
	comments_assert_snapshot "$COMMENTS_TMP/before-repeat" "$COMMENTS_TMP/after-repeat"
}

prepare_pending_destination_conflict() {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Pending Shared observation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	mkdir .review
	printf 'Concurrent destination prose.\n' >.review/comments.md
	run --separate-stderr git review finish
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'code was extracted but Shared comments could not be prepared'* ]]
}

@test "comments pending prepare refuses another branch before touching either prose" {
	prepare_pending_destination_conflict
	git switch --quiet --discard-changes main
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments prepare --context "$COMMENTS_CONTEXT"
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: Shared delivery belongs to another branch or destination' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments pending prepare revalidates source custody even when a retained generation exists" {
	prepare_pending_destination_conflict
	git config branch.review/feature/comments.reviewcommentsowner "$COMMENTS_TMP/foreign"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments prepare --context "$COMMENTS_CONTEXT" --check --porcelain
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments session belongs to another gitdir' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}
