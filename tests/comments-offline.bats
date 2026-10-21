#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments capture stays offline with dirty tracked and untracked code" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	printf 'dirty code\n' >>sample.txt
	printf 'untracked code\n' >new.txt
	comments_snapshot "$COMMENTS_TMP/before"
	comments_inject_operation git fetch fail
	# Calling the public dispatcher directly keeps Git from prepending its own
	# exec-path ahead of the fault wrapper used to detect an attempted fetch.
	run --separate-stderr git-review comments add --document local --text 'Offline question.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ ! -e "$COMMENTS_TMP/inject/hit" ]
	comments_refresh_paths
	[ "$(tail -n 1 "$COMMENTS_LOCAL")" = 'Offline question.' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" branch head refs index raw-index.bytes staged unstaged objects worktree
}

@test "comments general capture during a real finish conflict invents no version or objects" {
	run --separate-stderr comments_start step
	[ "$status" -eq 0 ]
	printf 'first-review\nchanged\nthird\n' >sample.txt
	run --separate-stderr git review next
	[ "$status" -eq 0 ]
	printf 'first\nchanged-review\nthird\n' >sample.txt
	run --separate-stderr git review finish
	[ "$status" -eq 1 ]
	[ "$(git config branch.review/feature/comments.reviewresume)" = conflict ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments add --document local --text 'How should these changes interact?'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-capture" {print}')" = '' ]
	[ "$(awk '/^base |^head / {print}' "$COMMENTS_LOCAL")" = '' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" branch head refs index raw-index.bytes staged unstaged objects worktree
}
