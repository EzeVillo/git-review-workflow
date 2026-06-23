#!/usr/bin/env bats
#
# Tests for git-review-save / git-review-continue / git-review-forget-saved.
#
# The PR (feature/x) has four commits on top of develop: A touches a.txt,
# B touches b.txt, C touches c.txt, D touches d.txt. Four commits give enough
# room to step into D, edit it, walk back to B and save from there — the case
# where a saved step review must carry edits banked on a commit ahead of the one
# you are sitting on.

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
	printf 'c\n' >c.txt
	git add c.txt
	git commit --quiet -m c3-touch-c
	printf 'd\n' >d.txt
	git add d.txt
	git commit --quiet -m c4-touch-d
	git push --quiet -u origin feature/x

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

# ── whole-PR mode ─────────────────────────────────────────────────────────────

@test "save (whole) returns to the start branch and swaps review/ for review-saved/" {
	git review-pr feature/x develop
	printf 'a1\na2\nWHOLEFIX\n' >a.txt
	run git review-save
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ]
	# the active review branch is gone, the saved one took its place
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
	run git rev-parse --verify --quiet refs/heads/review-saved/feature/x
	[ "$status" -eq 0 ]
}

@test "continue (whole) restores the staged PR diff and the edits, then finish extracts them" {
	git review-pr feature/x develop
	printf 'a1\na2\nWHOLEFIX\n' >a.txt
	git review-save
	run git review-continue feature/x
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	# the PR diff is staged again
	run git diff --cached --name-only
	[[ "$output" == *"a.txt"* ]]
	# the edit is back in the working tree, unstaged
	run git diff
	[[ "$output" == *"WHOLEFIX"* ]]
	# and it survives all the way to finish-review
	git finish-review
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	run git diff --cached
	[[ "$output" == *"+WHOLEFIX"* ]]
	# the saved review is consumed once resumed
	run git rev-parse --verify --quiet refs/heads/review-saved/feature/x
	[ "$status" -ne 0 ]
}

@test "continue (whole) survives a gc when the base was merged into the PR" {
	# Force the synthetic-lower path: advance develop, merge it into feature/x so
	# review-pr folds the already-merged base content into a merge-tree lower bound,
	# then review with --from so that lower bound is a fresh, off-history commit.
	first="$(git rev-list --reverse --first-parent feature/x ^develop | sed -n '1p')"
	git switch --quiet develop
	printf 'base-moved\n' >base2.txt
	git add base2.txt
	git commit --quiet -m base2
	git push --quiet origin develop
	git switch --quiet feature/x
	git merge --quiet --no-edit develop
	printf 'a1\na2\na3\n' >a.txt
	git add a.txt
	git commit --quiet -m c5-touch-a-again
	git push --quiet origin feature/x
	git switch --quiet develop

	git review-pr feature/x --from "$first"
	# the base file folded into the lower bound must not appear in the staged diff
	run git diff --cached --name-only
	[[ "$output" != *"base2.txt"* ]]
	printf 'a1\na2\na3\nGCFIX\n' >a.txt
	git review-save

	# A gc with no grace period prunes anything unreachable — the lower bound must
	# stay reachable through the saved commit, or continue cannot rebuild the diff.
	git reflog expire --expire-unreachable=now --all
	git gc --prune=now --quiet

	run git review-continue feature/x
	[ "$status" -eq 0 ]
	run git diff --cached --name-only
	[[ "$output" == *"a.txt"* ]]
	[[ "$output" != *"base2.txt"* ]]
	run git diff
	[[ "$output" == *"GCFIX"* ]]
}

@test "continue (whole) with no edits round-trips a clean review" {
	git review-pr feature/x develop
	git review-save
	run git review-continue feature/x
	[ "$status" -eq 0 ]
	# the PR diff is staged; the working tree is clean
	run git diff --cached --name-only
	[[ "$output" == *"a.txt"* ]]
	run git diff
	[ -z "$output" ]
}

# ── step mode ─────────────────────────────────────────────────────────────────

@test "save (step) banks the current step and moves every banked edit aside" {
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	git review-next
	printf 'b1\nb2\nFIXB\n' >b.txt
	# save from step 2 (B) with B's edits still in the working tree
	run git review-save
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ]
	# nothing is left under refs/review-edits/ — it all moved to review-saved-edits
	run git for-each-ref refs/review-edits/feature/x/
	[ -z "$output" ]
	run git for-each-ref refs/review-saved-edits/feature/x/
	# A (step 1) and B (step 2) → two banked edits
	[ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
}

@test "continue (step) drops back on the same commit with its edits restored" {
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	git review-next
	printf 'b1\nb2\nFIXB\n' >b.txt
	git review-save
	run git review-continue feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewstep)" = "2" ]
	[[ "$output" == *"[2/4]"* ]]
	[[ "$output" == *"c2-touch-b"* ]]
	# B's edit is back in the working tree
	run git diff
	[[ "$output" == *"FIXB"* ]]
}

