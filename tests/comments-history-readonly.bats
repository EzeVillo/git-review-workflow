#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments retained historical query after clean leaves another active review entirely unchanged" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --path sample.txt --text 'Original historical observation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	run --separate-stderr git review clean --keep-fixes feature/comments
	[ "$status" -eq 0 ]
	git switch --quiet -c feature/other main
	printf 'Another PR.\n' >another.txt
	git add another.txt
	git commit --quiet -m other
	run --separate-stderr git review start --offline --no-walk feature/other
	[ "$status" -eq 0 ]
	printf 'Unrelated dirty code.\n' >>another.txt
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments diff --context "$context" --document local --entry 1 --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-diff" {print}')" = "$(printf 'comment-diff\t1\t%s\t%s' "$(git rev-parse "$COMMENTS_BASE^{tree}")" "$(git rev-parse "$COMMENTS_TIP^{tree}")")" ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}
