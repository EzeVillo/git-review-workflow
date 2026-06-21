#!/usr/bin/env bats
#
# Tests for git review-pr --local: review your local branches directly, without
# fetching. The local tip is deliberately kept ahead of the remote one (an extra
# unpushed commit) so a local review and a remote review of the same branch name
# see different things — and must never overwrite each other's --delta progress.

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

	# feature/x: C1 (a.txt) is pushed; C2 (b.txt) stays local only.
	git switch --quiet -c feature/x
	printf 'a\n' >a.txt
	git add a.txt
	git commit --quiet -m c1-add-a
	git push --quiet -u origin feature/x
	printf 'b\n' >b.txt
	git add b.txt
	git commit --quiet -m c2-add-b

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

@test "--local reviews the local tip, including unpushed commits" {
	run git review-pr feature/x --local
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git diff --cached --name-only
	# Both the pushed commit and the local-only one are part of the review.
	[[ "$output" == *"a.txt"* ]]
	[[ "$output" == *"b.txt"* ]]
}

@test "--local does not fetch; works with an unreachable remote" {
	git remote set-url origin "$TMP/does-not-exist.git"
	run git review-pr feature/x --local
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
}

@test "--local names the local base, not the remote, in the range message" {
	run git review-pr feature/x --local
	[ "$status" -eq 0 ]
	[[ "$output" == *"vs develop"* ]]
	[[ "$output" != *"origin/"* ]]
}

@test "--local records a separate marker that does not collide with the remote one" {
	git review-pr feature/x --local
	# The local marker points at the local tip; the remote marker is untouched.
	run git config reviewworkflowlocal.feature/x.reviewed
	[ "$status" -eq 0 ]
	[ "$output" = "$(git rev-parse feature/x)" ]
	run git config reviewworkflow.feature/x.reviewed
	[ "$status" -ne 0 ]
}

@test "a local review does not disturb a prior remote review's marker" {
	git review-pr feature/x
	remote_marker="$(git config reviewworkflow.feature/x.reviewed)"
	git switch --quiet --discard-changes develop
	git clean-review feature/x
	git review-pr feature/x --local
	# The remote marker still points where the remote review left it.
	[ "$(git config reviewworkflow.feature/x.reviewed)" = "$remote_marker" ]
	[ "$(git config reviewworkflowlocal.feature/x.reviewed)" = "$(git rev-parse feature/x)" ]
	[ "$remote_marker" != "$(git rev-parse feature/x)" ]
}

@test "finish-review on a local review extracts edits locally" {
	git review-pr feature/x --local
	printf 'b\nFIXB\n' >b.txt
	run git finish-review
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	run git diff --cached
	[[ "$output" == *"+FIXB"* ]]
}

@test "abort rolls back the local marker, leaving the remote marker intact" {
	git review-pr feature/x
	remote_marker="$(git config reviewworkflow.feature/x.reviewed)"
	git switch --quiet --discard-changes develop
	git clean-review feature/x
	git review-pr feature/x --local
	run git review-abort
	[ "$status" -eq 0 ]
	# The cancelled local review left no local marker behind...
	run git config reviewworkflowlocal.feature/x.reviewed
	[ "$status" -ne 0 ]
	# ...and never touched the remote one.
	[ "$(git config reviewworkflow.feature/x.reviewed)" = "$remote_marker" ]
}

@test "review-forget <branch> clears the local marker" {
	git review-pr feature/x --local
	git switch --quiet develop
	git clean-review feature/x
	run git review-forget feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"(local)"* ]]
	run git config reviewworkflowlocal.feature/x.reviewed
	[ "$status" -ne 0 ]
}

@test "review-forget --stale clears a local marker when the local branch is gone" {
	git review-pr feature/x --local
	git switch --quiet develop
	git clean-review feature/x
	git branch -D feature/x
	run git review-forget --stale
	[ "$status" -eq 0 ]
	[[ "$output" == *"local; feature/x no longer exists"* ]]
	run git config reviewworkflowlocal.feature/x.reviewed
	[ "$status" -ne 0 ]
}

@test "review-forget --stale keeps a local marker whose local branch still exists" {
	git review-pr feature/x --local
	git switch --quiet develop
	git clean-review feature/x
	# Delete the remote branch but keep the local one: the local marker must stay.
	git push --quiet origin --delete feature/x
	run git review-forget --stale
	[ "$status" -eq 0 ]
	run git config reviewworkflowlocal.feature/x.reviewed
	[ "$status" -eq 0 ]
}

@test "--local --delta reviews only the commits added since the last local review" {
	# A full local review records the local marker at the local tip (C2)...
	git review-pr feature/x --local
	git switch --quiet --discard-changes develop
	git clean-review feature/x
	# ...then a third, local-only commit (C3) lands on top.
	git switch --quiet feature/x
	printf 'c\n' >c.txt
	git add c.txt
	git commit --quiet -m c3-add-c
	git switch --quiet develop

	run git review-pr feature/x --local --delta
	[ "$status" -eq 0 ]
	[[ "$output" == *"since last review"* ]]
	run git diff --cached --name-only
	# Only the commit added since the marker is in range; the earlier ones are not.
	[[ "$output" == *"c.txt"* ]]
	[[ "$output" != *"a.txt"* ]]
	[[ "$output" != *"b.txt"* ]]
}

