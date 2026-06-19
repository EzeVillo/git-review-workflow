#!/usr/bin/env bats
#
# Tests for the commit-by-commit review mode (review-pr --step + review-next).
# The PR has two commits: C1 touches a.txt, C2 touches b.txt.

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

	printf 'a1\n' >a.txt
	printf 'b1\n' >b.txt
	git add a.txt b.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop

	git switch --quiet -c feature/x
	printf 'a1\na2\n' >a.txt
	git add a.txt
	git commit --quiet -m c1-touch-a
	printf 'b1\nb2\n' >b.txt
	git add b.txt
	git commit --quiet -m c2-touch-b
	git push --quiet -u origin feature/x

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

@test "--step starts on the first commit" {
	run git review-pr feature/x --step
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	[[ "$output" == *"[1/2]"* ]]
	[[ "$output" == *"c1-touch-a"* ]]
	# clean working tree, parked exactly on the first commit
	run git status --porcelain
	[ -z "$output" ]
}

@test "review-next advances with a clean tree and hides prior edits" {
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	run git review-next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/2]"* ]]
	[[ "$output" == *"c2-touch-b"* ]]
	# the C1 edit is banked, not lingering in the tree
	run cat a.txt
	[[ "$output" != *"FIXA"* ]]
	run git status --porcelain
	[ -z "$output" ]
}

@test "review-next at the last commit reports the end" {
	git review-pr feature/x --step
	git review-next
	run git review-next
	[ "$status" -eq 0 ]
	[[ "$output" == *"no more commits"* ]]
}

@test "finish-review replays every banked edit onto the tip" {
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	git review-next
	printf 'b1\nb2\nFIXB\n' >b.txt
	git review-next
	run git finish-review
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	run git diff --cached
	[[ "$output" == *"+FIXA"* ]]
	[[ "$output" == *"+FIXB"* ]]
	# author lines belong to the tip, not to the extracted fixes
	[[ "$output" != *"+a2"* ]]
}

@test "finish-review works even without advancing to the end" {
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	run git finish-review
	[ "$status" -eq 0 ]
	run git diff --cached
	[[ "$output" == *"+FIXA"* ]]
}

@test "review-next requires step mode" {
	git review-pr feature/x
	run git review-next
	[ "$status" -ne 0 ]
	[[ "$output" == *"not started with git review-pr --step"* ]]
}

@test "clean-review removes banked edit refs" {
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	git review-next
	run git for-each-ref refs/review-edits/feature/x/
	[ -n "$output" ]
	git switch --quiet develop
	git clean-review feature/x
	run git for-each-ref refs/review-edits/feature/x/
	[ -z "$output" ]
}
