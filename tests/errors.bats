#!/usr/bin/env bats
#
# State-dependent error and side-effect tests that the per-command files did not
# already cover: wrong-branch guards, missing metadata, branch-already-exists,
# --push side effects, the "previously reviewed" note and the
# force-push / no-new-commits delta guards.

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

# ── wrong-branch guards (run on develop, not a review/* branch) ───────────────

@test "review-next off a review branch errors" {
	run git review-next
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}

@test "review-prev off a review branch errors" {
	run git review-prev
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}

@test "review-status off a review branch errors" {
	run git review-status
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}

@test "review-abort off a review branch errors" {
	run git review-abort
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}

@test "finish-review off a review branch errors" {
	run git finish-review
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}

@test "review-prev requires step mode on a whole review" {
	git review-pr feature/x
	run git review-prev
	[ "$status" -ne 0 ]
	[[ "$output" == *"not started with git review-pr --step"* ]]
}

# ── missing review metadata on a hand-made review/* branch ────────────────────

@test "review-status reports missing metadata" {
	git switch --quiet -c review/orphan
	run git review-status
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
}

@test "review-abort reports missing metadata" {
	git switch --quiet -c review/orphan
	run git review-abort
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
}

@test "finish-review reports missing metadata" {
	git switch --quiet -c review/orphan
	run git finish-review
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
}

# ── review-pr guards ──────────────────────────────────────────────────────────

@test "review-pr refuses when the review branch already exists" {
	git review-pr feature/x
	git switch --quiet develop
	git reset --hard --quiet
	run git review-pr feature/x
	[ "$status" -ne 0 ]
	[[ "$output" == *"already exists"* ]]
}

@test "review-pr rejects an unknown explicit base" {
	run git review-pr feature/x nosuchbase
	[ "$status" -ne 0 ]
	[[ "$output" == *"origin/nosuchbase not found"* ]]
}

@test "review-pr --from= equals form stages the same range as --from" {
	push_pr2
	c1="$(git rev-parse origin/feature/x~1)"
	run git review-pr feature/x --from="$c1"
	[ "$status" -eq 0 ]
	run git diff --cached
	[[ "$output" == *"+e"* ]]
}

@test "review-pr notes new commits since the last full review" {
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x~1)"
	run git review-pr feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"previously reviewed"* ]]
	[[ "$output" == *"--delta"* ]]
}

@test "review-pr --delta with no new commits fails" {
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x)"
	run git review-pr feature/x --delta
	[ "$status" -ne 0 ]
	[[ "$output" == *"no new commits"* ]]
}

@test "review-pr --delta after a force-push fails" {
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x)"
	# Rewrite feature/x so the recorded tip is no longer an ancestor.
	git switch --quiet feature/x
	git reset --hard --quiet develop
	printf 'alt\n' >alt.txt
	git add alt.txt
	git commit --quiet -m rewritten
	git push --quiet --force origin feature/x
	git switch --quiet develop
	run git review-pr feature/x --delta
	[ "$status" -ne 0 ]
	[[ "$output" == *"force-pushed"* ]]
}

