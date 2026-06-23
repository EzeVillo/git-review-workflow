#!/usr/bin/env bats
#
# End-to-end tests for the git review commands. Each test runs in an isolated
# HOME with its own bare "origin" remote and a working clone.

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

@test "review-pr stages the whole PR as a diff" {
	run git review-pr feature/x
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git diff --cached
	[[ "$output" == *"+B"* ]]
	[[ "$output" == *"+d"* ]]
}

@test "review-pr accepts -- as the end-of-options separator" {
	run git review-pr -- feature/x develop
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
}

@test "review-pr -- takes a dash-leading name as a branch, not an option" {
	# the point of the separator: a name that looks like a flag is positional
	run git review-pr -- -nope develop
	[ "$status" -ne 0 ]
	[[ "$output" == *"-nope"* ]]
	[[ "$output" != *"unknown option"* ]]
}

@test "review-pr refuses a dirty working tree" {
	printf 'dirty\n' >>app.txt
	run git review-pr feature/x
	[ "$status" -ne 0 ]
	[[ "$output" == *"local changes"* ]]
}

@test "review-pr fails for an unknown branch" {
	run git review-pr nope/nope
	[ "$status" -ne 0 ]
	[[ "$output" == *"origin/nope/nope not found"* ]]
}

@test "review-pr honours reviewworkflow.base config" {
	git config reviewworkflow.base develop
	run git review-pr feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewbase)" = "develop" ]
}

@test "a full review with no base configured fails asking to set one" {
	git config --unset reviewworkflow.base
	run git review-pr feature/x
	[ "$status" -ne 0 ]
	[[ "$output" == *"no base branch set"* ]]
}

@test "finish-review extracts only the reviewer edits" {
	git review-pr feature/x
	printf 'a\nB\nc\nd\nfix\n' >app.txt
	run git finish-review
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	run git diff --cached
	[[ "$output" == *"+fix"* ]]
	[[ "$output" != *"+B"* ]]
}

@test "finish-review --onto-source stages edits on the PR branch" {
	git review-pr feature/x
	tip="$(git rev-parse feature/x)"
	printf 'a\nB\nc\nd\nfix\n' >app.txt
	run git finish-review --onto-source
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "feature/x" ]
	[[ "$output" == *"feature/x ready with your edits staged"* ]]
	# the edits are staged, not committed: feature/x still points at the tip
	[ "$(git rev-parse feature/x)" = "$tip" ]
	run git diff --cached --quiet
	[ "$status" -ne 0 ]
}

@test "finish-review reports when there are no edits" {
	git review-pr feature/x
	run git finish-review
	[ "$status" -eq 0 ]
	[[ "$output" == *"no review changes"* ]]
}

@test "finish-review --onto-source with no edits still lands on the PR branch" {
	git review-pr feature/x
	tip="$(git rev-parse feature/x)"
	run git finish-review --onto-source
	[ "$status" -eq 0 ]
	[[ "$output" == *"no review changes"* ]]
	# the flag's whole point: you end up on the PR branch, not review/feature/x
	[ "$(git rev-parse --abbrev-ref HEAD)" = "feature/x" ]
	[ "$(git rev-parse feature/x)" = "$tip" ]
	# the undo point was rolled back, leaving nothing to abort
	run git config --get-regexp '^branch\.review/feature/x\.reviewundo'
	[ "$status" -ne 0 ]
}

@test "finish-review with no edits leaves no undo point blocking a later finish" {
	git review-pr feature/x
	run git finish-review
	[ "$status" -eq 0 ]
	# a real edit + second finish must not be refused by a dangling undo point
	printf 'a\nB\nc\nd\nfix\n' >app.txt
	run git finish-review
	[ "$status" -eq 0 ]
	[[ "$output" == *"ready with your edits staged"* ]]
}

@test "review-pr --delta stages only new commits" {
	git review-pr feature/x
	git switch --quiet develop
	git clean-review feature/x
	push_pr2
	run git review-pr feature/x --delta
	[ "$status" -eq 0 ]
	run git diff --cached
	[[ "$output" == *"+e"* ]]
	[[ "$output" != *"+d"* ]]
}

@test "review-pr --delta without a prior review fails" {
	run git review-pr feature/x --delta
	[ "$status" -ne 0 ]
	[[ "$output" == *"no previous review"* ]]
}

@test "review-pr --this --local reviews the current branch" {
	git switch --quiet feature/x
	run git review-pr --this --local
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	[ "$(git config branch.review/feature/x.reviewsource)" = "feature/x" ]
	run git diff --cached
	[[ "$output" == *"+B"* ]]
	[[ "$output" == *"+d"* ]]
}

