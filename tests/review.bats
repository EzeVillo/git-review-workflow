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

@test "review start stages the whole PR as a diff" {
	run git review start feature/x
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git diff --cached
	[[ "$output" == *"+B"* ]]
	[[ "$output" == *"+d"* ]]
}

@test "review start accepts -- as the end-of-options separator" {
	run git review start -- feature/x develop
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
}

@test "review start -- takes a dash-leading name as a branch, not an option" {
	# the point of the separator: a name that looks like a flag is positional
	run git review start -- -nope develop
	[ "$status" -ne 0 ]
	[[ "$output" == *"-nope"* ]]
	[[ "$output" != *"unknown option"* ]]
}

@test "review start refuses a dirty working tree" {
	printf 'dirty\n' >>app.txt
	run git review start feature/x
	[ "$status" -ne 0 ]
	[[ "$output" == *"local changes"* ]]
}

@test "review start fails for an unknown branch" {
	run git review start nope/nope
	[ "$status" -ne 0 ]
	[[ "$output" == *"origin/nope/nope not found"* ]]
}

@test "review start honours reviewworkflow.base config" {
	git config reviewworkflow.base develop
	run git review start feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewbase)" = "develop" ]
}

@test "a full review with no base configured fails asking to set one" {
	git config --unset reviewworkflow.base
	run git review start feature/x
	[ "$status" -ne 0 ]
	[[ "$output" == *"no base branch set"* ]]
}

@test "review finish extracts only the reviewer edits" {
	git review start feature/x
	printf 'a\nB\nc\nd\nfix\n' >app.txt
	run git review finish
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	run git diff --cached
	[[ "$output" == *"+fix"* ]]
	[[ "$output" != *"+B"* ]]
}

@test "review finish --onto-source stages edits on the PR branch" {
	git review start feature/x
	tip="$(git rev-parse feature/x)"
	printf 'a\nB\nc\nd\nfix\n' >app.txt
	run git review finish --onto-source
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "feature/x" ]
	[[ "$output" == *"feature/x ready with your edits staged"* ]]
	# the edits are staged, not committed: feature/x still points at the tip
	[ "$(git rev-parse feature/x)" = "$tip" ]
	run git diff --cached --quiet
	[ "$status" -ne 0 ]
}

@test "review finish reports when there are no edits" {
	git review start feature/x
	run git review finish
	[ "$status" -eq 0 ]
	[[ "$output" == *"no review changes"* ]]
}

@test "review finish --onto-source with no edits still lands on the PR branch" {
	git review start feature/x
	tip="$(git rev-parse feature/x)"
	run git review finish --onto-source
	[ "$status" -eq 0 ]
	[[ "$output" == *"no review changes"* ]]
	# the flag's whole point: you end up on the PR branch, not review/feature/x
	[ "$(git rev-parse --abbrev-ref HEAD)" = "feature/x" ]
	[ "$(git rev-parse feature/x)" = "$tip" ]
	# the undo point was rolled back, leaving nothing to abort
	run git config --get-regexp '^branch\.review/feature/x\.reviewundo'
	[ "$status" -ne 0 ]
}

@test "review finish with no edits leaves no undo point blocking a later finish" {
	git review start feature/x
	run git review finish
	[ "$status" -eq 0 ]
	# a real edit + second finish must not be refused by a dangling undo point
	printf 'a\nB\nc\nd\nfix\n' >app.txt
	run git review finish
	[ "$status" -eq 0 ]
	[[ "$output" == *"ready with your edits staged"* ]]
}

@test "review start --delta stages only new commits" {
	git review start feature/x
	git switch --quiet develop
	git review clean feature/x
	push_pr2
	run git review start feature/x --delta
	[ "$status" -eq 0 ]
	run git diff --cached
	[[ "$output" == *"+e"* ]]
	[[ "$output" != *"+d"* ]]
}

