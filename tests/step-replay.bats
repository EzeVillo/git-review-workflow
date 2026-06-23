#!/usr/bin/env bats
#
# Tests documenting how a --step review replays banked edits onto the PR tip at
# finish-review — specifically that it conflicts in exactly the cases a normal,
# commit-by-commit git rebase would, and only those.
#
# This is *expected* behaviour, not a defect: each step's edits are banked as an
# independent change against that step's commit and replayed in order, the same
# way `git rebase`/`git cherry-pick` replay commits one at a time. Two edits that
# fall in the same diff region (adjacent lines) therefore conflict — and a plain
# `git cherry-pick` of the very same edits conflicts identically, which one test
# below asserts directly. Edits in well-separated regions replay cleanly.
#
# Fixture: develop carries big.txt (20 lines), which the PR never touches, so it
# is present unchanged at every step. feature/x adds three commits on unrelated
# files, giving three steps to edit big.txt from.

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

	i=1
	: >big.txt
	while [ "$i" -le 20 ]; do
		printf 'L%s\n' "$i" >>big.txt
		i=$((i + 1))
	done
	printf 'a\n' >a.txt
	git add big.txt a.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop

	git switch --quiet -c feature/x
	printf '1\n' >f1.txt
	git add f1.txt
	git commit --quiet -m c1
	printf '2\n' >f2.txt
	git add f2.txt
	git commit --quiet -m c2
	printf '3\n' >f3.txt
	git add f3.txt
	git commit --quiet -m c3
	git push --quiet -u origin feature/x

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

@test "adjacent-line edits banked on different steps conflict at finish" {
	git review-pr feature/x --step
	sed -i 's/^L10$/L10-EDIT/' big.txt    # step 1
	git review-next
	sed -i 's/^L11$/L11-EDIT/' big.txt    # step 2, the line right after

	run git finish-review
	[ "$status" -ne 0 ]
	# it stops the way a rebase does: marks the conflict and points at --resume
	[ "$(git config branch.review/feature/x.reviewresume)" = "conflict" ]
	[[ "$output" == *"--resume"* ]]
	run cat big.txt
	[[ "$output" == *"<<<<<<<"* ]]
	[[ "$output" == *"L10-EDIT"* ]]
	[[ "$output" == *"L11-EDIT"* ]]
}

@test "a plain git cherry-pick of the same two edits conflicts identically" {
	# Prove the conflict above is git's own commit-by-commit replay behaviour, not
	# something the workflow introduces: build the two edits as ordinary commits on
	# the base and cherry-pick them onto the PR tip, exactly as a rebase would.
	git switch --quiet -c tmp-e1 develop
	sed -i 's/^L10$/L10-EDIT/' big.txt
	git commit --quiet -am e1-line10
	e1="$(git rev-parse HEAD)"

	git switch --quiet -c tmp-e2 develop
	sed -i 's/^L11$/L11-EDIT/' big.txt
	git commit --quiet -am e2-line11
	e2="$(git rev-parse HEAD)"

	# replay onto the tip, one commit at a time
	git switch --quiet --detach feature/x
	git cherry-pick "$e1"                 # first edit lands cleanly
	run git cherry-pick "$e2"
	[ "$status" -ne 0 ]                  # the adjacent second edit conflicts — git's own behaviour
	run cat big.txt
	[[ "$output" == *"<<<<<<<"* ]]
	git cherry-pick --abort
}

@test "well-separated edits banked on different steps replay cleanly" {
	git review-pr feature/x --step
	sed -i 's/^L3$/L3-EDIT/' big.txt      # step 1, near the top
	git review-next
	sed -i 's/^L17$/L17-EDIT/' big.txt    # step 2, far below — different region

	run git finish-review
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	[ -z "$(git config branch.review/feature/x.reviewresume || true)" ]
	# both edits made it, with no conflict markers
	run git diff --cached
	[[ "$output" == *"+L3-EDIT"* ]]
	[[ "$output" == *"+L17-EDIT"* ]]
	[[ "$output" != *"<<<<<<<"* ]]
}