@test "review-pr --this rejects a positional branch argument" {
	git switch --quiet feature/x
	run git review-pr --this feature/x
	[ "$status" -ne 0 ]
	[[ "$output" == *"--this takes no branch argument"* ]]
}

@test "review-pr --this fails on a detached HEAD" {
	git switch --quiet feature/x
	git checkout --quiet --detach
	run git review-pr --this --local
	[ "$status" -ne 0 ]
	[[ "$output" == *"detached"* ]]
}

@test "review-pr --this refuses to review a review/* branch" {
	git review-pr feature/x
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git review-pr --this
	[ "$status" -ne 0 ]
	[[ "$output" == *"cannot review a review branch"* ]]
	# The guard must fire before any review/ branch is created: no nested
	# review/review/feature/x must be left behind.
	run git rev-parse --verify --quiet refs/heads/review/review/feature/x
	[ "$status" -ne 0 ]
}

@test "review-pr --this refuses to review a review-saved/* branch" {
	# Standing on a paused review (review-saved/<branch>), --this must not
	# derive src from it and create review/review-saved/<branch>.
	git switch --quiet -c review-saved/feature/x
	run git review-pr --this --local
	[ "$status" -ne 0 ]
	[[ "$output" == *"cannot review a review branch"* ]]
	run git rev-parse --verify --quiet refs/heads/review/review-saved/feature/x
	[ "$status" -ne 0 ]
}

@test "review-pr --this refuses to review a review-fixes/* branch" {
	# Standing on extracted edits (review-fixes/<branch>), --this must not
	# derive src from it and create review/review-fixes/<branch>.
	git switch --quiet -c review-fixes/feature/x
	run git review-pr --this --local
	[ "$status" -ne 0 ]
	[[ "$output" == *"cannot review a review branch"* ]]
	run git rev-parse --verify --quiet refs/heads/review/review-fixes/feature/x
	[ "$status" -ne 0 ]
}

@test "review-pr --this accepts a branch named review-* without a slash" {
	# Guards against a too-broad pattern (review* / review-*): a legitimate
	# user branch whose name merely starts with "review-" is not a review
	# branch and must be reviewable.
	git switch --quiet feature/x
	git switch --quiet -c review-dashboard
	printf 'a\nB\nc\nd\nrev\n' >app.txt
	git add app.txt
	git commit --quiet -m review-dashboard-work
	# Base comes from reviewworkflow.base (develop); --this takes no positional.
	run git review-pr --this --local
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/review-dashboard" ]
}

@test "review-pr notes when the local branch differs from the remote" {
	# Commit on feature/x locally without pushing, so origin/feature/x (what a
	# remote review targets) trails the local branch of the same name.
	git switch --quiet feature/x
	printf 'a\nB\nc\nd\nlocal\n' >app.txt
	git add app.txt
	git commit --quiet -m local-only
	git switch --quiet develop
	run git review-pr feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"differs from your local feature/x"* ]]
}

@test "review-pr does not warn when the local branch matches the remote" {
	# Guards against a warning that always fires: here local == origin.
	run git review-pr feature/x
	[ "$status" -eq 0 ]
	[[ "$output" != *"differs from your local"* ]]
}

@test "review-pr does not warn when there is no local branch of that name" {
	# A branch that exists only on the remote (e.g. a fresh clone): there is no
	# local copy to diverge from, so reviewing it must succeed without a note.
	git switch --quiet feature/x
	git switch --quiet -c feature/y
	printf 'a\nB\nc\nd\ny\n' >app.txt
	git add app.txt
	git commit --quiet -m pr-y
	git push --quiet -u origin feature/y
	git switch --quiet develop
	git branch --quiet -D feature/y
	run git review-pr feature/y
	[ "$status" -eq 0 ]
	[[ "$output" != *"differs from your local"* ]]
	run git diff --cached
	[[ "$output" == *"+y"* ]]
}

@test "review-pr --this reviews the remote, not unpushed local commits" {
	# The headline remote-mode case: standing on feature/x with an unpushed
	# commit, --this must review origin's snapshot (no +local) and warn.
	git switch --quiet feature/x
	printf 'a\nB\nc\nd\nlocal\n' >app.txt
	git add app.txt
	git commit --quiet -m local-only
	run git review-pr --this
	[ "$status" -eq 0 ]
	[[ "$output" == *"differs from your local feature/x"* ]]
	run git diff --cached
	[[ "$output" != *"+local"* ]]
	[[ "$output" == *"+d"* ]]
}

