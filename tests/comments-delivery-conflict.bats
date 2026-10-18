#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

check_destination_change() {
	local state=$1
	if [ "$state" != created ] && [ "$state" != symlink ]; then
		git switch --quiet feature/comments
		mkdir .review
		printf 'Original Shared source.\n' >.review/comments.md
		git add .review/comments.md
		git commit --quiet -m 'Shared destination baseline'
		git switch --quiet main
	fi
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	local tip
	tip=$(git config branch.review/feature/comments.reviewtip)
	run --separate-stderr git review comments add --document local --text 'Private observation.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Prepared Shared observation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/local"
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/prepared"
	# Rendezvous after code extraction and before the output branch switch.
	# Its .review path is unchanged between both trees, so Git carries the
	# concurrent prose change rather than incorporating it into extracted code.
	comments_inject_operation git review-fixes/feature/comments barrier
	git-review finish >"$COMMENTS_TMP/finish.out" 2>"$COMMENTS_TMP/finish.err" &
	local writer=$!
	comments_barrier_arrived "$COMMENTS_TMP/inject"
	case "$state" in
		changed) printf 'Concurrent destination prose.\n' >.review/comments.md ;;
		created) mkdir .review; printf 'Concurrent destination prose.\n' >.review/comments.md ;;
		deleted) rm .review/comments.md ;;
		empty) : >.review/comments.md ;;
		directory) rm .review/comments.md; mkdir .review/comments.md; printf 'child sentinel\n' >.review/comments.md/sentinel ;;
		symlink) printf 'outside sentinel\n' >"$COMMENTS_TMP/outside"; mkdir .review; comments_symlink "$COMMENTS_TMP/outside" .review/comments.md ;;
		equal) cp "$COMMENTS_TMP/prepared" .review/comments.md ;;
		*) return 1 ;;
	esac
	comments_barrier_resume "$COMMENTS_TMP/inject"
	local finish_status=0
	wait "$writer" || finish_status=$?
	if [ "$state" = equal ]; then [ "$finish_status" -eq 0 ]
	else
		[ "$finish_status" -eq 1 ]
		[[ "$(cat "$COMMENTS_TMP/finish.err")" == *'code was extracted but Shared comments could not be prepared'* ]]
	fi
	[ "$(git symbolic-ref --short HEAD)" = review-fixes/feature/comments ]
	[ "$(git rev-parse HEAD)" = "$tip" ]
	[ "$(git diff --cached --name-only)" = '' ]
	case "$state" in
		changed|created) printf 'Concurrent destination prose.\n' >"$COMMENTS_TMP/expected"; cmp "$COMMENTS_TMP/expected" .review/comments.md ;;
		deleted) [ ! -e .review/comments.md ] ;;
		empty) [ -f .review/comments.md ]; [ ! -s .review/comments.md ] ;;
		directory) [ "$(cat .review/comments.md/sentinel)" = 'child sentinel' ] ;;
		symlink) [ -L .review/comments.md ]; [ "$(cat "$COMMENTS_TMP/outside")" = 'outside sentinel' ] ;;
		equal) cmp "$COMMENTS_TMP/prepared" .review/comments.md ;;
	esac
	comments_refresh_paths
	cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/prepared" "$COMMENTS_SHARED"
	local delivery=pending
	if [ "$state" = equal ]; then delivery=delivered; fi
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery" {print $3}')" = "$delivery" ]
}

@test "comments delivery preserves a concurrently changed destination" { check_destination_change changed; }
@test "comments delivery preserves a concurrently created destination" { check_destination_change created; }
@test "comments delivery preserves a concurrently deleted destination" { check_destination_change deleted; }
@test "comments delivery distinguishes a concurrently emptied destination from absence" { check_destination_change empty; }
@test "comments delivery rejects a directory destination without touching its child" { check_destination_change directory; }
@test "comments delivery rejects a symlink destination without touching its target" { check_destination_change symlink; }
@test "comments delivery recognizes destination already equal to prepared as successful" { check_destination_change equal; }