@test "review start --delta without a prior review fails" {
	run git review start feature/x --delta
	[ "$status" -ne 0 ]
	[[ "$output" == *"no previous review"* ]]
}

@test "review start with no branch reviews the current branch" {
	git switch --quiet feature/x
	run git review start --local
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	[ "$(git config branch.review/feature/x.reviewsource)" = "feature/x" ]
	run git diff --cached
	[[ "$output" == *"+B"* ]]
	[[ "$output" == *"+d"* ]]
}

@test "review start --base reviews the current branch against an explicit base" {
	# The wart --this carried: with the branch omitted there was no way to also
	# name a base — the lone positional fell into src and base was unreachable.
	# --base destapa it; review the current branch against a base we pass, with
	# no reviewworkflow.base configured at all to prove the base really comes
	# from --base and not from config.
	git switch --quiet feature/x
	git config --unset reviewworkflow.base
	run git review start --base develop --local
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewsource)" = "feature/x" ]
	[ "$(git config branch.review/feature/x.reviewbase)" = "develop" ]
	run git diff --cached
	[[ "$output" == *"+B"* ]]
	[[ "$output" == *"+d"* ]]
}

@test "review start rejects a base given both positionally and with --base" {
	run git review start feature/x develop --base main
	[ "$status" -ne 0 ]
	[[ "$output" == *"base given more than once"* ]]
}

@test "review start --base= rejects an empty value, not silently ignored" {
	run git review start feature/x --base=
	[ "$status" -ne 0 ]
	[[ "$output" == *"--base requires a base"* ]]
}

@test "review start --base with no value at the end of the args is rejected" {
	# The separate-token form: --base consumes the next arg, but there is none.
	run git review start feature/x --base
	[ "$status" -ne 0 ]
	[[ "$output" == *"--base requires a base"* ]]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "review start rejects --base given twice in the = form" {
	# The positional+--base clash is covered above; this hits the duplicate guard
	# through the --base= arm specifically.
	run git review start feature/x --base=develop --base=main
	[ "$status" -ne 0 ]
	[[ "$output" == *"base given more than once"* ]]
}

@test "review start with no branch fails on a detached HEAD" {
	git switch --quiet feature/x
	git checkout --quiet --detach
	run git review start --local
	[ "$status" -ne 0 ]
	[[ "$output" == *"detached"* ]]
}

@test "review start with no branch refuses to review a review/* branch" {
	git review start feature/x
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git review start
	[ "$status" -ne 0 ]
	[[ "$output" == *"refusing to review a review branch"* ]]
	# The guard must fire before any review/ branch is created: no nested
	# review/review/feature/x must be left behind.
	run git rev-parse --verify --quiet refs/heads/review/review/feature/x
	[ "$status" -ne 0 ]
}

@test "review start with no branch refuses to review a review-saved/* branch" {
	# Standing on a paused review (review-saved/<branch>), an omitted branch must
	# not derive src from it and create review/review-saved/<branch>.
	git switch --quiet -c review-saved/feature/x
	run git review start --local
	[ "$status" -ne 0 ]
	[[ "$output" == *"refusing to review a review branch"* ]]
	run git rev-parse --verify --quiet refs/heads/review/review-saved/feature/x
	[ "$status" -ne 0 ]
}

@test "review start with no branch refuses to review a review-fixes/* branch" {
	# Standing on extracted edits (review-fixes/<branch>), an omitted branch must
	# not derive src from it and create review/review-fixes/<branch>.
	git switch --quiet -c review-fixes/feature/x
	run git review start --local
	[ "$status" -ne 0 ]
	[[ "$output" == *"refusing to review a review branch"* ]]
	run git rev-parse --verify --quiet refs/heads/review/review-fixes/feature/x
	[ "$status" -ne 0 ]
}

@test "review start with no branch accepts a branch named review-* without a slash" {
	# Guards against a too-broad pattern (review* / review-*): a legitimate
	# user branch whose name merely starts with "review-" is not a review
	# branch and must be reviewable when its name is omitted.
	git switch --quiet feature/x
	git switch --quiet -c review-dashboard
	printf 'a\nB\nc\nd\nrev\n' >app.txt
	git add app.txt
	git commit --quiet -m review-dashboard-work
	# Base comes from reviewworkflow.base (develop); the branch is omitted.
	run git review start --local
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/review-dashboard" ]
}

@test "review start accepts a tag as the base" {
	# #4: the base generalises to any commit-ish, so a tag works as a read-only
	# lower bound even though it never materialises as origin/<tag>.
	git tag v1.0 develop
	run git review start feature/x v1.0
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewbase)" = "v1.0" ]
	run git diff --cached
	[[ "$output" == *"+B"* ]]
	[[ "$output" == *"+d"* ]]
}