@test "review-pr --this --local reviews unpushed local commits without warning" {
	# The mirror case: --local must read the working branch, including the
	# unpushed commit, and never emit the remote-divergence note.
	git switch --quiet feature/x
	printf 'a\nB\nc\nd\nlocal\n' >app.txt
	git add app.txt
	git commit --quiet -m local-only
	run git review-pr --this --local
	[ "$status" -eq 0 ]
	[[ "$output" != *"differs from your local"* ]]
	run git diff --cached
	[[ "$output" == *"+local"* ]]
}

@test "review-pr --this resolves the actual current branch, not another" {
	# With more than one feature branch present, prove --this picks the one we
	# are standing on rather than, say, the base or the first branch.
	git switch --quiet feature/x
	git switch --quiet -c feature/z
	printf 'a\nB\nc\nd\nz\n' >app.txt
	git add app.txt
	git commit --quiet -m pr-z
	run git review-pr --this --local
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/z.reviewsource)" = "feature/z" ]
}

@test "review-pr --this on the base branch reports nothing to review" {
	# Standing on develop, --this resolves src=develop against base develop:
	# the range is empty, so it must error and leave no review branch behind.
	[ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ]
	run git review-pr --this --local
	[ "$status" -ne 0 ]
	[[ "$output" == *"no commits to review"* ]]
	run git rev-parse --verify --quiet refs/heads/review/develop
	[ "$status" -ne 0 ]
}

@test "review-pr reports nothing to review for a source already at the base" {
	# The same guard, reached without --this, to prove it is not --this-specific.
	run git review-pr develop develop
	[ "$status" -ne 0 ]
	[[ "$output" == *"no commits to review"* ]]
	run git rev-parse --verify --quiet refs/heads/review/develop
	[ "$status" -ne 0 ]
}

@test "review-pr --this --delta without a prior review fails" {
	git switch --quiet feature/x
	run git review-pr --this --local --delta
	[ "$status" -ne 0 ]
	[[ "$output" == *"no previous review"* ]]
}

@test "review-pr --this --local --delta stages only new local commits" {
	# Record a local marker, drop the review branch, add an unpushed commit,
	# then a --this --delta must stage only that new commit.
	git switch --quiet feature/x
	git review-pr --this --local
	git switch --quiet feature/x
	git clean-review feature/x
	printf 'a\nB\nc\nd\ne\n' >app.txt
	git add app.txt
	git commit --quiet -m pr2-local
	run git review-pr --this --local --delta
	[ "$status" -eq 0 ]
	run git diff --cached
	[[ "$output" == *"+e"* ]]
	[[ "$output" != *"+d"* ]]
}

@test "review-pr --step warns when the local branch differs from the remote" {
	# The divergence note must fire in step mode too (it is computed before the
	# step layout branches off).
	git switch --quiet feature/x
	printf 'a\nB\nc\nd\nlocal\n' >app.txt
	git add app.txt
	git commit --quiet -m local-only
	git switch --quiet develop
	run git review-pr feature/x --step
	[ "$status" -eq 0 ]
	[[ "$output" == *"differs from your local feature/x"* ]]
}

@test "review-pr --this resolves HEAD from a linked worktree" {
	# --this reads git symbolic-ref HEAD, which must reflect the worktree's own
	# checkout, not the main one.
	git switch --quiet develop
	wt="$TMP/wt"
	git worktree add --quiet -b feature/w "$wt" feature/x
	cd "$wt"
	run git review-pr --this --local
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/w.reviewsource)" = "feature/w" ]
}

@test "clean-review deletes the review branches" {
	git review-pr feature/x
	git switch --quiet develop
	run git clean-review feature/x
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "clean-review skips the currently checked out branch" {
	git review-pr feature/x
	run git clean-review feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"skipping review/feature/x"* ]]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -eq 0 ]
}

# ── --this composed with the range flags ──────────────────────────────────────

@test "review-pr --this --from <commit> reviews the remote from that commit" {
	git switch --quiet feature/x
	from="$(git rev-parse origin/feature/x^)"
	run git review-pr --this --from "$from"
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
}

@test "review-pr --this --local --delta --step reviews only new local commits in step mode" {
	git switch --quiet feature/x
	# a first local review records the local marker at the tip
	git review-pr --this --local
	git switch --quiet feature/x
	git clean-review feature/x
	# a new unpushed commit lands on top
	printf 'a\nB\nc\nd\ne\n' >app.txt
	git add app.txt
	git commit --quiet -m pr2-local
	run git review-pr --this --local --delta --step
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/1]"* ]]
}

@test "review-pr --this --from on the base branch reports nothing to review" {
	git switch --quiet develop
	base="$(git rev-parse develop)"
	run git review-pr --this --from "$base"
	[ "$status" -ne 0 ]
	[[ "$output" == *"no commits to review"* || "$output" == *"not an ancestor"* ]]
}
