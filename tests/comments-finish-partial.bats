#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments finish failed result publication exposes the complete preparation and retries without replay" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Recover this private observation.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Recover this shared observation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT local_path=$COMMENTS_LOCAL shared_path=$COMMENTS_SHARED
	cp "$local_path" "$COMMENTS_TMP/local"
	cp "$shared_path" "$COMMENTS_TMP/shared"
	comments_inject_operation mv '*/current' fail
	run --separate-stderr git-review finish
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'code was extracted but comments results could not be retained'* ]]
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
	[ "$(git symbolic-ref --short HEAD)" = review-fixes/feature/comments ]
	[ "$(git rev-parse HEAD)" = "$COMMENTS_TIP" ]
	cmp "$COMMENTS_TMP/shared" .review/comments.md
	comments_refresh_paths
	[ "$COMMENTS_LOCAL" = "$local_path" ]
	[ "$COMMENTS_SHARED" = "$shared_path" ]
	cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
	run --separate-stderr git-review comments prepare --context "$context"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(git rev-parse HEAD)" = "$COMMENTS_TIP" ]
	comments_refresh_paths
	[ "$COMMENTS_LOCAL" != "$local_path" ]
	cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
}
