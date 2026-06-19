#!/usr/bin/env bats
#
# State-dependent error and side-effect tests that the per-command files did not
# already cover: wrong-branch guards, missing metadata, branch-already-exists,
# --push / --forget side effects, the "previously reviewed" note and the
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

@test "clean-review --forget discards the recorded reviewed tip" {
	git review-pr feature/x
	git switch --quiet develop
	git reset --hard --quiet
	[ -n "$(git config reviewworkflow.feature/x.reviewed)" ]
	run git clean-review feature/x --forget
	[ "$status" -eq 0 ]
	run git config reviewworkflow.feature/x.reviewed
	[ "$status" -ne 0 ]
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