@test "--local --delta is bounded by the local marker, not the remote one" {
	# A remote review records the remote marker at the pushed tip (C1)...
	git review-pr feature/x
	git switch --quiet --discard-changes develop
	git clean-review feature/x
	# ...and a local review records the local marker at the local tip (C2).
	git review-pr feature/x --local
	git switch --quiet --discard-changes develop
	git clean-review feature/x
	# A new local-only commit (C3) lands on top of the local tip.
	git switch --quiet feature/x
	printf 'c\n' >c.txt
	git add c.txt
	git commit --quiet -m c3-add-c
	git switch --quiet develop

	run git review-pr feature/x --local --delta
	[ "$status" -eq 0 ]
	run git diff --cached --name-only
	# The range starts at the local marker (C2 = b.txt), so only c.txt is new. Had
	# it used the remote marker (C1 = a.txt), b.txt would wrongly appear in range.
	[[ "$output" == *"c.txt"* ]]
	[[ "$output" != *"b.txt"* ]]
	[[ "$output" != *"a.txt"* ]]
}

@test "--local --step records the local marker and the local flag" {
	run git review-pr feature/x --local --step
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	[ "$(git config branch.review/feature/x.reviewlocal)" = "1" ]
	[ "$(git config reviewworkflowlocal.feature/x.reviewed)" = "$(git rev-parse feature/x)" ]
	# The remote marker is left untouched by a local --step review.
	run git config reviewworkflow.feature/x.reviewed
	[ "$status" -ne 0 ]
}

@test "abort on a local --step review rolls back the local marker" {
	git review-pr feature/x --local --step
	run git review-abort
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ]
	# No prior local review existed, so the marker is cleared, not left dangling.
	run git config reviewworkflowlocal.feature/x.reviewed
	[ "$status" -ne 0 ]
}

@test "finish-review on a local --step review replays banked edits locally" {
	git review-pr feature/x --local --step
	# Edit the first commit (C1 = a.txt), then advance to bank that edit.
	printf 'a\nFIXA\n' >a.txt
	git review-next
	run git finish-review
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	run git diff --cached
	[[ "$output" == *"+FIXA"* ]]
}

@test "--local fails clearly when the local base branch is missing" {
	# Drop the local base branch so --local has nothing to diff against; the
	# remote-tracking origin/develop must not be used as a fallback.
	git switch --quiet feature/x
	git branch -D develop
	run git review-pr feature/x --local
	[ "$status" -ne 0 ]
	[[ "$output" == *"develop not found"* ]]
	# It failed before creating the review branch.
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "finish-review --onto-source on a local review stages onto the local branch" {
	git review-pr feature/x --local
	tip="$(git rev-parse feature/x)"
	printf 'b\nFIXB\n' >b.txt
	run git finish-review --onto-source
	[ "$status" -eq 0 ]
	# The fix is staged onto feature/x itself, and we end up there.
	[ "$(git rev-parse --abbrev-ref HEAD)" = "feature/x" ]
	[[ "$output" == *"feature/x ready with your edits staged"* ]]
	[ "$(git rev-parse feature/x)" = "$tip" ]
	run git diff --cached
	[[ "$output" == *"+FIXB"* ]]
}

# ── regression: a branch literally named "<x>.local" must not collide with the
# local marker of "<x>". Local markers live in their own config section
# (reviewworkflowlocal.*), so the two keys are disjoint. With the old
# reviewworkflow.<x>.local.reviewed scheme these were the same key.

# make_dotlocal_branch: create and push a branch named feature/x.local (one commit
# on top of develop) and return to develop, leaving origin/feature/x.local set.
make_dotlocal_branch() {
	git switch --quiet -c feature/x.local develop
	printf 'd\n' >d.txt
	git add d.txt
	git commit --quiet -m d-add-d
	git push --quiet -u origin feature/x.local
	git switch --quiet develop
}

@test "a remote review of <x>.local and a local review of <x> use disjoint markers" {
	make_dotlocal_branch

	# Remote review of feature/x.local -> reviewworkflow.feature/x.local.reviewed
	git review-pr feature/x.local
	git switch --quiet --discard-changes develop
	git clean-review feature/x.local
	# Local review of feature/x -> reviewworkflowlocal.feature/x.reviewed
	git review-pr feature/x --local

	# Each marker holds exactly what its own review recorded...
	[ "$(git config reviewworkflow.feature/x.local.reviewed)" = "$(git rev-parse origin/feature/x.local)" ]
	[ "$(git config reviewworkflowlocal.feature/x.reviewed)" = "$(git rev-parse feature/x)" ]
	# ...and they are different commits, proving they never shared a key.
	[ "$(git config reviewworkflow.feature/x.local.reviewed)" != "$(git config reviewworkflowlocal.feature/x.reviewed)" ]
}

@test "review-forget <x> leaves the remote marker of the branch named <x>.local alone" {
	make_dotlocal_branch

	git review-pr feature/x.local
	git switch --quiet --discard-changes develop
	git clean-review feature/x.local
	git review-pr feature/x --local
	git switch --quiet --discard-changes develop
	git clean-review feature/x

	run git review-forget feature/x
	[ "$status" -eq 0 ]
	# Only feature/x's own (local) marker is cleared...
	run git config reviewworkflowlocal.feature/x.reviewed
	[ "$status" -ne 0 ]
	# ...the remote marker belonging to the branch named feature/x.local survives.
	[ -n "$(git config reviewworkflow.feature/x.local.reviewed)" ]
}

@test "review-forget --stale keeps a <x>.local remote marker even when local <x> is gone" {
	make_dotlocal_branch

	git review-pr feature/x.local       # remote marker reviewworkflow.feature/x.local.reviewed
	git switch --quiet --discard-changes develop
	git clean-review feature/x.local

	# Remove the local feature/x branch; keep the remote feature/x.local branch.
	git branch -D feature/x

	run git review-forget --stale
	[ "$status" -eq 0 ]
	# The marker is keyed off origin/feature/x.local (still present), so it stays.
	# The old scheme mis-routed it to local feature/x and would have forgotten it.
	[ -n "$(git config reviewworkflow.feature/x.local.reviewed)" ]
}
