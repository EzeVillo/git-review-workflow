#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Recover private prose.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Recover Shared prose.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/local"
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/shared"
	printf 'code correction\n' >>sample.txt
}
teardown() { comments_teardown; }

check_delivery_io() {
	local context=$COMMENTS_CONTEXT
	if [ "$1" = mv ]; then comments_inject_operation mv "$COMMENTS_WORK/.review/comments.md" fail
	else comments_inject_operation "$1" "$COMMENTS_WORK/.review/comments.md.candidate.*" fail
	fi
	run --separate-stderr git-review finish
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'injected operation failure'* ]]
	[[ "$stderr" == *'code was extracted but Shared comments could not be prepared'* ]]
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
	[ "$(git symbolic-ref --short HEAD)" = review-fixes/feature/comments ]
	[ "$(git rev-parse HEAD)" = "$COMMENTS_TIP" ]
	[ "$(git config branch.review/feature/comments.reviewundoouthead)" = "$COMMENTS_TIP" ]
	[ "$(git diff --cached --name-only)" = sample.txt ]
	[ ! -e .review/comments.md ]
	comments_refresh_paths
	cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery" {print $3}')" = pending ]
	local candidate
	candidate=$(find .review -type f -name 'comments.md.candidate.*' -print)
	if [ "$1" = mktemp ]; then [ -z "$candidate" ]
	else
		[ -f "$candidate" ]
		if [ "$1" = mv ]; then cmp "$COMMENTS_TMP/shared" "$candidate"; fi
	fi
	local index_before
	index_before=$(git ls-files --stage)
	run --separate-stderr git-review comments prepare --context "$context"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(git rev-parse HEAD)" = "$COMMENTS_TIP" ]
	[ "$(git ls-files --stage)" = "$index_before" ]
	cmp "$COMMENTS_TMP/shared" .review/comments.md
	comments_refresh_paths
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery" {print $3}')" = delivered ]
	cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
}

@test "comments delivery temporary creation failure records a recoverable pending finish and retries" { check_delivery_io mktemp; }
@test "comments delivery copy failure keeps both prose documents and retries only Shared" { check_delivery_io cp; }
@test "comments delivery rename failure preserves the complete candidate and retries only Shared" { check_delivery_io mv; }
