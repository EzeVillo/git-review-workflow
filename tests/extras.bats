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

@test "review-status rejects a step past the last commit instead of printing garbage" {
	git review-pr feature/x --step
	# corrupt the metadata the way a hand-edit or a future bug might
	git config branch.review/feature/x.reviewstep 99
	run git review-status
	[ "$status" -ne 0 ]
	[[ "$output" == *"out of range (1..2)"* ]]
}

@test "review-status rejects step 0 and a non-numeric step" {
	git review-pr feature/x --step
	git config branch.review/feature/x.reviewstep 0
	run git review-status
	[ "$status" -ne 0 ]
	[[ "$output" == *"out of range (1..2)"* ]]

	git config branch.review/feature/x.reviewstep abc
	run git review-status
	[ "$status" -ne 0 ]
	[[ "$output" == *"not a positive integer"* ]]
}

@test "review-status accepts the last valid step (no off-by-one false positive)" {
	git review-pr feature/x --step
	# step 2 of 2 is the boundary: it must NOT be rejected as out of range
	git config branch.review/feature/x.reviewstep 2
	run git review-status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/2]"* ]]
	[[ "$output" != *"out of range"* ]]
}

@test "review-next and review-prev refuse a corrupt step instead of crashing" {
	git review-pr feature/x --step
	git config branch.review/feature/x.reviewstep 99
	run git review-next
	[ "$status" -ne 0 ]
	[[ "$output" == *"out of range (1..2)"* ]]
	# step must be untouched — the guard fires before any banking/reset
	[ "$(git config branch.review/feature/x.reviewstep)" = "99" ]

	run git review-prev
	[ "$status" -ne 0 ]
	[[ "$output" == *"out of range (1..2)"* ]]
}

@test "review-next and review-prev report a deleted metadata key instead of dying silently" {
	git review-pr feature/x --step
	# A hand-edit removes an essential key but leaves reviewmode=step, so the
	# mode guard passes and set -e would kill the read with no message.
	git config --unset branch.review/feature/x.reviewstart

	run git review-next
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]

	run git review-prev
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
}

@test "review-status/preview/save report a deleted step key instead of dying silently" {
	# These three read the step keys with bare git config; under set -e a missing
	# key kills the bare read mid-script (after a couple of lines of output) with
	# no message. A reviewcount deleted by hand leaves reviewmode=step, so the
	# mode guard passes and the read is reached. The status code AND the message
	# both matter: dying silently exits non-zero too, so assert on both.
	git review-pr feature/x --step
	git config --unset branch.review/feature/x.reviewcount

	run git review-status
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]] ||
		{ echo "review-status died silently or printed garbage: $output"; false; }

	run git review-preview
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]] ||
		{ echo "review-preview died silently: $output"; false; }

	run git review-save
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]] ||
		{ echo "review-save died silently: $output"; false; }
}

@test "review-status reports a deleted reviewstep key with a precise message" {
	# reviewstep is special: status/preview let it fall through to the numeric
	# guard, which names the key rather than the generic "missing metadata".
	git review-pr feature/x --step
	git config --unset branch.review/feature/x.reviewstep
	run git review-status
	[ "$status" -ne 0 ]
	[[ "$output" == *"corrupt review metadata"* ]] ||
		{ echo "review-status died silently on missing reviewstep: $output"; false; }
}

@test "review-prev restores edits in both directions" {
	git review-pr feature/x --step
	printf 'edited1\n' >f.txt
	git review-next
	# the edit is banked, gone from the tree at step 2: f.txt is C2's content
	run cat f.txt
	[[ "$output" == *"extra"* ]]
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

@test "review-abort clears the delta marker when there was no prior review" {
	git review-pr feature/x
	git review-abort
	run git config reviewworkflow.feature/x.reviewed
	[ "$status" -ne 0 ]
	run git review-pr feature/x --delta
	[ "$status" -ne 0 ]
	[[ "$output" == *"no previous review"* ]]
}

@test "review-abort restores the delta marker from a prior review" {
	prior="$(git rev-parse develop)"
	git config reviewworkflow.feature/x.reviewed "$prior"
	git review-pr feature/x
	git review-abort
	[ "$(git config reviewworkflow.feature/x.reviewed)" = "$prior" ]
}

@test "review-abort drops banked edit refs" {
	git review-pr feature/x --step
	printf 'edited1\n' >f.txt
	git review-next
	git review-abort
	run git for-each-ref refs/review-edits/feature/x/
	[ -z "$output" ]
}

@test "review-abort tears down a review already passed through finish-review" {
	# Off-book path: finish-review, then switch back to the still-present review
	# branch and cancel. Abort must leave nothing dangling — not the review-fixes
	# branch finish created, nor its undo point.
	git review-pr feature/x
	printf 'c1\nextra\nfix\n' >f.txt
	git finish-review
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	[ -n "$(git for-each-ref refs/review-undo/feature/x/)" ]

	git switch --quiet --discard-changes review/feature/x
	run git review-abort
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ]
	# review branch, review-fixes branch and the undo refs are all gone
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -ne 0 ]
	run git for-each-ref refs/review-undo/feature/x/
	[ -z "$output" ]
	# and the undo config (it rode on the deleted review branch) is gone too
	[ -z "$(git config branch.review/feature/x.reviewundohead || true)" ]
}

@test "review-abort falls back to the base when the return branch is gone" {
	# Start the review from a throwaway branch, then delete it: the recorded
	# return branch no longer resolves, so abort must fall back to the base.
	git switch --quiet -c throwaway
	git review-pr feature/x
	[ "$(git config branch.review/feature/x.reviewreturn)" = "throwaway" ]
	[ "$(git config branch.review/feature/x.reviewbase)" = "develop" ]
	git branch -D throwaway
	run git review-abort
	[ "$status" -eq 0 ]
	# Landed on the base, not the (now-missing) return branch.
	[ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ]
	[[ "$output" == *"returned to develop"* ]]
	# The review branch was still cleaned up despite the fallback.
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "review-abort errors when neither the return branch nor the base exists" {
	# Started on develop, so both the return branch and the base point at it;
	# deleting it leaves abort with nowhere to return to.
	git review-pr feature/x
	git branch -D develop
	run git review-abort
	[ "$status" -ne 0 ]
	[[ "$output" == *"could not determine a branch to return to"* ]]
	# It must bail before touching anything: no switch, review branch intact.
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -eq 0 ]
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

@test "review-prev stages the previous commit's diff" {
	git review-pr feature/x --step
	git review-next
	# at step 2: f.txt staged, working tree clean
	run git diff --cached --name-only
	[ "$output" = "f.txt" ]
	run git diff --name-only
	[ -z "$output" ]
	git review-prev
	# back at step 1: f.txt still staged, working tree still clean
	run git diff --cached --name-only
	[ "$output" = "f.txt" ]
	run git diff --name-only
	[ -z "$output" ]
}

@test "review-prev at the first commit reports already at the start and keeps staging" {
	git review-pr feature/x --step
	run git review-prev
	[ "$status" -eq 0 ]
	[[ "$output" == *"already at the first commit"* ]]
	[ "$(git config branch.review/feature/x.reviewstep)" = "1" ]
	# staging must be intact — same invariant as the original staging bug
	run git diff --cached --name-only
	[ "$output" = "f.txt" ]
	run git diff --name-only
	[ -z "$output" ]
}
