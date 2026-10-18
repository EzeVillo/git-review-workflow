#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

prepare_pending_fixture() {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Private observation.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Prepared Shared observation.'
	[ "$status" -eq 0 ]
	mkdir .review
	printf 'Concurrent destination prose.\n' >.review/comments.md
	run --separate-stderr git review finish
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'code was extracted but Shared comments could not be prepared'* ]]
	comments_refresh_paths
}

@test "comments prepare check returns exact role presence revisions and pending state as a read only query" {
	prepare_pending_fixture
	local baseline prepared_revision destination_revision
	baseline=$(dirname "$COMMENTS_SHARED")/source-baseline.md
	prepared_revision=$(git hash-object --no-filters "$COMMENTS_SHARED")
	destination_revision=$(git hash-object --no-filters .review/comments.md)
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments prepare --context "$COMMENTS_CONTEXT" --check --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$output" = "$(printf 'comments-delivery\t%s\tpending\tShared comments delivery.\ncomments-delivery-file\t%s\tbaseline\tabsent\tabsent\ncomments-delivery-file\t%s\tprepared\tpresent\t%s\ncomments-delivery-file\t%s\tdestination\tpresent\t%s' "$COMMENTS_CONTEXT" "$baseline" "$COMMENTS_SHARED" "$prepared_revision" "$COMMENTS_WORK/.review/comments.md" "$destination_revision")" ]
	run --separate-stderr git review comments prepare --context "$COMMENTS_CONTEXT" --check
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[[ "$output" == *'Concurrent destination prose.'* ]]
	[[ "$output" == *'Prepared Shared observation.'* ]]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments prepare check read failure returns one without a partial usable role stream" {
	prepare_pending_fixture
	comments_inject_operation git "$COMMENTS_SHARED" fail
	run --separate-stderr git-review comments prepare --context "$COMMENTS_CONTEXT" --check --porcelain
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'injected operation failure' ]
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
}

@test "comments prepare check rejects an unsafe private baseline instead of reporting it absent" {
	prepare_pending_fixture
	local baseline
	baseline=$(dirname "$COMMENTS_SHARED")/source-baseline.md
	mkdir "$baseline"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments prepare --context "$COMMENTS_CONTEXT" --check --porcelain
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = "error: unsafe comments path: $baseline" ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments prepare refuses porcelain without check and offers no force overwrite option" {
	prepare_pending_fixture
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments prepare --context "$COMMENTS_CONTEXT" --porcelain
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: prepare requires --context; --porcelain requires --check' ]
	run --separate-stderr git review comments prepare --context "$COMMENTS_CONTEXT" --force
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: unexpected comments argument: --force' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments prepare never converts a comparison result into a versioned Shared delivery" {
	run --separate-stderr comments_start compare
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Local comparison result.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments save
	[ "$status" -eq 0 ]
	comments_refresh_paths
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments prepare --context "$COMMENTS_CONTEXT"
	[ "$status" -eq 2 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: there is no pending Shared delivery for this context' ]
	[ ! -e .review/comments.md ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments prepare rejects a stale prepared revision before changing destination or closure metadata" {
	prepare_pending_fixture
	local revision
	revision=$(git hash-object --no-filters "$COMMENTS_SHARED")
	printf '\nNew prepared prose.\n' >>"$COMMENTS_SHARED"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments prepare --context "$COMMENTS_CONTEXT" --expect-document "$revision"
	[ "$status" -eq 4 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments document is stale' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}