@test "review start accepts a commit SHA as the base" {
	sha="$(git rev-parse develop)"
	run git review start feature/x "$sha"
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewbase)" = "$sha" ]
	run git diff --cached
	[[ "$output" == *"+B"* ]]
	[[ "$output" == *"+d"* ]]
}

@test "review start fails clearly when the base resolves to nothing" {
	# A base that is neither a branch nor any commit-ish must be reported as not
	# found, before any review branch is created.
	run git review start feature/x no-such-base
	[ "$status" -ne 0 ]
	[[ "$output" == *"not found"* ]]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "review start notes when the local branch differs from the remote" {
	# Commit on feature/x locally without pushing, so origin/feature/x (what a
	# remote review targets) trails the local branch of the same name.
	git switch --quiet feature/x
	printf 'a\nB\nc\nd\nlocal\n' >app.txt
	git add app.txt
	git commit --quiet -m local-only
	git switch --quiet develop
	run git review start feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"differs from your local feature/x"* ]]
}

@test "review start does not warn when the local branch matches the remote" {
	# Guards against a warning that always fires: here local == origin.
	run git review start feature/x
	[ "$status" -eq 0 ]
	[[ "$output" != *"differs from your local"* ]]
}

@test "review start does not warn when there is no local branch of that name" {
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
	run git review start feature/y
	[ "$status" -eq 0 ]
	[[ "$output" != *"differs from your local"* ]]
	run git diff --cached
	[[ "$output" == *"+y"* ]]
}

@test "review start with no branch reviews the remote, not unpushed local commits" {
	# The headline remote-mode case: standing on feature/x with an unpushed
	# commit, an omitted branch must review origin's snapshot (no +local) and warn.
	git switch --quiet feature/x
	printf 'a\nB\nc\nd\nlocal\n' >app.txt
	git add app.txt
	git commit --quiet -m local-only
	run git review start
	[ "$status" -eq 0 ]
	[[ "$output" == *"differs from your local feature/x"* ]]
	run git diff --cached
	[[ "$output" != *"+local"* ]]
	[[ "$output" == *"+d"* ]]
}

@test "review start with no branch --local reviews unpushed local commits without warning" {
	# The mirror case: --local must read the working branch, including the
	# unpushed commit, and never emit the remote-divergence note.
	git switch --quiet feature/x
	printf 'a\nB\nc\nd\nlocal\n' >app.txt
	git add app.txt
	git commit --quiet -m local-only
	run git review start --local
	[ "$status" -eq 0 ]
	[[ "$output" != *"differs from your local"* ]]
	run git diff --cached
	[[ "$output" == *"+local"* ]]
}

@test "review start with no branch resolves the actual current branch, not another" {
	# With more than one feature branch present, prove the omitted branch picks the
	# one we are standing on rather than, say, the base or the first branch.
	git switch --quiet feature/x
	git switch --quiet -c feature/z
	printf 'a\nB\nc\nd\nz\n' >app.txt
	git add app.txt
	git commit --quiet -m pr-z
	run git review start --local
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/z.reviewsource)" = "feature/z" ]
}

