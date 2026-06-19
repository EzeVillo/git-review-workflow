#!/usr/bin/env bats
#
# Tests for git review-list, which shows every review/* branch in progress.

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
	git config reviewworkflow.base develop

	printf 'a\n' >app.txt
	git add app.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop

	git switch --quiet -c feature/x
	printf 'a\nb\n' >app.txt
	git add app.txt
	git commit --quiet -m pr1
	git push --quiet -u origin feature/x

	git switch --quiet -c feature/y develop
	printf 'a\nc\n' >app.txt
	git add app.txt
	git commit --quiet -m pr1y
	git push --quiet -u origin feature/y

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

@test "review-list reports no reviews when none exist" {
	run git review-list
	[ "$status" -eq 0 ]
	[[ "$output" == *"no reviews in progress"* ]]
}

@test "review-list lists every review branch" {
	git review-pr feature/x
	# A whole review leaves a staged diff; clear it before starting another.
	git switch --quiet develop
	git reset --hard --quiet
	git review-pr feature/y --step
	git switch --quiet develop

	run git review-list
	[ "$status" -eq 0 ]
	[[ "$output" == *"review/feature/x"* ]]
	[[ "$output" == *"whole"* ]]
	[[ "$output" == *"review/feature/y"* ]]
	[[ "$output" == *"step ["* ]]
}

@test "review-list marks the current branch with an asterisk" {
	git review-pr feature/x
	run git review-list
	[ "$status" -eq 0 ]
	[[ "$output" == *"* review/feature/x"* ]]
}

@test "review-list rejects unexpected arguments" {
	run git review-list bogus
	[ "$status" -ne 0 ]
	[[ "$output" == *"unexpected argument"* ]]
}
