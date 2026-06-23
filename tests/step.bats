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
	# the first commit's diff is staged; working tree is clean
	run git diff --cached --name-only
	[ "$output" = "a.txt" ]
	run git diff --name-only
	[ -z "$output" ]
}

@test "--step prints the diffstat before the header so the header stays near the prompt" {
	run git review-pr feature/x --step
	[ "$status" -eq 0 ]
	# The diffstat summary must come before the [n/total] header: a long stat
	# scrolls off the top, the identifying header stays next to the prompt.
	stat_line="$(printf '%s\n' "$output" | grep -nE '[0-9]+ files? changed' | head -1 | cut -d: -f1)"
	hdr_line="$(printf '%s\n' "$output" | grep -nF '[1/2]' | head -1 | cut -d: -f1)"
	[ -n "$stat_line" ]
	[ -n "$hdr_line" ]
	[ "$stat_line" -lt "$hdr_line" ]
	# the subject still shows, just below the header
	[[ "$output" == *"c1-touch-a"* ]]
}

@test "review-next advances with a clean tree and hides prior edits" {
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	run git review-next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/2]"* ]]
	[[ "$output" == *"c2-touch-b"* ]]
	# the C1 edit is banked, not lingering in the tree: a.txt is back to C1's content
	run cat a.txt
	[[ "$output" == *"a2"* ]]
	[[ "$output" != *"FIXA"* ]]
	# the C2 diff is staged; working tree is clean
	run git diff --cached --name-only
	[ "$output" = "b.txt" ]
	run git diff --name-only
	[ -z "$output" ]
}

@test "review-next prints the diffstat before the header too" {
	git review-pr feature/x --step
	run git review-next
	[ "$status" -eq 0 ]
	stat_line="$(printf '%s\n' "$output" | grep -nE '[0-9]+ files? changed' | head -1 | cut -d: -f1)"
	hdr_line="$(printf '%s\n' "$output" | grep -nF '[2/2]' | head -1 | cut -d: -f1)"
	[ -n "$stat_line" ]
	[ -n "$hdr_line" ]
	[ "$stat_line" -lt "$hdr_line" ]
	[[ "$output" == *"c2-touch-b"* ]]
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

@test "review-next with no edits leaves no banked ref and stages the next diff" {
	git review-pr feature/x --step
	# advance without editing — the tree matches the commit so no ref should be created
	git review-next
	run git for-each-ref refs/review-edits/feature/x/1
	[ -z "$output" ]
	# step 2 diff is staged; working tree is clean
	run git diff --cached --name-only
	[ "$output" = "b.txt" ]
	run git diff --name-only
	[ -z "$output" ]
}

@test "finish-review with no edits exits early" {
	git review-pr feature/x --step
	run git finish-review
	[ "$status" -eq 0 ]
	[[ "$output" == *"no review changes"* ]]
}

@test "--step on a single-commit PR stages its diff then ends" {
	git switch --quiet develop
	git switch --quiet -c feature/solo
	printf 'solo\n' >solo.txt
	git add solo.txt
	git commit --quiet -m solo-commit
	git push --quiet -u origin feature/solo
	git switch --quiet develop

	git review-pr feature/solo --step
	run git diff --cached --name-only
	[ "$output" = "solo.txt" ]
	run git diff --name-only
	[ -z "$output" ]
	run git review-next
	[ "$status" -eq 0 ]
	[[ "$output" == *"no more commits"* ]]
}

# A banked edit reverted back to the clean commit content must not resurrect: the
# stale edit ref has to be cleared, not left to reappear on the next visit.
@test "reverting a banked edit to clean does not resurrect it on prev/next" {
	git review-pr feature/x --step
	# edit step 1, then bank it by advancing
	printf 'a1\na2\nEDIT\n' >a.txt
	git review-next
	# back on step 1: the edit is restored
	git review-prev
	run git diff --name-only
	[ "$output" = "a.txt" ]
	# revert it to the clean commit content
	git checkout -- a.txt
	run git diff --name-only
	[ -z "$output" ]
	# moving away and back must not bring the reverted edit back
	git review-next
	git review-prev
	run git diff --name-only
	[ -z "$output" ]
}

@test "reverting a banked edit to clean does not resurrect it at finish" {
	git review-pr feature/x --step
	printf 'a1\na2\nEDIT\n' >a.txt
	git review-next          # bank step 1
	git review-prev          # back to step 1
	git checkout -- a.txt    # revert to clean
	git review-next          # move on (should clear the banked edit)
	git finish-review
	run git diff --cached
	[[ "$output" != *"EDIT"* ]]
}

@test "--step --step is harmless (a duplicated flag)" {
	run git review-pr feature/x --step --step
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	[[ "$output" == *"[1/2]"* ]]
}
