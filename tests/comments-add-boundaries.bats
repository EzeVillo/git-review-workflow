#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments init --document local
	[ "$status" -eq 0 ]
	comments_refresh_paths
}
teardown() { comments_teardown; }

@test "comments add rejects open fence or HTML without changing original or another document" {
	local fixture
	for fixture in open-fence open-html; do
		cp "$BATS_TEST_DIRNAME/fixtures/comments/$fixture.md" "$COMMENTS_LOCAL"
		comments_snapshot "$COMMENTS_TMP/before"
		run --separate-stderr git review comments add --document local --text 'Visible question.'
		[ "$status" -eq 1 ]
		[ "$output" = '' ]
		[ "$stderr" = 'error: close the open code fence or HTML comment before adding a comment' ]
		comments_snapshot "$COMMENTS_TMP/after"
		comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	done
}

@test "comments input reserved heading must be fenced and exactly one block is added" {
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments add --document local --text $'Question\n## 88. example'
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: fence or quote reserved headings and close code or HTML containers in the comment text' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	run --separate-stderr git review comments add --document local --text $'Question\n~~~md\n## 88. example\n~~~'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-count" {print $3}')" = 1 ]
}
