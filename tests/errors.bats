#!/usr/bin/env bats
#
# State-dependent error and side-effect tests that the per-command files did not
# already cover: wrong-branch guards, missing metadata, branch-already-exists,
# the "previously reviewed" note and the force-push / no-new-commits delta
# guards.

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

# Rewrite origin/feature/x onto develop so its previous commits become orphaned —
# a force-push that drops the old history. The original commits still exist as
# objects locally (callers capture their SHAs first). Leaves you on develop.
force_push_feature() {
	git switch --quiet feature/x
	git reset --hard --quiet develop
	printf 'alt\n' >alt.txt
	git add alt.txt
	git commit --quiet -m rewritten
	git push --quiet --force origin feature/x
	git switch --quiet develop
}

# A feature branch with two independent commits: c1 adds a.txt, c2 adds b.txt.
# Two commits give a step review a banked edit on step 1 and a live edit on
# step 2, and leave step 1 short of the tip so a whole-mode fallback would leak
# c2 into the reviewer's diff. Leaves you on develop.
make_two_commit_feature() {
	git switch --quiet -c feature/two develop
	printf 'a2\n' >a.txt
	git add a.txt
	git commit --quiet -m c1-touch-a
	printf 'b2\n' >b.txt
	git add b.txt
	git commit --quiet -m c2-touch-b
	git push --quiet -u origin feature/two
	git switch --quiet develop
}

# Start a step review of that two-commit feature, bank an edit (FIXA) on step 1
# and leave a live edit (FIXB) on step 2 — the working state review finish's step
# replay must not silently discard when its metadata is corrupt. Leaves you on the
# review branch, on step 2.
step_review_two_with_edits() {
	make_two_commit_feature
	git review start feature/two --step
	printf 'a2\nFIXA\n' >a.txt
	git review next                # bank step 1 (FIXA), now on step 2
	printf 'b2\nFIXB\n' >b.txt     # current step edit, not yet banked
}

# ── wrong-branch guards (run on develop, not a review/* branch) ───────────────

@test "review next off a review branch errors" {
	run git review next
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}

@test "review prev off a review branch errors" {
	run git review prev
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}

@test "review status off a review branch errors" {
	run git review status
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}

@test "review abort off a review branch errors" {
	run git review abort
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}

@test "review finish off a review branch errors" {
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}

@test "review prev requires step mode on a whole review" {
	git review start feature/x
	run git review prev
	[ "$status" -ne 0 ]
	[[ "$output" == *"not started with git review start --step"* ]]
}

# ── missing review metadata on a hand-made review/* branch ────────────────────

@test "review status reports missing metadata" {
	git switch --quiet -c review/orphan
	run git review status
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
}

@test "review abort reports missing metadata" {
	git switch --quiet -c review/orphan
	run git review abort
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
}

@test "review finish reports missing metadata" {
	git switch --quiet -c review/orphan
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
}

# ── review start guards ──────────────────────────────────────────────────────────

@test "review start refuses when the review branch already exists" {
	git review start feature/x
	git switch --quiet develop
	git reset --hard --quiet
	run git review start feature/x
	[ "$status" -ne 0 ]
	[[ "$output" == *"already exists"* ]]
}

@test "review start rejects an unknown explicit base" {
	# The base is a commit-ish (branch, tag or commit), so a failed lookup is no
	# longer labelled origin/<base> — it was tried as a tag and a commit too. The
	# label is the base as given.
	run git review start feature/x nosuchbase
	[ "$status" -ne 0 ]
	[[ "$output" == *"nosuchbase not found"* ]]
	[[ "$output" != *"origin/nosuchbase"* ]]
}

@test "review start --from= equals form stages the same range as --from" {
	push_pr2
	c1="$(git rev-parse origin/feature/x~1)"
	run git review start feature/x --from="$c1"
	[ "$status" -eq 0 ]
	run git diff --cached
	[[ "$output" == *"+e"* ]]
}

@test "review start notes new commits since the last full review" {
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x~1)"
	run git review start feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"previously reviewed"* ]]
	[[ "$output" == *"--delta"* ]]
}

@test "review start --delta with no new commits fails" {
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x)"
	run git review start feature/x --delta
	[ "$status" -ne 0 ]
	[[ "$output" == *"no new commits"* ]]
}

@test "review start --delta after a force-push fails" {
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x)"
	# Rewrite feature/x so the recorded tip is no longer an ancestor.
	git switch --quiet feature/x
	git reset --hard --quiet develop
	printf 'alt\n' >alt.txt
	git add alt.txt
	git commit --quiet -m rewritten
	git push --quiet --force origin feature/x
	git switch --quiet develop
	run git review start feature/x --delta
	[ "$status" -ne 0 ]
	[[ "$output" == *"force-pushed"* ]]
}

