#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	run --separate-stderr comments_start compare
	[ "$status" -eq 0 ]
}
teardown() { comments_teardown; }

@test "comments compare failed publication keeps previous checkpoint and retry preserves both documents" {
	run --separate-stderr git review comments add --document local --text 'First local.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'First shared.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT root
	root=$(git rev-parse --absolute-git-dir)/review-comments
	run --separate-stderr git review comments save
	[ "$status" -eq 0 ]
	local previous
	previous=$(cat "$root/results/$context/current")
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/first-local"
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/first-shared"
	printf '\nSecond local.\n' >>"$COMMENTS_LOCAL"
	printf '\nSecond shared.\n' >>"$COMMENTS_SHARED"
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/second-local"
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/second-shared"
	comments_inject_operation mv '*/current' fail
	run --separate-stderr git-review comments save
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[[ "$stderr" == *'could not publish comments generation pointer'* ]]
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
	[ "$(cat "$root/results/$context/current")" = "$previous" ]
	cmp "$COMMENTS_TMP/first-local" "$root/results/$context/$previous/local.md"
	cmp "$COMMENTS_TMP/first-shared" "$root/results/$context/$previous/shared.md"
	cmp "$COMMENTS_TMP/second-local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/second-shared" "$COMMENTS_SHARED"
	run --separate-stderr git-review comments save
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(cat "$root/results/$context/current")" != "$previous" ]
	printf 'Discard after checkpoint.\n' >>"$COMMENTS_LOCAL"
	run --separate-stderr git review abort
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cmp "$COMMENTS_TMP/second-local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/second-shared" "$COMMENTS_SHARED"
	[ ! -e .review/comments.md ]
}

@test "comments compare without save discards preparation and never creates a retained result" {
	run --separate-stderr git review comments add --document local --text 'Not saved.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT root path=$COMMENTS_LOCAL
	root=$(git rev-parse --absolute-git-dir)/review-comments
	run --separate-stderr git review abort
	[ "$status" -eq 0 ]
	[ ! -e "$path" ]
	[ ! -e "$root/results/$context/current" ]
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$output" = $'comments-identity\tfresh\tNo comments context yet.' ]
}

@test "comments compare save rechecks the original context before publishing a generation" {
	run --separate-stderr git review comments add --document local --text 'First checkpoint.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT root
	root=$(git rev-parse --absolute-git-dir)/review-comments
	run --separate-stderr git review comments save
	[ "$status" -eq 0 ]
	local previous
	previous=$(cat "$root/results/$context/current")
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/previous-local"
	printf '\nNew preparation.\n' >>"$COMMENTS_LOCAL"
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/preparation"
	comments_inject_operation cp '*/local.md' barrier
	git-review comments save >"$COMMENTS_TMP/writer.out" 2>"$COMMENTS_TMP/writer.err" &
	local writer=$!
	comments_barrier_arrived "$COMMENTS_TMP/inject"
	git config branch.review/feature/comments.reviewtip "$COMMENTS_BASE"
	comments_barrier_resume "$COMMENTS_TMP/inject"
	local writer_status=0
	wait "$writer" || writer_status=$?
	[ "$writer_status" -eq 4 ]
	[ ! -s "$COMMENTS_TMP/writer.out" ]
	[ "$(cat "$COMMENTS_TMP/writer.err")" = 'error: comments context is stale' ]
	[ "$(cat "$root/results/$context/current")" = "$previous" ]
	cmp "$COMMENTS_TMP/previous-local" "$root/results/$context/$previous/local.md"
	cmp "$COMMENTS_TMP/preparation" "$COMMENTS_LOCAL"
}

check_pair_revision_guard() {
	run --separate-stderr git review comments add --document local --text 'Private checkpoint.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Shared checkpoint.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local local_revision shared_revision
	local_revision=$(git hash-object --no-filters "$COMMENTS_LOCAL")
	shared_revision=$(git hash-object --no-filters "$COMMENTS_SHARED")
	run --separate-stderr git review comments save
	[ "$status" -eq 0 ]
	if [ "$1" = local ]; then printf '\nNew local edit.\n' >>"$COMMENTS_LOCAL"
	else printf '\nNew shared edit.\n' >>"$COMMENTS_SHARED"
	fi
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments save --expect-local "$local_revision" --expect-shared "$shared_revision"
	[ "$status" -eq 4 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments document is stale' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments compare stale Local revision never advances either half of the checkpoint" { check_pair_revision_guard local; }
@test "comments compare stale Shared revision never advances either half of the checkpoint" { check_pair_revision_guard shared; }

@test "comments save outside compare returns two without changing review state" {
	run --separate-stderr git review abort
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments save
	[ "$status" -eq 2 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: saving comments requires an active compare' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/before-review"
	run --separate-stderr git review comments save
	[ "$status" -eq 2 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: saving comments requires an active compare' ]
	comments_snapshot "$COMMENTS_TMP/after-review"
	comments_assert_snapshot "$COMMENTS_TMP/before-review" "$COMMENTS_TMP/after-review"
}
