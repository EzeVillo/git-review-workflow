#!/usr/bin/env bats
#
# Tests for reviewworkflow.remote: the review commands default to "origin" but
# can be pointed at any remote (e.g. an upstream you review but do not own).
# Here the remote is named "upstream" and there is no "origin" at all, so any
# leftover hardcoded "origin" would fail loudly.

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"

	git config --global user.email t@example.com
	git config --global user.name tester
	git config --global init.defaultBranch develop

	UPSTREAM="$TMP/upstream.git"
	WORK="$TMP/work"
	git init --quiet --bare "$UPSTREAM"
	git init --quiet "$WORK"
	cd "$WORK"
	git remote add upstream "$UPSTREAM"
	git config reviewworkflow.base develop
	git config reviewworkflow.remote upstream

	printf 'a\nb\nc\n' >app.txt
	git add app.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u upstream develop

	git switch --quiet -c feature/x
	printf 'a\nB\nc\nd\n' >app.txt
	git add app.txt
	git commit --quiet -m pr1
	git push --quiet -u upstream feature/x

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

@test "review-pr reviews from the configured remote" {
	run git review-pr feature/x
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git diff --cached
	[[ "$output" == *"+B"* ]]
	[[ "$output" == *"+d"* ]]
}

@test "review-pr range message names the configured remote" {
	run git review-pr feature/x develop
	[ "$status" -eq 0 ]
	[[ "$output" == *"vs upstream/develop"* ]]
}

@test "review-pr error names the configured remote, not origin" {
	run git review-pr nope/nope
	[ "$status" -ne 0 ]
	[[ "$output" == *"upstream/nope/nope not found"* ]]
	[[ "$output" != *"origin/"* ]]
}

@test "finish-review --push pushes to the configured remote" {
	git review-pr feature/x
	printf 'a\nB\nc\nd\nfix\n' >app.txt
	run git finish-review --push
	[ "$status" -eq 0 ]
	[[ "$output" == *"upstream"* ]]
	# The fix branch landed on upstream, not anywhere named origin.
	run git ls-remote --heads upstream "review-fixes/feature/x"
	[ -n "$output" ]
}

@test "review-forget --stale fetches from the configured remote" {
	git review-pr feature/x
	# A marker now exists for feature/x; delete the remote branch so it is stale.
	git push --quiet upstream --delete feature/x
	run git review-forget --stale
	[ "$status" -eq 0 ]
	[[ "$output" == *"upstream/feature/x no longer exists"* ]]
	run git config reviewworkflow.feature/x.reviewed
	[ "$status" -ne 0 ]
}