@test "review start with no branch on the base branch reports nothing to review" {
	# Standing on develop, an omitted branch resolves src=develop against base
	# develop: the range is empty, so it must error and leave no review branch.
	[ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ]
	run git review start --local
	[ "$status" -ne 0 ]
	[[ "$output" == *"no commits to review"* ]]
	run git rev-parse --verify --quiet refs/heads/review/develop
	[ "$status" -ne 0 ]
}

@test "review start reports nothing to review for a source already at the base" {
	# The same guard, reached with an explicit branch, to prove it is not specific
	# to the omitted-branch path.
	run git review start develop develop
	[ "$status" -ne 0 ]
	[[ "$output" == *"no commits to review"* ]]
	run git rev-parse --verify --quiet refs/heads/review/develop
	[ "$status" -ne 0 ]
}

@test "review start with no branch --delta without a prior review fails" {
	git switch --quiet feature/x
	run git review start --local --delta
	[ "$status" -ne 0 ]
	[[ "$output" == *"no previous review"* ]]
}

@test "review start with no branch --local --delta stages only new local commits" {
	# Record a local marker, drop the review branch, add an unpushed commit,
	# then an omitted-branch --delta must stage only that new commit.
	git switch --quiet feature/x
	git review start --local
	git switch --quiet feature/x
	git review clean feature/x
	printf 'a\nB\nc\nd\ne\n' >app.txt
	git add app.txt
	git commit --quiet -m pr2-local
	run git review start --local --delta
	[ "$status" -eq 0 ]
	run git diff --cached
	[[ "$output" == *"+e"* ]]
	[[ "$output" != *"+d"* ]]
}

@test "review start --step warns when the local branch differs from the remote" {
	# The divergence note must fire in step mode too (it is computed before the
	# step layout branches off).
	git switch --quiet feature/x
	printf 'a\nB\nc\nd\nlocal\n' >app.txt
	git add app.txt
	git commit --quiet -m local-only
	git switch --quiet develop
	run git review start feature/x --step
	[ "$status" -eq 0 ]
	[[ "$output" == *"differs from your local feature/x"* ]]
}

@test "review start with no branch resolves HEAD from a linked worktree" {
	# An omitted branch reads git symbolic-ref HEAD, which must reflect the
	# worktree's own checkout, not the main one.
	git switch --quiet develop
	wt="$TMP/wt"
	git worktree add --quiet -b feature/w "$wt" feature/x
	cd "$wt"
	run git review start --local
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/w.reviewsource)" = "feature/w" ]
}

@test "review clean deletes the review branches" {
	git review start feature/x
	git switch --quiet develop
	run git review clean feature/x
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "review clean skips the currently checked out branch" {
	git review start feature/x
	run git review clean feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"skipping review/feature/x"* ]]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -eq 0 ]
}

# ── an omitted branch composed with the range flags ───────────────────────────

@test "review start with no branch --from <commit> reviews the remote from that commit" {
	git switch --quiet feature/x
	from="$(git rev-parse origin/feature/x^)"
	run git review start --from "$from"
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
}

@test "review start with no branch --local --delta --step reviews only new local commits in step mode" {
	git switch --quiet feature/x
	# a first local review records the local marker at the tip
	git review start --local
	git switch --quiet feature/x
	git review clean feature/x
	# a new unpushed commit lands on top
	printf 'a\nB\nc\nd\ne\n' >app.txt
	git add app.txt
	git commit --quiet -m pr2-local
	run git review start --local --delta --step
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/1]"* ]]
}

@test "review start with no branch --from on the base branch reports nothing to review" {
	git switch --quiet develop
	base="$(git rev-parse develop)"
	run git review start --from "$base"
	[ "$status" -ne 0 ]
	[[ "$output" == *"no commits to review"* || "$output" == *"not an ancestor"* ]]
}
