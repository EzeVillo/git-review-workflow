#!/usr/bin/env bats
#
# Tests for the range axis (--delta, --from) and its composition with --step.
# The PR starts with two commits: C1 adds a.txt, C2 adds b.txt.

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

	printf 'base\n' >base.txt
	git add base.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop

	git switch --quiet -c feature/x
	printf 'a\n' >a.txt
	git add a.txt
	git commit --quiet -m c1-add-a
	printf 'b\n' >b.txt
	git add b.txt
	git commit --quiet -m c2-add-b
	git push --quiet -u origin feature/x

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

# Append two more commits (C3 adds c.txt, C4 adds d.txt); leaves you on develop.
push_more() {
	git switch --quiet feature/x
	printf 'c\n' >c.txt
	git add c.txt
	git commit --quiet -m c3-add-c
	printf 'd\n' >d.txt
	git add d.txt
	git commit --quiet -m c4-add-d
	git push --quiet origin feature/x
	git switch --quiet develop
}

@test "--from stages only the commits after the given commit" {
	c1="$(git rev-parse feature/x~1)"
	run git review-pr feature/x --from "$c1"
	[ "$status" -eq 0 ]
	run git diff --cached --name-only
	[[ "$output" == *"b.txt"* ]]
	[[ "$output" != *"a.txt"* ]]
}

@test "--from --step walks only the commits after the given commit" {
	c1="$(git rev-parse feature/x~1)"
	run git review-pr feature/x --from "$c1" --step
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/1]"* ]]
	[[ "$output" == *"c2-add-b"* ]]
}

@test "--from rejects an unknown commit" {
	run git review-pr feature/x --from deadbeef
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown commit"* ]]
}

@test "--from rejects a commit that is not an ancestor of the PR" {
	# A commit on develop after the branch point is not an ancestor of feature/x.
	printf 'x\n' >x.txt
	git add x.txt
	git commit --quiet -m off-branch
	other="$(git rev-parse HEAD)"
	run git review-pr feature/x --from "$other"
	[ "$status" -ne 0 ]
	[[ "$output" == *"not an ancestor"* ]]
}

@test "--delta and --from cannot be combined" {
	c1="$(git rev-parse feature/x~1)"
	run git review-pr feature/x --delta --from "$c1"
	[ "$status" -ne 0 ]
	[[ "$output" == *"only one of --delta and --from"* ]]
}

@test "an explicit base cannot be combined with --delta" {
	run git review-pr feature/x develop --delta
	[ "$status" -ne 0 ]
	[[ "$output" == *"base is ignored with --delta/--from"* ]]
}

@test "an explicit base cannot be combined with --from" {
	c1="$(git rev-parse feature/x~1)"
	run git review-pr feature/x develop --from "$c1"
	[ "$status" -ne 0 ]
	[[ "$output" == *"base is ignored with --delta/--from"* ]]
}

@test "--delta --step walks only the new commits after a prior review" {
	git review-pr feature/x
	git switch --quiet develop
	git clean-review feature/x
	push_more
	run git review-pr feature/x --delta --step
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/2]"* ]]
	[[ "$output" == *"c3-add-c"* ]]
}

@test "--delta --step then finish replays edits onto the new tip" {
	git review-pr feature/x
	git switch --quiet develop
	git clean-review feature/x
	push_more
	git review-pr feature/x --delta --step
	printf 'c\nFIXC\n' >c.txt
	git review-next
	git review-next
	run git finish-review
	[ "$status" -eq 0 ]
	run git diff --cached
	[[ "$output" == *"+FIXC"* ]]
}