@test "save/continue (step) keep edits banked on a commit ahead of the saved step" {
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	git review-next          # bank A, now on B (step 2)
	printf 'b1\nb2\nFIXB\n' >b.txt
	git review-next          # bank B, now on C (step 3)
	git review-next          # now on D (step 4)
	printf 'd\nFIXD\n' >d.txt
	git review-prev          # bank D, now on C (step 3)
	git review-prev          # now on B (step 2) — D already edited and banked ahead

	[ "$(git config branch.review/feature/x.reviewstep)" = "2" ]
	git review-save
	# all three banked edits (A, B, D) travelled into the saved namespace
	run git for-each-ref refs/review-saved-edits/feature/x/
	[ "$(printf '%s\n' "$output" | grep -c .)" -eq 3 ]

	git review-continue feature/x
	[ "$(git config branch.review/feature/x.reviewstep)" = "2" ]
	# step back forward to D; its edit must still be there
	git review-next          # to C
	run git review-next      # to D
	[[ "$output" == *"[4/4]"* ]]
	run git diff
	[[ "$output" == *"FIXD"* ]]
	# finish replays A, B and D onto the tip
	git finish-review
	run git diff --cached
	[[ "$output" == *"+FIXA"* ]]
	[[ "$output" == *"+FIXB"* ]]
	[[ "$output" == *"+FIXD"* ]]
}

@test "continue reports a deleted metadata key instead of dying silently" {
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	git review-save
	# A hand-edit removes an essential key from the saved review's config; without
	# || true the read would let set -e kill review-continue with no message.
	git config --unset branch.review-saved/feature/x.reviewstart

	run git review-continue feature/x
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
}

@test "clean-review does not touch a saved review" {
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	git review-save
	# a blanket clean-review prunes review/* and refs/review-edits/, never the saved ones
	git clean-review
	run git rev-parse --verify --quiet refs/heads/review-saved/feature/x
	[ "$status" -eq 0 ]
	run git for-each-ref refs/review-saved-edits/feature/x/
	[ -n "$output" ]
	# and the saved review is still resumable, on the same step with its edit intact
	run git review-continue feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewstep)" = "1" ]
	run git diff
	[[ "$output" == *"FIXA"* ]]
}

# ── review-list / review-pr integration ───────────────────────────────────────

@test "review-list shows a saved review under \"saved\"" {
	git review-pr feature/x --step
	git review-save
	run git review-list
	[ "$status" -eq 0 ]
	[[ "$output" == *"review-saved/feature/x"* ]]
	[[ "$output" == *"saved"* ]]
}

@test "review-pr refuses to start when a saved review of the branch exists" {
	git review-pr feature/x --step
	git review-save
	run git review-pr feature/x develop
	[ "$status" -ne 0 ]
	[[ "$output" == *"saved review of feature/x"* ]]
	[[ "$output" == *"review-continue"* ]]
}

# ── continue selection ────────────────────────────────────────────────────────

@test "continue with no argument resumes the only saved review" {
	git review-pr feature/x --step
	git review-save
	run git review-continue
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
}

@test "continue with no argument lists choices when several reviews are saved" {
	# first saved review
	git review-pr feature/x develop
	git review-save
	# a second source branch with its own saved review
	git switch --quiet develop
	git switch --quiet -c feature/y
	printf 'y\n' >y.txt
	git add y.txt
	git commit --quiet -m c-y
	git push --quiet -u origin feature/y
	git switch --quiet develop
	git review-pr feature/y develop
	git review-save

	run git review-continue
	[ "$status" -ne 0 ]
	[[ "$output" == *"more than one saved review"* ]]
	[[ "$output" == *"feature/x"* ]]
	[[ "$output" == *"feature/y"* ]]
}

@test "continue names an unknown saved review clearly" {
	run git review-continue nope
	[ "$status" -ne 0 ]
	[[ "$output" == *"no saved review for nope"* ]]
}

# ── forget-saved ──────────────────────────────────────────────────────────────

@test "forget-saved discards the branch, its banked edits and rolls back the delta marker" {
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	git review-next
	git review-save
	# the review-pr that created this set a reviewed marker at the tip
	run git config reviewworkflow.feature/x.reviewed
	[ "$status" -eq 0 ]

	run git review-forget-saved feature/x
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review-saved/feature/x
	[ "$status" -ne 0 ]
	run git for-each-ref refs/review-saved-edits/feature/x/
	[ -z "$output" ]
	# the marker is rolled back (there was no prior review, so it is cleared)
	run git config reviewworkflow.feature/x.reviewed
	[ "$status" -ne 0 ]
}

@test "forget-saved --all discards every saved review" {
	git review-pr feature/x --step
	git review-save
	git switch --quiet develop
	git switch --quiet -c feature/y
	printf 'y\n' >y.txt
	git add y.txt
	git commit --quiet -m c-y
	git push --quiet -u origin feature/y
	git switch --quiet develop
	git review-pr feature/y develop
	git review-save

	run git review-forget-saved --all
	[ "$status" -eq 0 ]
	run git for-each-ref refs/heads/review-saved/
	[ -z "$output" ]
}

@test "forget-saved on a branch with no saved review is a no-op note" {
	run git review-forget-saved feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"no saved review for feature/x"* ]]
}

# ── guards ────────────────────────────────────────────────────────────────────

@test "save off a review branch fails" {
	run git review-save
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}

@test "continue with a dirty working tree fails" {
	git review-pr feature/x --step
	git review-save
	printf 'dirty\n' >>a.txt
	run git review-continue feature/x
	[ "$status" -ne 0 ]
	[[ "$output" == *"local changes"* ]]
}

@test "continue fails when the review is already active" {
	git review-pr feature/x --step
	git review-save
	git review-continue feature/x
	# now review/feature/x is active again; a stray saved branch cannot clobber it
	run git review-continue feature/x
	[ "$status" -ne 0 ]
	[[ "$output" == *"no saved review for feature/x"* ]]
}
