#!/usr/bin/env bats

load helpers/comments

setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments oracle detects a same-length byte edit" {
	printf 'alpha\n' >"$COMMENTS_TMP/expected"
	printf 'alpHa\n' >"$COMMENTS_TMP/actual"
	run --separate-stderr comments_assert_file "$COMMENTS_TMP/actual" "$COMMENTS_TMP/expected"
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'file bytes differ' ]
}

@test "comments oracle distinguishes absent from empty" {
	: >"$COMMENTS_TMP/empty"
	run --separate-stderr comments_assert_file "$COMMENTS_TMP/absent" "$COMMENTS_TMP/empty"
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'file presence differs' ]
}

@test "comments oracle accepts byte-identical documents including final LF" {
	cp "$BATS_TEST_DIRNAME/fixtures/comments/mixed-eol.md" "$COMMENTS_TMP/copy"
	run --separate-stderr comments_assert_file "$COMMENTS_TMP/copy" "$BATS_TEST_DIRNAME/fixtures/comments/mixed-eol.md"
	[ "$status" -eq 0 ]
	[ "$output" = '' ]
	[ "$stderr" = '' ]
}

@test "comments snapshot detects a ref change" {
	comments_snapshot "$COMMENTS_TMP/before"
	git update-ref refs/test/oracle HEAD
	comments_snapshot "$COMMENTS_TMP/after"
	run --separate-stderr comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" refs
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'snapshot differs: refs' ]
}

@test "comments snapshot detects a config change" {
	comments_snapshot "$COMMENTS_TMP/before"
	git config reviewworkflow.oracle changed
	comments_snapshot "$COMMENTS_TMP/after"
	run --separate-stderr comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" config
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'snapshot differs: config' ]
}

@test "comments snapshot detects an index entry change" {
	comments_snapshot "$COMMENTS_TMP/before"
	git update-index --chmod=+x sample.txt
	comments_snapshot "$COMMENTS_TMP/after"
	run --separate-stderr comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" index
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'snapshot differs: index' ]
}

@test "comments snapshot detects prose and storage changes outside worktree" {
	local root
	root="$(git rev-parse --absolute-git-dir)/review-comments"
	mkdir -p "$root/sessions/test"
	printf 'alpha\n' >"$root/sessions/test/local.md"
	comments_snapshot "$COMMENTS_TMP/before"
	printf 'alpHa\n' >"$root/sessions/test/local.md"
	comments_snapshot "$COMMENTS_TMP/after"
	run --separate-stderr comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" comments
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'snapshot differs: comments' ]
}

@test "comments snapshot is read-only including raw index and object inventory" {
	printf 'untracked\n' >'untracked file.txt'
	printf 'dirty\n' >>sample.txt
	local gitdir
	gitdir=$(git rev-parse --absolute-git-dir)
	cp "$gitdir/index" "$COMMENTS_TMP/index-before-first-read"
	git for-each-ref --format='%(refname) %(objectname)' >"$COMMENTS_TMP/refs-before-first-read"
	git config --null --list >"$COMMENTS_TMP/config-before-first-read"
	comments_inventory "$gitdir/objects" >"$COMMENTS_TMP/objects-before-first-read"
	comments_snapshot "$COMMENTS_TMP/before"
	cmp "$COMMENTS_TMP/index-before-first-read" "$gitdir/index"
	cmp "$COMMENTS_TMP/config-before-first-read" "$COMMENTS_TMP/before/config"
	cmp "$COMMENTS_TMP/refs-before-first-read" "$COMMENTS_TMP/before/refs"
	cmp "$COMMENTS_TMP/objects-before-first-read" "$COMMENTS_TMP/before/objects"
	[ ! -e "$gitdir/review-comments" ]
	comments_snapshot "$COMMENTS_TMP/after"
	run --separate-stderr comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	[ "$status" -eq 0 ]
	[ "$output" = '' ]
	[ "$stderr" = '' ]
}