@test "review-pr --delta --step after a force-push fails" {
	# The force-push guard lives in the --delta range resolution, before the
	# --step layout runs; --step must not let a rewritten history slip through.
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x)"
	force_push_feature

	run git review-pr feature/x --delta --step
	# Fails for the force-push reason specifically, not some other guard.
	[ "$status" -ne 0 ]
	[[ "$output" == *"force-pushed"* ]]

	# The guard must fire before --step creates the review branch or advances the
	# recorded tip — otherwise we'd be reviewing rewritten commits as "new".
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "review-pr --from after a force-push rejects the now-orphaned commit" {
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

	run git review-pr feature/x --from "$from"
	[ "$status" -ne 0 ]
	[[ "$output" == *"not an ancestor"* ]]
	[[ "$output" != *"unknown commit"* ]]

	# The guard fires before any review branch is created.
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "review-pr --delta after a genuine rebase fails" {
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

	run git review-pr feature/x --delta
	[ "$status" -ne 0 ]
	[[ "$output" == *"force-pushed"* ]]

	# The guard fires before any review branch is created or the tip advances.
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

# ── finish-review side effects and guards ─────────────────────────────────────

@test "finish-review refuses when review-fixes already exists" {
	git branch review-fixes/feature/x develop
	git review-pr feature/x
	printf 'a\nB\nc\nd\nfix\n' >app.txt
	run git finish-review
	[ "$status" -ne 0 ]
	[[ "$output" == *"already exists"* ]]
}

@test "finish-review --push publishes review-fixes to origin" {
	git review-pr feature/x
	printf 'a\nB\nc\nd\nfix\n' >app.txt
	run git finish-review --push
	[ "$status" -eq 0 ]
	[[ "$output" == *"pushed review-fixes/feature/x to origin"* ]]
	run git ls-remote --heads origin review-fixes/feature/x
	[ -n "$output" ]
}

@test "finish-review --onto-source --push publishes fixes onto the PR branch" {
	git review-pr feature/x
	printf 'a\nB\nc\nd\nfix\n' >app.txt
	run git finish-review --onto-source --push
	[ "$status" -eq 0 ]
	[[ "$output" == *"pushed review fixes to origin/feature/x"* ]]
	run git log -1 --pretty=%s origin/feature/x
	[[ "$output" == *"review fixes (feature/x)"* ]]
}

@test "finish-review --onto-source refuses a local branch behind the tip" {
	# Advance origin, then leave the local feature/x behind the reviewed tip.
	push_pr2
	git branch -f feature/x origin/feature/x~1
	git review-pr feature/x
	printf 'a\nB\nc\nd\ne\nfix\n' >app.txt
	run git finish-review --onto-source
	[ "$status" -ne 0 ]
	[[ "$output" == *"not at the reviewed tip"* ]]
}

# Advance origin/feature/x to a new commit *without* touching this repo's
# working tree, HEAD, or the local feature/x branch — as if a teammate pushed
# while you were reviewing. Uses a throwaway worktree so the review state in
# WORK stays exactly as review-pr left it. Echoes the new origin tip.
advance_origin_only() {
	git worktree add --quiet --detach "$TMP/adv" origin/feature/x
	(
		cd "$TMP/adv"
		printf 'a\nB\nc\nd\nteammate\n' >app.txt
		git add app.txt
		git commit --quiet -m pr2-teammate
		git push --quiet origin HEAD:feature/x
		git rev-parse HEAD
	)
	git worktree remove --force "$TMP/adv"
}

@test "finish-review --onto-source --push refuses when origin advanced during review" {
	git review-pr feature/x
	# The reviewed tip == local feature/x == origin/feature/x at this point.
	reviewed="$(git rev-parse feature/x)"

	# A teammate pushes on top of the reviewed tip; our local feature/x and the
	# review branch are left untouched, so this isolates the origin-advanced
	# guard from the local-branch-behind guard (which would not trip here).
	advanced="$(advance_origin_only)"
	[ "$advanced" != "$reviewed" ]

	printf 'a\nB\nc\nd\nfix\n' >app.txt
	run git finish-review --onto-source --push

	# Fails for the right reason, naming the origin-advanced guard specifically.
	[ "$status" -ne 0 ]
	[[ "$output" == *"advanced since your review"* ]]

	# The guard must fire before any switch/commit/push side effect:
	# still parked on the review branch …
	[ "$(git symbolic-ref --quiet --short HEAD)" = "review/feature/x" ]
	# … local feature/x untouched (no "review fixes" commit landed) …
	[ "$(git rev-parse feature/x)" = "$reviewed" ]
	# … and origin/feature/x is exactly the teammate's commit, nothing pushed.
	[ "$(git ls-remote origin refs/heads/feature/x | cut -f1)" = "$advanced" ]
	run git log -1 --pretty=%s origin/feature/x
	[[ "$output" != *"review fixes"* ]]
}

# Rewrite origin/feature/x to a divergent history — a rebase + force-push by a
# teammate while you review — *without* touching this repo's working tree, HEAD,
# or the local feature/x branch. The new tip is built on origin/develop, so the
# reviewed tip is not an ancestor of it (a true rewrite, not a fast-forward).
# Uses a throwaway worktree so the review state in WORK is untouched. Echoes the
# new origin tip.
rebase_origin_only() {
	git worktree add --quiet --detach "$TMP/reb" origin/develop
	(
		cd "$TMP/reb"
		printf 'rebased\n' >rebased.txt
		git add rebased.txt
		git commit --quiet -m "feature rebased onto develop"
		git push --quiet --force origin HEAD:feature/x
		git rev-parse HEAD
	)
	git worktree remove --force "$TMP/reb"
}

@test "finish-review --onto-source --push refuses when the PR was rebased during review" {
	git review-pr feature/x
	reviewed="$(git rev-parse feature/x)"

	# The PR is rebased and force-pushed under us. Unlike the "advanced" case this
	# is a divergent rewrite: assert the reviewed tip is no longer an ancestor, so
	# the test cannot silently degrade into the fast-forward scenario.
	rewritten="$(rebase_origin_only)"
	[ "$rewritten" != "$reviewed" ]
	run git merge-base --is-ancestor "$reviewed" "$rewritten"
	[ "$status" -ne 0 ]

	printf 'a\nB\nc\nd\nfix\n' >app.txt
	run git finish-review --onto-source --push
	[ "$status" -ne 0 ]
	[[ "$output" == *"advanced since your review"* ]]

	# No side effects: still on the review branch, local feature/x untouched,
	# origin still exactly the rebased tip, and no review-fixes commit pushed.
	[ "$(git symbolic-ref --quiet --short HEAD)" = "review/feature/x" ]
	[ "$(git rev-parse feature/x)" = "$reviewed" ]
	[ "$(git ls-remote origin refs/heads/feature/x | cut -f1)" = "$rewritten" ]
	run git log -1 --pretty=%s origin/feature/x
	[[ "$output" != *"review fixes"* ]]
}

@test "finish-review --push (review-fixes) is unaffected by an origin rebase" {
	# The default flow targets a separate review-fixes/<branch> built on the frozen
	# reviewed tip; it never consults origin/<src>, so a rebase under us must not
	# block it. This is the deliberate counterpart to the --onto-source guard.
	git review-pr feature/x
	printf 'a\nB\nc\nd\nfix\n' >app.txt
	rewritten="$(rebase_origin_only)"

	run git finish-review --push
	[ "$status" -eq 0 ]
	[[ "$output" == *"pushed review-fixes/feature/x to origin"* ]]
	run git ls-remote --heads origin review-fixes/feature/x
	[ -n "$output" ]
	# origin/feature/x is left as the teammate's rebase, not rewritten by us.
	[ "$(git ls-remote origin refs/heads/feature/x | cut -f1)" = "$rewritten" ]
}

# ── clean-review behaviours ───────────────────────────────────────────────────

@test "clean-review with no branch deletes every review branch" {
	git switch --quiet -c feature/y develop
	printf 'a\nb\nc\nY\n' >app.txt
	git add app.txt
	git commit --quiet -m pr1y
	git push --quiet -u origin feature/y
	git switch --quiet develop

	git review-pr feature/x
	git switch --quiet develop
	git reset --hard --quiet
	git review-pr feature/y
	git switch --quiet develop
	git reset --hard --quiet

	run git clean-review
	[ "$status" -eq 0 ]
	run git for-each-ref refs/heads/review/
	[ -z "$output" ]
}

@test "clean-review reports when there are no review branches" {
	run git clean-review
	[ "$status" -eq 0 ]
	[[ "$output" == *"no review branches found"* ]]
}

@test "clean-review keeps the recorded reviewed tip (forgetting moved to review-forget)" {
	git review-pr feature/x
	git switch --quiet develop
	git reset --hard --quiet
	[ -n "$(git config reviewworkflow.feature/x.reviewed)" ]
	run git clean-review feature/x
	[ "$status" -eq 0 ]
	# clean-review no longer owns the delta marker; it must survive
	[ -n "$(git config reviewworkflow.feature/x.reviewed)" ]
}

# ── review-status: banked steps display ───────────────────────────────────────

@test "review-status lists banked steps in step mode" {
	git switch --quiet -c feature/two develop
	printf 'a\nb\nc\nP1\n' >app.txt
	git add app.txt
	git commit --quiet -m t1
	printf 'a\nb\nc\nP1\nP2\n' >app.txt
	git add app.txt
	git commit --quiet -m t2
	git push --quiet -u origin feature/two
	git switch --quiet develop

	git review-pr feature/two --step
	printf 'a\nb\nc\nP1\nEDIT\n' >app.txt
	git review-next
	run git review-status
	[ "$status" -eq 0 ]
	[[ "$output" == *"banked"* ]]
	[[ "$output" == *" 1"* ]]
}
