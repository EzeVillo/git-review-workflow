#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	comments_fixture_context 1111111111111111111111111111111111111111
}
teardown() { comments_teardown; }

@test "comments storage rejects unsafe context tokens before constructing paths" {
	local token
	printf 'sentinel\n' >"$COMMENTS_TMP/sentinel"
	comments_snapshot "$COMMENTS_TMP/before"
	for token in ../sentinel /tmp/escape a/b '' '..' '1;touch sentinel' 'ABCDEF' '1234'; do
		run --separate-stderr git review comments status --porcelain --context "$token"
		[ "$status" -eq 1 ]
		[ "$output" = '' ]
		if [ -z "$token" ]; then [ "$stderr" = 'error: --context requires a nonempty value' ]
		else [ "$stderr" = 'error: invalid comments context token' ]
		fi
	done
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	printf 'sentinel\n' >"$COMMENTS_TMP/expected"
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_TMP/sentinel"
}

@test "comments storage rejects a symlink at every storage ancestor" {
	local component parent
	for component in review-comments contexts "$COMMENTS_CONTEXT"; do
		case "$component" in
			review-comments) parent=$(git rev-parse --absolute-git-dir) ;;
			contexts) parent="$COMMENTS_ROOT" ;;
			*) parent="$COMMENTS_ROOT/contexts" ;;
		esac
		mv "$parent/$component" "$COMMENTS_TMP/saved"
		comments_symlink "$COMMENTS_TMP/saved" "$parent/$component"
		run --separate-stderr git review comments status --porcelain --context "$COMMENTS_CONTEXT"
		[ "$status" -eq 1 ]
		[ "$output" = '' ]
		[[ "$stderr" == 'error: unsafe comments path: '* ]]
		rm "$parent/$component"
		mv "$COMMENTS_TMP/saved" "$parent/$component"
	done
}

@test "comments storage refuses another gitdir owner without adopting files" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_fixture_session
	git config branch.review/feature/comments.reviewcommentsowner "$COMMENTS_TMP/another-gitdir"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments session belongs to another gitdir' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments lock refuses an existing unknown owner and preserves it" {
	mkdir -p "$COMMENTS_ROOT/locks/$COMMENTS_CONTEXT.lock"
	printf 'unknown owner\n' >"$COMMENTS_ROOT/locks/$COMMENTS_CONTEXT.lock/owner"
	run --separate-stderr comments_driver lock "$COMMENTS_CONTEXT"
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments context is locked' ]
	[ "$(cat "$COMMENTS_ROOT/locks/$COMMENTS_CONTEXT.lock/owner")" = 'unknown owner' ]
}

@test "comments lock releases its own directory on normal return and operation error" {
	run --separate-stderr comments_driver lock "$COMMENTS_CONTEXT"
	[ "$status" -eq 0 ]
	[ "$output" = locked ]
	[ "$stderr" = '' ]
	[ ! -e "$COMMENTS_ROOT/locks/$COMMENTS_CONTEXT.lock" ]
	run --separate-stderr comments_driver write "$COMMENTS_CONTEXT" "$COMMENTS_ROOT/absent.md" "$COMMENTS_TMP/missing-candidate" absent
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[[ "$stderr" == 'error: '* ]]
	[ ! -e "$COMMENTS_ROOT/locks/$COMMENTS_CONTEXT.lock" ]
	[ ! -e "$COMMENTS_ROOT/absent.md" ]
}

@test "comments lock releases on termination after a synchronized acquisition" {
	comments_barrier_create "$COMMENTS_TMP/hold"
	comments_driver lock "$COMMENTS_CONTEXT" "$COMMENTS_TMP/hold" >"$COMMENTS_TMP/lock.out" 2>"$COMMENTS_TMP/lock.err" &
	local holder=$!
	# The bounded ready FIFO proves acquisition before the termination signal.
	comments_barrier_arrived "$COMMENTS_TMP/hold"
	[ -f "$COMMENTS_TMP/hold/arrived" ]
	local shell_pid
	shell_pid=$(awk -F '\t' '$1 == "pid" {print $2}' "$COMMENTS_ROOT/locks/$COMMENTS_CONTEXT.lock/owner")
	[[ "$shell_pid" =~ ^[0-9]+$ ]]
	kill -TERM "$shell_pid"
	# Let the waiting child complete so the parent's signal trap runs without
	# the timeout utility terminating that child and printing its own message.
	comments_barrier_resume "$COMMENTS_TMP/hold"
	local holder_status=0
	wait "$holder" || holder_status=$?
	[ "$holder_status" -eq 1 ]
	[ ! -e "$COMMENTS_ROOT/locks/$COMMENTS_CONTEXT.lock" ]
	[ "$(cat "$COMMENTS_TMP/lock.out")" = locked ]
	if [ -s "$COMMENTS_TMP/lock.err" ]; then cat "$COMMENTS_TMP/lock.err" >&2; fi
	[ ! -s "$COMMENTS_TMP/lock.err" ]
}

@test "comments writer rejects symlink targets without touching outside sentinel" {
	printf 'sentinel\n' >"$COMMENTS_TMP/sentinel"
	printf 'candidate\n' >"$COMMENTS_TMP/candidate"
	comments_symlink "$COMMENTS_TMP/sentinel" "$COMMENTS_ROOT/local.md"
	run --separate-stderr comments_driver write "$COMMENTS_CONTEXT" "$COMMENTS_ROOT/local.md" "$COMMENTS_TMP/candidate" absent
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[[ "$stderr" == 'error: unsafe comments path: '* ]]
	[ -L "$COMMENTS_ROOT/local.md" ]
	[ "$(cat "$COMMENTS_TMP/sentinel")" = sentinel ]
	[ "$(cat "$COMMENTS_TMP/candidate")" = candidate ]
}

@test "comments manifest directories are rejected instead of receiving a moved candidate" {
	local manifest="$COMMENTS_ROOT/contexts/$COMMENTS_CONTEXT/manifest"
	mv "$manifest" "$COMMENTS_TMP/context-manifest"
	mkdir "$manifest"
	run --separate-stderr git review comments status --context "$COMMENTS_CONTEXT" --porcelain
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[[ "$stderr" == 'error: unsafe comments path: '* ]]
	[ -z "$(find "$manifest" -mindepth 1 -print)" ]
}

@test "comments retained result refuses a context manifest owned by another gitdir" {
	comments_fixture_result
	printf 'Retained private prose.\n' >"$COMMENTS_RESULT_DIR/local.md"
	printf 'context\t%s\nkind\treview\nowner_gitdir\t%s\n' "$COMMENTS_CONTEXT" "$COMMENTS_TMP/foreign" >"$COMMENTS_ROOT/contexts/$COMMENTS_CONTEXT/manifest"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments status --context "$COMMENTS_CONTEXT" --porcelain
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments context belongs to another gitdir' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}
