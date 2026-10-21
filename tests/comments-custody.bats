#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Keep this preparation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
}
teardown() { comments_teardown; }

@test "comments save rejects a destination custody collision before banking code or creating branches" {
	git config branch.review-saved/feature/comments.reviewcommentssession 2222222222222222222222222222222222222222
	printf 'unsaved code edit\n' >>sample.txt
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review save
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: another comments session owns the destination' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments continue rejects a destination custody collision before changing HEAD or refs" {
	run --separate-stderr git review save
	[ "$status" -eq 0 ]
	git config branch.review/feature/comments.reviewcommentssession 2222222222222222222222222222222222222222
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: another comments session owns the destination' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments linked worktree never adopts the original gitdir session through shared config" {
	local session original_gitdir original_path=$COMMENTS_LOCAL
	original_gitdir=$(git rev-parse --absolute-git-dir)
	session=$(git config branch.review/feature/comments.reviewcommentssession)
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/original-prose"
	git worktree add --quiet -b review/other "$COMMENTS_TMP/linked" main
	git config branch.review/other.reviewsource feature/comments
	git config branch.review/other.reviewtip "$COMMENTS_TIP"
	git config branch.review/other.reviewbase main
	git config branch.review/other.reviewreturn main
	git config branch.review/other.reviewcommentscontext "$COMMENTS_CONTEXT"
	git config branch.review/other.reviewcommentssession "$session"
	git config branch.review/other.reviewcommentsowner "$original_gitdir"
	cd "$COMMENTS_TMP/linked"
	comments_snapshot "$COMMENTS_TMP/before-linked"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments session belongs to another gitdir' ]
	run --separate-stderr git review save
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments session belongs to another gitdir' ]
	comments_snapshot "$COMMENTS_TMP/after-linked"
	comments_assert_snapshot "$COMMENTS_TMP/before-linked" "$COMMENTS_TMP/after-linked"
	cmp "$COMMENTS_TMP/original-prose" "$original_path"
}

@test "comments session manifest must identify the same exclusive session as branch metadata" {
	local manifest
	manifest=$(dirname "$COMMENTS_LOCAL")/manifest
	awk -F '\t' 'BEGIN {OFS="\t"} $1=="session" {$2="2222222222222222222222222222222222222222"} {print}' "$manifest" >"$COMMENTS_TMP/changed-manifest"
	cp "$COMMENTS_TMP/changed-manifest" "$manifest"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review save
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments session ownership does not match' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments corrupted tip cannot become an unresolved or malformed capture record" {
	git config branch.review/feature/comments.reviewtip $'invalid\tOID'
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments capture tip is not a full object ID' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}