@test "review start --delta --step after a force-push fails" {
	# The force-push guard lives in the --delta range resolution, before the
	# --step layout runs; --step must not let a rewritten history slip through.
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x)"
	force_push_feature

	run git review start feature/x --delta --step
	# Fails for the force-push reason specifically, not some other guard.
	[ "$status" -ne 0 ]
	[[ "$output" == *"force-pushed"* ]]

	# The guard must fire before --step creates the review branch or advances the
	# recorded tip — otherwise we'd be reviewing rewritten commits as "new".
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "review start --from after a force-push rejects the now-orphaned commit" {
	# A --from commit that is a genuine ancestor of origin/feature/x today.
	push_pr2
	from="$(git rev-parse origin/feature/x~1)"
	git merge-base --is-ancestor "$from" origin/feature/x

	# Rewrite the branch so that commit is no longer in its history.
	force_push_feature

	# The commit object still exists locally, so --from resolves it and the
	# failure is the ancestry check — not "unknown commit".
	run git rev-parse --verify --quiet "$from^{commit}"
	[ "$status" -eq 0 ]

	run git review start feature/x --from "$from"
	[ "$status" -ne 0 ]
	[[ "$output" == *"not an ancestor"* ]]
	[[ "$output" != *"unknown commit"* ]]

	# The guard fires before any review branch is created.
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "review start --delta after a genuine rebase fails" {
	# The existing force-push guard test rewrites with reset --hard; this exercises
	# the same guard via a real `git rebase`, the way a PR is rebased in practice.
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x)"
	old="$(git rev-parse origin/feature/x)"

	# Advance develop, then replay feature/x onto it so the PR commit gets a new
	# SHA and the recorded tip is no longer an ancestor of the rebased branch.
	git switch --quiet develop
	printf 'newdev\n' >newdev.txt
	git add newdev.txt
	git commit --quiet -m "develop advance"
	git push --quiet origin develop
	git switch --quiet feature/x
	git rebase --quiet develop
	git push --quiet --force origin feature/x
	git switch --quiet develop

	# Sanity: it really was rebased — the old tip is no longer an ancestor.
	run git merge-base --is-ancestor "$old" origin/feature/x
	[ "$status" -ne 0 ]

	run git review start feature/x --delta
	[ "$status" -ne 0 ]
	[[ "$output" == *"force-pushed"* ]]

	# The guard fires before any review branch is created or the tip advances.
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

# ── review finish side effects and guards ─────────────────────────────────────

@test "review finish refuses when review-fixes already exists" {
	git branch review-fixes/feature/x develop
	git review start feature/x
	printf 'a\nB\nc\nd\nfix\n' >app.txt
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"already exists"* ]]
}

@test "review finish --onto-source refuses a local branch behind the tip" {
	# Advance origin, then leave the local feature/x behind the reviewed tip.
	push_pr2
	git branch -f feature/x origin/feature/x~1
	git review start feature/x
	printf 'a\nB\nc\nd\ne\nfix\n' >app.txt
	run git review finish --onto-source
	[ "$status" -ne 0 ]
	[[ "$output" == *"not at the reviewed tip"* ]]
}

# ── review clean behaviours ───────────────────────────────────────────────────

@test "review clean with no branch deletes every review branch" {
	git switch --quiet -c feature/y develop
	printf 'a\nb\nc\nY\n' >app.txt
	git add app.txt
	git commit --quiet -m pr1y
	git push --quiet -u origin feature/y
	git switch --quiet develop

	git review start feature/x
	git switch --quiet develop
	git reset --hard --quiet
	git review start feature/y
	git switch --quiet develop
	git reset --hard --quiet

	run git review clean
	[ "$status" -eq 0 ]
	run git for-each-ref refs/heads/review/
	[ -z "$output" ]
}

@test "review clean reports when there are no review branches" {
	run git review clean
	[ "$status" -eq 0 ]
	[[ "$output" == *"no review branches found"* ]]
}

@test "review clean does not claim 'no review branches' when it drops orphaned refs" {
	# An orphaned undo ref with no matching review branch: review clean must
	# still purge it, and it must not pretend it had nothing to do.
	git update-ref refs/review-undo/feature/x/0 "$(git rev-parse HEAD)"

	run git review clean
	[ "$status" -eq 0 ]
	[[ "$output" != *"no review branches found"* ]]
	run git for-each-ref refs/review-undo/
	[ -z "$output" ]
}

@test "review clean keeps the recorded reviewed tip (forgetting moved to review forget --delta)" {
	git review start feature/x
	git switch --quiet develop
	git reset --hard --quiet
	[ -n "$(git config reviewworkflow.feature/x.reviewed)" ]
	run git review clean feature/x
	[ "$status" -eq 0 ]
	# review clean no longer owns the delta marker; it must survive
	[ -n "$(git config reviewworkflow.feature/x.reviewed)" ]
}

# ── review status: banked steps display ───────────────────────────────────────

@test "review status lists banked steps in step mode" {
	git switch --quiet -c feature/two develop
	printf 'a\nb\nc\nP1\n' >app.txt
	git add app.txt
	git commit --quiet -m t1
	printf 'a\nb\nc\nP1\nP2\n' >app.txt
	git add app.txt
	git commit --quiet -m t2
	git push --quiet -u origin feature/two
	git switch --quiet develop

	git review start feature/two --step
	printf 'a\nb\nc\nP1\nEDIT\n' >app.txt
	git review next
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"banked"* ]]
	[[ "$output" == *" 1"* ]]
}

