#!/usr/bin/env bats
#
# End-to-end tests for the git review commands. Each test runs in an isolated
# HOME with its own bare "origin" remote and a working clone.

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"

	git config --global user.email t@example.com
	git config --global user.name tester
	git config --global init.defaultBranch develop

	ORIGIN="$TMP/origin.git"
	WORK="$TMP/work"
	git init --quiet --bare "$ORIGIN"
	git init --quiet "$WORK"
	cd "$WORK"
	git remote add origin "$ORIGIN"

	printf 'a\nb\nc\n' >app.txt
	git add app.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop

	git switch --quiet -c feature/x
	printf 'a\nB\nc\nd\n' >app.txt
	git add app.txt
	git commit --quiet -m pr1
	git push --quiet -u origin feature/x

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

# Push a second PR commit that appends a line; leaves you on develop.
push_pr2() {
	git switch --quiet feature/x
	printf 'a\nB\nc\nd\ne\n' >app.txt
	git add app.txt
	git commit --quiet -m pr2
	git push --quiet origin feature/x
	git switch --quiet develop
}

@test "review-pr stages the whole PR as a diff" {
	run git review-pr feature/x
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git diff --cached
	[[ "$output" == *"+B"* ]]
	[[ "$output" == *"+d"* ]]
}

@test "review-pr refuses a dirty working tree" {
	printf 'dirty\n' >>app.txt
	run git review-pr feature/x
	[ "$status" -ne 0 ]
	[[ "$output" == *"local changes"* ]]
}

@test "review-pr fails for an unknown branch" {
	run git review-pr nope/nope
	[ "$status" -ne 0 ]
	[[ "$output" == *"origin/nope/nope not found"* ]]
}

@test "review-pr honours reviewworkflow.base config" {
	git config reviewworkflow.base develop
	run git review-pr feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewbase)" = "develop" ]
}

@test "finish-review extracts only the reviewer edits" {
	git review-pr feature/x
	printf 'a\nB\nc\nd\nfix\n' >app.txt
	run git finish-review
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	run git diff --cached
	[[ "$output" == *"+fix"* ]]
	[[ "$output" != *"+B"* ]]
}

@test "finish-review --onto-source commits on the PR branch" {
	git review-pr feature/x
	printf 'a\nB\nc\nd\nfix\n' >app.txt
	run git finish-review --onto-source
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "feature/x" ]
	run git log -1 --pretty=%s
	[[ "$output" == *"review fixes (feature/x)"* ]]
}

@test "finish-review reports when there are no edits" {
	git review-pr feature/x
	run git finish-review
	[ "$status" -eq 0 ]
	[[ "$output" == *"no review changes"* ]]
}

@test "review-pr --delta stages only new commits" {
	git review-pr feature/x
	git switch --quiet develop
	git clean-review feature/x
	push_pr2
	run git review-pr feature/x --delta
	[ "$status" -eq 0 ]
	run git diff --cached
	[[ "$output" == *"+e"* ]]
	[[ "$output" != *"+d"* ]]
}

@test "review-pr --delta without a prior review fails" {
	run git review-pr feature/x --delta
	[ "$status" -ne 0 ]
	[[ "$output" == *"no previous review"* ]]
}

@test "clean-review deletes the review branches" {
	git review-pr feature/x
	git switch --quiet develop
	run git clean-review feature/x
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "clean-review skips the currently checked out branch" {
	git review-pr feature/x
	run git clean-review feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"skipping review/feature/x"* ]]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -eq 0 ]
}
