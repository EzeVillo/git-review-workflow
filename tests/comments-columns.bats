#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
}
teardown() { comments_teardown; }

@test "comments preserves exact columns in entries history and retained results" {
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments add --document shared --path sample.txt --side head --start-line 2 --end-line 2 --start-column 2 --end-column 5 --text 'Only han.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	[ "$(sed -n '/^start-column /p;/^end-column /p' "$COMMENTS_SHARED")" = "$(printf 'start-column 2\nend-column 5')" ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" branch head refs index raw-index.bytes staged unstaged worktree objects
	local operation
	for operation in entries diff; do
		set --
		if [ "$operation" = diff ]; then set -- --entry 1; fi
		run --separate-stderr git review comments "$operation" --document shared --porcelain "$@"
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-columns" {print}')" = "$(printf 'comment-columns\t1\thead\t2\t5')" ]
	done
	run --separate-stderr git review comments renumber --document shared
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	[ "$(sed -n '/^start-column /p;/^end-column /p' .review/comments.md)" = "$(printf 'start-column 2\nend-column 5')" ]
}

@test "comments rejects incomplete empty reversed and huge columns without mutation" {
	local scenario
	for scenario in missing lines zero reversed empty outside huge; do
		set -- --path sample.txt --side head --start-line 2 --end-line 2
		case "$scenario" in
			missing) set -- "$@" --start-column 1 ;;
			lines) set -- --path sample.txt --side head --start-column 1 --end-column 2 ;;
			zero) set -- "$@" --start-column 0 --end-column 2 ;;
			reversed) set -- "$@" --start-column 5 --end-column 2 ;;
			empty) set -- "$@" --start-column 2 --end-column 2 ;;
			outside) set -- "$@" --start-column 2 --end-column 9 ;;
			huge) set -- "$@" --start-column 2 --end-column 999999999999999999999999999999999999 ;;
		esac
		comments_snapshot "$COMMENTS_TMP/before"
		run --separate-stderr git review comments add --document local --text 'Why?' "$@"
		[ "$status" -eq 1 ]
		[ "$output" = '' ]
		case "$scenario" in
			missing) [ "$stderr" = 'error: start and end columns must be positive integers provided together' ] ;;
			lines|zero) [ "$stderr" = 'error: comment columns require a line range and positive coordinates' ] ;;
			reversed|empty) [ "$stderr" = 'error: comment selection must be nonempty and ordered' ] ;;
			outside|huge) [ "$stderr" = 'error: comment selection exceeds the captured blob' ] ;;
		esac
		comments_snapshot "$COMMENTS_TMP/after"
		comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	done
}

@test "comments selection can end at next line column one including final newline" {
	run --separate-stderr git review comments add --document local --path sample.txt --side head --start-line 3 --end-line 4 --start-column 2 --end-column 1 --text 'Through newline.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	run --separate-stderr git review comments entries --document local --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-location" || $1=="comment-columns" {print}')" = "$(printf 'comment-location\t1\thead\t3\t4\ncomment-columns\t1\thead\t2\t1')" ]
}

@test "comments validates UTF16 columns for emoji tabs CRLF and unterminated EOF" {
	local tree
	printf 'a\360\237\230\200\tZ\r\nend' >unicode.txt
	git add unicode.txt
	tree=$(git write-tree)
	run --separate-stderr git review comments add --document local --base "$tree" --head "$tree" --path unicode.txt --side head --start-line 1 --end-line 1 --start-column 2 --end-column 6 --text 'Emoji tab Z.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments add --document local --base "$tree" --head "$tree" --path unicode.txt --side head --start-line 1 --end-line 1 --start-column 3 --end-column 4 --text 'Half an emoji.'
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: comment selection exceeds the captured blob' ]
	run --separate-stderr git review comments add --document local --base "$tree" --head "$tree" --path unicode.txt --side head --start-line 1 --end-line 1 --start-column 2 --end-column 7 --text 'Too far.'
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: comment selection exceeds the captured blob' ]
	run --separate-stderr git review comments add --document local --base "$tree" --head "$tree" --path unicode.txt --side head --start-line 2 --end-line 3 --start-column 1 --end-column 1 --text 'No final newline.'
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: comment selection exceeds the captured blob' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}