# ── partial step metadata: a hand-deleted key must be reported, not die silently ─
#
# These commands read step metadata with `|| true`; under set -e a bare read of a
# missing key would otherwise kill the script with no message.

@test "review status reports a deleted reviewcount key instead of dying silently" {
	git review start feature/x --step
	git config --unset branch.review/feature/x.reviewcount
	run git review status
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
}

@test "review status reports a deleted reviewstep key instead of dying silently" {
	git review start feature/x --step
	git config --unset branch.review/feature/x.reviewstep
	run git review status
	[ "$status" -ne 0 ]
	[[ "$output" == *"corrupt review metadata"* ]]
}

@test "review next reports a deleted reviewstart key instead of dying silently" {
	git review start feature/x --step
	git config --unset branch.review/feature/x.reviewstart
	run git review next
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
}

# ── review finish on corrupt step metadata ────────────────────────────────────
#
# review finish used to read step metadata raw, without the guards the shared
# helper (load_step_review_meta) gives the other commands. Each corrupt key below
# either silently discarded the user's banked edits or died with an opaque shell /
# git / sed diagnostic. It now validates through the helper and reports a clear
# error, the way review next / review status do.

@test "review finish reports a deleted reviewcount instead of saying 'no changes'" {
	# `|| echo 0` defaulted a deleted reviewcount to 0, so the replay loop never
	# ran: every banked edit (FIXA) and the current step's edit (FIXB) were
	# discarded and review finish printed "no review changes to apply" — silent
	# data loss. It must report the corrupt metadata instead.
	step_review_two_with_edits
	git config --unset branch.review/feature/two.reviewcount
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" != *"no review changes to apply"* ]]
	[[ "$output" == *"missing review metadata"* ]]
}

@test "review finish with a deleted reviewcount preserves the undo point for --abort" {
	# The undo point is recorded before the step block runs. The old "no changes"
	# path cleared it, so --abort could not recover; the fix fails before clearing.
	step_review_two_with_edits
	git config --unset branch.review/feature/two.reviewcount
	run git review finish
	[ "$status" -ne 0 ]
	[ -n "$(git config branch.review/feature/two.reviewundohead || true)" ]

	run git review finish --abort
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/two" ]
	# The current step's edit (FIXB) must be back in the working tree.
	run git diff
	[[ "$output" == *"FIXB"* ]]
}

@test "review finish reports reviewcount=0 instead of silently losing edits" {
	step_review_two_with_edits
	git config branch.review/feature/two.reviewcount 0
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" != *"no review changes to apply"* ]]
	[[ "$output" == *"corrupt review metadata"* ]]
}

@test "review finish reports a non-numeric reviewcount instead of a shell error" {
	step_review_two_with_edits
	git config branch.review/feature/two.reviewcount abc
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" != *"no review changes to apply"* ]]
	[[ "$output" == *"corrupt review metadata"* ]]
}

@test "review finish reports a deleted reviewstart instead of dying silently" {
	# reviewstart was read without || true, so set -e killed review finish with no
	# message; the helper reads it with || true and reports it.
	step_review_two_with_edits
	git config --unset branch.review/feature/two.reviewstart
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
}

@test "review finish reports reviewstep=0 instead of an opaque sed error" {
	# step=0 reached `sed -n "0p"` ("invalid usage of line address 0"); now caught
	# by the helper's range check.
	step_review_two_with_edits
	git config branch.review/feature/two.reviewstep 0
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"out of range"* ]]
}

@test "review finish reports a reviewstep past the last commit instead of a git error" {
	# step past the commit count made `sed -n "${step}p"` empty, so rev-parse died
	# with "ambiguous argument"; now caught by the helper's range check.
	step_review_two_with_edits
	git config branch.review/feature/two.reviewstep 99
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"out of range"* ]]
}

@test "review finish on a step review with deleted reviewmode does not leak author commits" {
	# With reviewmode gone the step block was skipped and the whole-mode tail diffed
	# the current step commit (c1) against the tip (c2), reversing the author's c2
	# into the extracted fix. The step keys still present make the inconsistency
	# detectable: report it and never build the fix branch.
	make_two_commit_feature
	git review start feature/two --step
	# Stay on step 1 (HEAD = c1, not the tip c2).
	printf 'a2\nFIXA\n' >a.txt
	git config --unset branch.review/feature/two.reviewmode

	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"corrupt review metadata"* ]]
	# No review-fixes branch — so the author's c2 could not have leaked into one.
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/two
	[ "$status" -ne 0 ]
}

# ── a finish, then a second one off the review branch ─────────────────────────

@test "a second review finish is blocked once you are off the review branch" {
	git review start feature/x
	printf 'a\nB\nc\nd\nfix\n' >app.txt
	git review finish
	# the first finish left us on review-fixes/*, no longer a review/* branch
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}
