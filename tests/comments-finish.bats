#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
}
teardown() { comments_teardown; }

@test "comments finish delivers only Shared without creating a correction commit" {
	run --separate-stderr git review comments add --document local --text 'Private only.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Shared question.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/expected"
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = review-fixes/feature/comments ]
	[ "$(git rev-parse HEAD)" = "$COMMENTS_TIP" ]
	cmp "$COMMENTS_TMP/expected" .review/comments.md
	git diff --cached --exit-code
	[ "$(git ls-files -- .review/comments.md)" = '' ]
	[ "$(git status --porcelain --untracked-files=all)" = '?? .review/comments.md' ]
	comments_refresh_paths
	[ "$(tail -n 1 "$COMMENTS_LOCAL")" = 'Private only.' ]
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_SHARED"
}

@test "comments finish private only preserves a result without creating a shared file" {
	run --separate-stderr git review comments add --document local --text 'Private only.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	[ ! -e .review/comments.md ]
	comments_refresh_paths
	[ "$(tail -n 1 "$COMMENTS_LOCAL")" = 'Private only.' ]
	[ ! -e "$COMMENTS_SHARED" ]
}

@test "comments finish undo keeps prose and removes its untracked delivery from review code" {
	run --separate-stderr git review comments add --document shared --text 'Shared question.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/expected"
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	cmp "$COMMENTS_TMP/expected" .review/comments.md
	run --separate-stderr git review finish --abort
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = review/feature/comments ]
	[ ! -e .review/comments.md ]
	comments_refresh_paths
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_SHARED"
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery" {print $3}')" = prepared ]
	git diff --exit-code
}

@test "comments pending delivery preserves destination and retry never extracts code twice" {
	run --separate-stderr git review comments add --document shared --text 'Prepared question.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/prepared"
	mkdir .review
	printf 'Separate destination change.\n' >.review/comments.md
	run --separate-stderr git review finish
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'code was extracted but Shared comments could not be prepared'* ]]
	[ "$(git symbolic-ref --short HEAD)" = review-fixes/feature/comments ]
	[ "$(cat .review/comments.md)" = 'Separate destination change.' ]
	local head_after_code
	head_after_code=$(git rev-parse HEAD)
	run --separate-stderr git review comments prepare --context "$context" --check --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery-file" {print $3}')" = "$(printf 'baseline\nprepared\ndestination')" ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery" {print $2 "\t" $3}')" = "$(printf '%s\tpending' "$context")" ]
	cp "$COMMENTS_TMP/prepared" .review/comments.md
	printf 'Later code edit.\n' >>sample.txt
	run --separate-stderr git review finish --resume
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$head_after_code" ]
	cmp "$COMMENTS_TMP/prepared" .review/comments.md
	run --separate-stderr git review finish --abort
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'has changes since the finish'* ]]
	[ "$(tail -n 1 sample.txt)" = 'Later code edit.' ]
}

@test "comments finish undo from another branch keeps prose and respects the existing code undo flow" {
	run --separate-stderr git review comments add --document shared --text 'Keep this Shared question.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/expected"
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	git switch --quiet main
	run --separate-stderr git review finish --abort
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = review/feature/comments ]
	[ ! -e .review/comments.md ]
	comments_refresh_paths
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_SHARED"
	git diff --exit-code
}