@test "comments snapshot refuses destinations inside observed storage" {
	run --separate-stderr comments_snapshot "$COMMENTS_WORK/.git/oracle"
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'snapshot must be outside observed storage' ]
	[ ! -e "$COMMENTS_WORK/.git/oracle" ]
}

@test "comments barrier fails when no writer reaches rendezvous" {
	comments_barrier_create "$COMMENTS_TMP/barrier"
	run --separate-stderr comments_barrier_wait "$COMMENTS_TMP/barrier" 1
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = "barrier not released: $COMMENTS_TMP/barrier" ]
	[ -f "$COMMENTS_TMP/barrier/arrived" ]
}

@test "comments barrier synchronizes two participants" {
	comments_barrier_create "$COMMENTS_TMP/barrier"
	comments_barrier_release "$COMMENTS_TMP/barrier" &
	local writer=$!
	run --separate-stderr comments_barrier_wait "$COMMENTS_TMP/barrier"
	[ "$status" -eq 0 ]
	[ "$output" = '' ]
	[ "$stderr" = '' ]
	wait "$writer"
}

@test "comments barrier arrival fails within its bound when the writer never arrives" {
	comments_barrier_create "$COMMENTS_TMP/barrier"
	run --separate-stderr comments_barrier_arrived "$COMMENTS_TMP/barrier" 1
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = "barrier not reached: $COMMENTS_TMP/barrier" ]
}

@test "comments operation fault records its hit and fails exactly once" {
	printf 'source\n' >"$COMMENTS_TMP/source"
	comments_inject_operation cp '*/destination' fail
	run --separate-stderr cp "$COMMENTS_TMP/source" "$COMMENTS_TMP/destination"
	[ "$status" -eq 73 ]
	[ "$output" = '' ]
	[ "$stderr" = 'injected operation failure' ]
	[ ! -e "$COMMENTS_TMP/destination" ]
	[ "$(cat "$COMMENTS_TMP/inject/hit/argument")" = "$COMMENTS_TMP/destination" ]
	run --separate-stderr cp "$COMMENTS_TMP/source" "$COMMENTS_TMP/destination"
	[ "$status" -eq 0 ]
	[ "$output" = '' ]
	[ "$stderr" = '' ]
	cmp "$COMMENTS_TMP/source" "$COMMENTS_TMP/destination"
}

@test "comments injected operation waits for a real release before publishing" {
	printf 'source\n' >"$COMMENTS_TMP/source"
	comments_inject_operation mv '*/destination' barrier
	comments_barrier_release "$COMMENTS_TMP/inject" &
	local releaser=$!
	run --separate-stderr mv "$COMMENTS_TMP/source" "$COMMENTS_TMP/destination"
	[ "$status" -eq 0 ]
	[ "$output" = '' ]
	[ "$stderr" = '' ]
	wait "$releaser"
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
	[ ! -e "$COMMENTS_TMP/source" ]
	printf 'source\n' >"$COMMENTS_TMP/expected"
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_TMP/destination"
}

@test "comments temporary repositories cover whole walk step and compare" {
	local mode
	for mode in whole walk step compare; do
		# Each mode needs its own repository: no abort command is under test here.
		COMMENTS_WORK="$COMMENTS_TMP/$mode"
		git clone --quiet --no-hardlinks "$COMMENTS_TMP/work" "$COMMENTS_WORK"
		cd "$COMMENTS_WORK"
		git branch feature/comments origin/feature/comments
		git config reviewworkflow.base main
		run --separate-stderr comments_start "$mode"
		[ "$status" -eq 0 ]
		run --separate-stderr git review status --porcelain
		[ "$status" -eq 0 ]
		local expected_mode="$mode"
		if [ "$mode" = compare ]; then expected_mode=whole; fi
		[ "$(printf '%s\n' "$output" | awk -F '\t' '$1 == "state" {print $5}')" = "$expected_mode" ]
	done
}
