#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments absent source unchanged from absent baseline keeps both retained documents" {
	comments_fixture_baseline present
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cmp "$COMMENTS_TMP/baseline-local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/baseline-shared" "$COMMENTS_SHARED"
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-diagnostic" {print}')" = '' ]
}

@test "comments unchanged empty retained Shared adopts the authors deletion as absence" {
	git switch --quiet feature/comments
	mkdir .review
	: >.review/comments.md
	git add .review/comments.md
	git commit --quiet -m 'empty source'
	COMMENTS_TIP=$(git rev-parse HEAD)
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_result
	printf 'Local sentinel.\n' >"$COMMENTS_RESULT_DIR/local.md"
	: >"$COMMENTS_RESULT_DIR/shared.md"
	: >"$COMMENTS_RESULT_DIR/source-baseline.md"
	printf 'context\t%s\nlocal\tpresent\nshared\tpresent\n' "$COMMENTS_CONTEXT" >"$COMMENTS_RESULT_DIR/manifest"
	git rm --quiet .review/comments.md
	git commit --quiet -m 'author deletes source'
	git switch --quiet main
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ ! -e "$COMMENTS_SHARED" ]
	[ "$(cat "$COMMENTS_LOCAL")" = 'Local sentinel.' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-diagnostic" {print}')" = '' ]
}

@test "comments empty retained Shared and new source both differ from absent baseline and remain separate" {
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_result
	printf 'Local sentinel.\n' >"$COMMENTS_RESULT_DIR/local.md"
	: >"$COMMENTS_RESULT_DIR/shared.md"
	printf 'context\t%s\nlocal\tpresent\nshared\tpresent\n' "$COMMENTS_CONTEXT" >"$COMMENTS_RESULT_DIR/manifest"
	git switch --quiet feature/comments
	mkdir .review
	printf 'New author source.\n' >.review/comments.md
	git add .review/comments.md
	git commit --quiet -m 'new source'
	git switch --quiet main
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ -f "$COMMENTS_SHARED" ]
	[ ! -s "$COMMENTS_SHARED" ]
	[ "$(cat "$COMMENTS_LOCAL")" = 'Local sentinel.' ]
	[ "$(cat .review/comments.md)" = 'New author source.' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-diagnostic" {print $3}')" = source-conflict ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' -v path="$COMMENTS_SHARED" '$1=="comments-count" && $2==path {print $3}')" = 0 ]
}
