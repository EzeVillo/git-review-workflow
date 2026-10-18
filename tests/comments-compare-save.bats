#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

save_prose_without_code() {
	comments_snapshot "$COMMENTS_TMP/before-save"
	run --separate-stderr git review comments save
	[ "$status" -eq 0 ]
	[ "$output" = 'Comments saved.' ]
	[ "$stderr" = '' ]
	comments_snapshot "$COMMENTS_TMP/after-save"
	comments_assert_snapshot "$COMMENTS_TMP/before-save" "$COMMENTS_TMP/after-save" branch head refs index raw-index.bytes staged unstaged worktree objects
}

check_compare_checkpoints() {
	local saves=$1
	run --separate-stderr comments_start compare
	[ "$status" -eq 0 ]
	printf 'dirty comparison code\n' >>sample.txt
	run --separate-stderr git review comments add --document local --text 'First private checkpoint.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT local_path=$COMMENTS_LOCAL root
	root=$(git rev-parse --absolute-git-dir)/review-comments
	if [ "$saves" -gt 0 ]; then
		save_prose_without_code
		cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/expected-local"
	fi
	run --separate-stderr git review comments add --document shared --text 'Shared before a possible second checkpoint.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Second private checkpoint.'
	[ "$status" -eq 0 ]
	if [ "$saves" -eq 2 ]; then
		save_prose_without_code
		cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/expected-local"
		cp "$COMMENTS_SHARED" "$COMMENTS_TMP/expected-shared"
	fi
	run --separate-stderr git review comments add --document local --text 'Discard after the last checkpoint.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review abort
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = main ]
	[ ! -e "$local_path" ]
	[ ! -e .review/comments.md ]
	[ -z "$(git for-each-ref --format='%(refname)' refs/heads/review-saved/)" ]
	if [ "$saves" -eq 0 ]; then [ ! -e "$root/results/$context/current" ]
	else
		comments_refresh_paths
		cmp "$COMMENTS_TMP/expected-local" "$COMMENTS_LOCAL"
		comments_assert_file "$COMMENTS_SHARED" "$COMMENTS_TMP/expected-shared"
	fi
}

@test "comments comparison with zero saves discards both documents after abort" { check_compare_checkpoints 0; }
@test "comments comparison with one Local save keeps Shared absent after abort" { check_compare_checkpoints 1; }
@test "comments comparison with two saves keeps the complete second pair after abort" { check_compare_checkpoints 2; }
