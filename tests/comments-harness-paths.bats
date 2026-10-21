#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments fixture uses the Git absolute worktree path even when its temp prefix is a symlink" {
	mkdir "$COMMENTS_TMP/physical"
	comments_symlink "$COMMENTS_TMP/physical" "$COMMENTS_TMP/alias"
	[ -L "$COMMENTS_TMP/alias" ]
	run --separate-stderr env TMPDIR="$COMMENTS_TMP/alias" bash -c '
		export BATS_TEST_DIRNAME="$1"
		source "$1/helpers/comments.bash"
		comments_setup || exit 2
		actual=$(git rev-parse --show-toplevel) || exit 2
		result=0
		[ "$COMMENTS_WORK" = "$actual" ] || result=1
		comments_teardown
		exit "$result"
	' bash "$BATS_TEST_DIRNAME"
	[ "$status" -eq 0 ]
	[ "$output" = '' ]
	[ "$stderr" = '' ]
}
