#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments unchanged manual Shared source is not rewritten when only Local changes" {
	git switch --quiet feature/comments
	mkdir .review
	printf '# Existing manual comments\n\nKeep this original prose without metadata.\n' >.review/comments.md
	git add .review/comments.md
	git commit --quiet -m 'existing Shared source'
	local tip
	tip=$(git rev-parse HEAD)
	cp .review/comments.md "$COMMENTS_TMP/source"
	git switch --quiet main
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Only private prose changes.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cmp "$COMMENTS_TMP/source" "$COMMENTS_SHARED"
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$tip" ]
	cmp "$COMMENTS_TMP/source" .review/comments.md
	[ "$(git status --porcelain --untracked-files=all)" = '' ]
	comments_refresh_paths
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery" {print $3}')" = unchanged ]
	cmp "$COMMENTS_TMP/source" "$COMMENTS_SHARED"
}

@test "comments inherited Shared is only a destination baseline and is not chosen as this PR seed" {
	mkdir .review
	printf '# Comments inherited from the integration base\n\nNot observations about this PR.\n' >.review/comments.md
	git add .review/comments.md
	git commit --quiet -m 'integration base Shared'
	cp .review/comments.md "$COMMENTS_TMP/inherited"
	git switch --quiet feature/comments
	git merge --quiet --no-edit main
	local tip
	tip=$(git rev-parse HEAD)
	git switch --quiet main
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Private observation about this PR.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ ! -e "$COMMENTS_SHARED" ]
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$tip" ]
	cmp "$COMMENTS_TMP/inherited" .review/comments.md
	[ "$(git status --porcelain --untracked-files=all)" = '' ]
	comments_refresh_paths
	[ ! -e "$COMMENTS_SHARED" ]
	run --separate-stderr git review finish --abort
	[ "$status" -eq 0 ]
	cmp "$COMMENTS_TMP/inherited" .review/comments.md
}
