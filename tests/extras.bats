#!/usr/bin/env bats
#
# Tests for review-status, review-prev, review-abort and finish-review --resume.
# The PR has two commits: C1 rewrites f.txt's first line, C2 appends a line.

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

	printf 'orig\n' >f.txt
	git add f.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop

	git switch --quiet -c feature/x
	printf 'c1\n' >f.txt
	git add f.txt
	git commit --quiet -m c1-rewrite
	printf 'c1\nextra\n' >f.txt
	git add f.txt
	git commit --quiet -m c2-append
	git push --quiet -u origin feature/x

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

@test "review-status reports a whole review" {
	git review-pr feature/x
	run git review-status
	[ "$status" -eq 0 ]
	[[ "$output" == *"review of feature/x"* ]]
	[[ "$output" == *"mode    whole"* ]]
}

@test "review-status reports step progress" {
	git review-pr feature/x --step
	git review-next
	run git review-status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/2]"* ]]
	[[ "$output" == *"c2-append"* ]]
}

@test "review-prev restores edits in both directions" {
	git review-pr feature/x --step
	printf 'edited1\n' >f.txt
	git review-next
	# the edit is banked, gone from the tree at step 2
	run cat f.txt
	[[ "$output" != *"edited1"* ]]
	# going back restores it
	git review-prev
	run cat f.txt
	[[ "$output" == *"edited1"* ]]
}

@test "review-abort returns to the starting branch and removes the review" {
	git review-pr feature/x
	run git review-abort
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "review-abort drops banked edit refs" {
	git review-pr feature/x --step
	printf 'edited1\n' >f.txt
	git review-next
	git review-abort
	run git for-each-ref refs/review-edits/feature/x/
	[ -z "$output" ]
}

@test "finish-review surfaces replay conflicts and resumes after resolution" {
	git review-pr feature/x --step
	printf 'FIX1\n' >f.txt
	git review-next
	printf 'FIX2\nextra\n' >f.txt
	git review-next
	run git finish-review
	[ "$status" -ne 0 ]
	[[ "$output" == *"conflict"* ]]
	# resolve the markers and resume
	printf 'RESOLVED\nextra\n' >f.txt
	run git finish-review --resume
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	run git diff --cached
	[[ "$output" == *"RESOLVED"* ]]
}

@test "finish-review --resume without a pending conflict fails" {
	git review-pr feature/x --step
	run git finish-review --resume
	[ "$status" -ne 0 ]
	[[ "$output" == *"nothing to resume"* ]]
}
