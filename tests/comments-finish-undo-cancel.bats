#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

check_finish_undo_cancel() {
	local mode=$1 previous=${2:-none} onto=${3:-0}
	if [ "$previous" != none ]; then comments_fixture_baseline "$previous"; fi
	run --separate-stderr comments_start "$mode"
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'New private observation.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'New Shared observation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT local_path=$COMMENTS_LOCAL shared_path=$COMMENTS_SHARED
	local pointer="$(git rev-parse --absolute-git-dir)/review-comments/results/$context/current"
	cp "$local_path" "$COMMENTS_TMP/local-current"
	cp "$shared_path" "$COMMENTS_TMP/shared-current"
	git diff --cached --binary >"$COMMENTS_TMP/index-before"
	if [ "$onto" -eq 1 ]; then
		run --separate-stderr git review finish --onto-source
	else
		run --separate-stderr git review finish
	fi
	[ "$status" -eq 0 ]
	[ "$(git diff --cached --name-only)" = .review/comments.md ]
	git show :.review/comments.md >"$COMMENTS_TMP/staged"
	cmp "$COMMENTS_TMP/shared-current" "$COMMENTS_TMP/staged"
	comments_refresh_paths
	# Edits to the retained result also return to the preparation on Undo.
	printf '\nWritten after Finish.\n' >>"$COMMENTS_LOCAL"
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/local-current"
	run --separate-stderr git review finish --abort
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = review/feature/comments ]
	[ ! -e .review/comments.md ]
	[ "$(git ls-files --stage -- .review/comments.md)" = '' ]
	git diff --cached --binary >"$COMMENTS_TMP/index-after"
	cmp "$COMMENTS_TMP/index-before" "$COMMENTS_TMP/index-after"
	comments_refresh_paths
	[ "$COMMENTS_LOCAL" = "$local_path" ]
	[ "$COMMENTS_SHARED" = "$shared_path" ]
	cmp "$COMMENTS_TMP/local-current" "$local_path"
	cmp "$COMMENTS_TMP/shared-current" "$shared_path"
	if [ "$previous" = none ]; then
		[ ! -e "$pointer" ]
	else
		[ "$(cat "$pointer")" = 4444444444444444444444444444444444444444 ]
		comments_assert_baseline
	fi
	run --separate-stderr git review abort
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = main ]
	[ "$(git status --porcelain --untracked-files=all)" = '' ]
	[ ! -e "$local_path" ]
	[ ! -e "$shared_path" ]
	[ -z "$(git for-each-ref --format='%(refname)' refs/heads/review/ refs/heads/review-fixes/ refs/review-undo/)" ]
	if [ "$previous" = none ]; then
		[ ! -e "$pointer" ]
	else
		[ "$(cat "$pointer")" = 4444444444444444444444444444444444444444 ]
		comments_assert_baseline
	fi
}

@test "comments whole finish undo and cancel discard the new pair" { check_finish_undo_cancel whole; }
@test "comments walk finish undo and cancel discard the new pair" { check_finish_undo_cancel walk; }
@test "comments step finish undo and cancel discard the new pair" { check_finish_undo_cancel step; }
@test "comments onto source finish undo and cancel discard the new pair" { check_finish_undo_cancel whole none 1; }
@test "comments finish undo and cancel restore the previous nonempty result" { check_finish_undo_cancel whole present; }
@test "comments finish undo and cancel restore the previous empty result" { check_finish_undo_cancel whole empty; }
@test "comments finish undo and cancel restore the previous absent documents" { check_finish_undo_cancel whole absent; }

start_previous_pair() {
	comments_fixture_baseline present
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'New private observation.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'New Shared observation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
}

undo_cancel_previous_pair() {
	run --separate-stderr git review finish --abort
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = review/feature/comments ]
	[ ! -e .review/comments.md ]
	[ "$(git ls-files --stage -- .review/comments.md)" = '' ]
	comments_assert_baseline
	run --separate-stderr git review abort
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = main ]
	[ "$(cat "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/current")" = 4444444444444444444444444444444444444444 ]
	comments_assert_baseline
}

@test "comments repeated finish and undo keep the original discard boundary" {
	start_previous_pair
	local attempt
	for attempt in 1 2; do
		run --separate-stderr git review finish
		[ "$status" -eq 0 ]
		run --separate-stderr git review finish --abort
		[ "$status" -eq 0 ]
		comments_refresh_paths
		[ "$(tail -n 1 "$COMMENTS_LOCAL")" = 'New private observation.' ]
		[ "$(tail -n 1 "$COMMENTS_SHARED")" = 'New Shared observation.' ]
		[ "$(cat "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/current")" = 4444444444444444444444444444444444444444 ]
		comments_assert_baseline
	done
	run --separate-stderr git review abort
	[ "$status" -eq 0 ]
	comments_assert_baseline
}

@test "comments delivery retry and undo restore the previous result before cancel" {
	start_previous_pair
	comments_inject_operation mktemp "$COMMENTS_WORK/.review/comments.md.candidate.*" fail
	run --separate-stderr git-review finish
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'code was extracted but Shared comments could not be prepared'* ]]
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
	run --separate-stderr git-review finish --resume
	[ "$status" -eq 0 ]
	[ "$(git diff --cached --name-only)" = .review/comments.md ]
	undo_cancel_previous_pair
}

@test "comments publication retry and undo restore the previous result before cancel" {
	start_previous_pair
	comments_inject_operation mv '*/current' fail
	run --separate-stderr git-review finish
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'code was extracted but comments results could not be retained'* ]]
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
	run --separate-stderr git-review comments prepare --context "$COMMENTS_CONTEXT"
	[ "$status" -eq 0 ]
	undo_cancel_previous_pair
}

@test "comments undo pointer failure preserves the staged delivery and can be retried" {
	start_previous_pair
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	local pointer="$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/current" generation index
	generation=$(cat "$pointer")
	index=$(git ls-files --stage)
	cp .review/comments.md "$COMMENTS_TMP/delivered"
	comments_inject_operation mv '*/current' fail
	run --separate-stderr git-review finish --abort
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[[ "$stderr" == *'injected operation failure'* ]]
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
	[ "$(git symbolic-ref --short HEAD)" = review-fixes/feature/comments ]
	[ "$(git ls-files --stage)" = "$index" ]
	[ "$(cat "$pointer")" = "$generation" ]
	cmp "$COMMENTS_TMP/delivered" .review/comments.md
	undo_cancel_previous_pair
}

@test "comments undo refuses a missing previous generation before changing code or prose" {
	start_previous_pair
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	rm "$COMMENTS_RESULT_DIR/manifest"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review finish --abort
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments finish result baseline is invalid; preserve the result before undoing it' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}
