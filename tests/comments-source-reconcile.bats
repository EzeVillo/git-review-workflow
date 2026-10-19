#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	git switch --quiet feature/comments
	mkdir .review
	printf 'Original source.\n' >.review/comments.md
	git add .review/comments.md
	git commit --quiet -m source-comments
	COMMENTS_TIP=$(git rev-parse HEAD)
	git switch --quiet main
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_result
	printf 'Original source.\n' >"$COMMENTS_RESULT_DIR/source-baseline.md"
	printf 'context\t%s\nlocal\tabsent\nshared\tpresent\n' "$COMMENTS_CONTEXT" >"$COMMENTS_RESULT_DIR/manifest"
}
teardown() { comments_teardown; }

start_with_source() {
	git switch --quiet feature/comments
	printf '%s\n' "$1" >.review/comments.md
	git add .review/comments.md
	git commit --quiet --allow-empty -m next-pass
	git switch --quiet main
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments init --document local
	[ "$status" -eq 0 ]
	comments_refresh_paths
}

@test "comments source unchanged continues retained Shared without involving Local" {
	printf 'Retained questions.\n' >"$COMMENTS_RESULT_DIR/shared.md"
	start_with_source 'Original source.'
	printf 'Retained questions.\n' >"$COMMENTS_TMP/expected"
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_SHARED"
}

@test "comments source equal to retained Shared continues that exact content" {
	printf 'Both versions.\n' >"$COMMENTS_RESULT_DIR/shared.md"
	start_with_source 'Both versions.'
	printf 'Both versions.\n' >"$COMMENTS_TMP/expected"
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_SHARED"
}

@test "comments unchanged retained Shared adopts an updated source" {
	printf 'Original source.\n' >"$COMMENTS_RESULT_DIR/shared.md"
	start_with_source 'New source questions.'
	printf 'New source questions.\n' >"$COMMENTS_TMP/expected"
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_SHARED"
}

@test "comments separately changed source and Shared preserve both and diagnose conflict" {
	printf 'Retained questions.\n' >"$COMMENTS_RESULT_DIR/shared.md"
	start_with_source 'New source questions.'
	printf 'Retained questions.\n' >"$COMMENTS_TMP/expected"
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_SHARED"
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-diagnostic" {print $3}')" = source-conflict ]
	[ "$(cat .review/comments.md)" = 'New source questions.' ]
	run --separate-stderr git review finish
	[ "$status" -eq 1 ]
	[ "$(cat .review/comments.md)" = 'New source questions.' ]
}

@test "comments resolved source conflict stays resolved through finish undo and another finish" {
	printf 'Retained questions.\n' >"$COMMENTS_RESULT_DIR/shared.md"
	start_with_source 'New source questions.'
	run --separate-stderr git review finish
	[ "$status" -eq 1 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT
	printf 'Deliberate resolution of both versions.\n' >"$COMMENTS_SHARED"
	cp "$COMMENTS_SHARED" .review/comments.md
	run --separate-stderr git review comments prepare --context "$context"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-diagnostic" && $3=="source-conflict" {print}')" = '' ]
	run --separate-stderr git review finish --abort
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-diagnostic" && $3=="source-conflict" {print}')" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery" {print $3}')" = prepared ]
	[ "$(cat "$COMMENTS_SHARED")" = 'Deliberate resolution of both versions.' ]
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	[ "$(cat .review/comments.md)" = 'Deliberate resolution of both versions.' ]
}
