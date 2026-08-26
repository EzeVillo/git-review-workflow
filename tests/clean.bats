#!/usr/bin/env bats
#
# Tests for git review clean after the --forget split:
#   - it deletes both review/ and review-fixes/ branches, even if only one exists
#   - it drops banked edit refs even when no review branches remain
#   - incomplete reviews roll back their --delta marker (like abort); finished ones keep it

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"

	git config --global user.email t@example.com
	git config --global user.name tester
	git config --global core.autocrlf false
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

# ── delete both namespaces, even if only one is present ────────────────────────

@test "review clean <branch> deletes both review/ and review-fixes/ when both exist" {
	git branch review/feature/x develop
	git branch review-fixes/feature/x develop

	run git review clean feature/x
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -ne 0 ]
}

@test "review clean <branch> deletes review-fixes/ even when review/ is absent" {
	git branch review-fixes/feature/x develop

	run git review clean feature/x
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -ne 0 ]
}

# ── drop banked edit refs even with no review branches left ────────────────────

@test "review clean drops orphaned edit refs when no review branches remain" {
	git review start feature/x --step
	printf 'edited\n' >f.txt
	git review next
	# leave and delete the review branch by hand, orphaning the banked edit ref
	git switch --quiet --discard-changes develop
	git branch -D review/feature/x >/dev/null

	# precondition: an edit ref exists and no review branches do
	[ -n "$(git for-each-ref refs/review-edits/feature/x/)" ]
	[ -z "$(git for-each-ref refs/heads/review/ refs/heads/review-fixes/)" ]

	run git review clean
	[ "$status" -eq 0 ]
	# the orphaned edit ref must be gone
	[ -z "$(git for-each-ref refs/review-edits/feature/x/)" ]
}

# ── tear down the undo point fully, even on the branch we refuse to delete ──────

@test "review clean removes every reviewundo* key, even for the current branch it skips" {
	git review start feature/x >/dev/null
	# leave an unresolved finish: record_exit writes reviewundoouthead/outtree
	printf 'edited\n' >f.txt
	git review finish >/dev/null
	# stand back on the review branch so review clean skips deleting it; the branch
	# survives, so its config is only cleaned by the explicit unset loop, not by
	# the branch -D that would otherwise drop the whole section.
	git switch --quiet review/feature/x

	run git review clean feature/x
	[ "$status" -eq 0 ]

	# no reviewundo* key may linger — a missing key in the unset list orphans it
	run git config --get-regexp '^branch\.review/feature/x\.reviewundo'
	[ "$status" -ne 0 ]
	[ -z "$output" ]
}

# ── honest message when only a saved review is around ──────────────────────────

@test "review clean points at the saved review when no review/ or review-fixes/ remain" {
	git review start feature/x >/dev/null
	printf 'edited\n' >f.txt
	git review save >/dev/null
	# precondition: a saved review exists, but nothing review clean owns
	[ -n "$(git for-each-ref refs/heads/review-saved/feature/x)" ]
	[ -z "$(git for-each-ref refs/heads/review/ refs/heads/review-fixes/)" ]

	run git review clean feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"saved review"* ]]
	[[ "$output" == *"git review continue"* ]]
	# the saved review must survive — review clean does not own that namespace
	run git rev-parse --verify --quiet refs/heads/review-saved/feature/x
	[ "$status" -eq 0 ]
}

@test "review clean still says 'no review branches found' when nothing at all exists" {
	run git review clean feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"no review branches found"* ]]
}

# ── --forget is gone; delta rollback is only for incomplete review sessions ────

@test "review clean rejects the removed --forget option" {
	run git review clean feature/x --forget
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown option --forget"* ]]
}

@test "review clean keeps a hand-set delta marker when the review branch has no session metadata" {
	# A bare review/* ref without start metadata is not a session: do not touch markers.
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x)"
	git branch review/feature/x develop

	run git review clean feature/x
	[ "$status" -eq 0 ]
	[ "$(git config reviewworkflow.feature/x.reviewed)" = "$(git rev-parse origin/feature/x)" ]
}

@test "review clean rolls back delta marker for an abandoned start" {
	# start advances the marker; clean of incomplete review/* must restore prev
	# so the next --delta does not skip never-reviewed commits.
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x~1)"
	git review start feature/x >/dev/null
	[ "$(git config reviewworkflow.feature/x.reviewed)" = "$(git rev-parse origin/feature/x)" ]
	git switch --quiet develop
	git reset --hard --quiet

	run git review clean feature/x
	[ "$status" -eq 0 ]
	[ "$(git config reviewworkflow.feature/x.reviewed)" = "$(git rev-parse origin/feature/x~1)" ]
}

@test "review clean keeps delta marker after a completed finish" {
	git review start feature/x >/dev/null
	printf 'edited\n' >f.txt
	git review finish >/dev/null
	marker="$(git rev-parse origin/feature/x)"
	[ "$(git config reviewworkflow.feature/x.reviewed)" = "$marker" ]
	git switch --quiet --discard-changes develop 2>/dev/null || {
		git reset --quiet --hard
		git clean --quiet -fd
		git switch --quiet develop
	}

	run git review clean feature/x
	[ "$status" -eq 0 ]
	[ "$(git config reviewworkflow.feature/x.reviewed)" = "$marker" ]
}

@test "review clean clears reviewresume with the undo keys" {
	git review start feature/x --step >/dev/null
	# Force a mid-conflict marker + undo without needing an overlapping PR:
	# finish records undo then we plant reviewresume as clean would see it.
	printf 'edited\n' >f.txt
	git review finish >/dev/null || true
	# After a normal finish we are on review-fixes; plant resume on the review branch.
	git config branch.review/feature/x.reviewresume conflict
	[ "$(git config branch.review/feature/x.reviewresume)" = "conflict" ]

	run git review clean feature/x
	[ "$status" -eq 0 ]
	[ -z "$(git config branch.review/feature/x.reviewresume || true)" ]
	[ -z "$(git config branch.review/feature/x.reviewundohead || true)" ]
}

# ── --keep-fixes: drop the finish undo, keep the deliverable ───────────────────

@test "review clean --keep-fixes deletes review/ and keeps review-fixes/" {
	git branch review/feature/x develop
	git branch review-fixes/feature/x develop

	run git review clean --keep-fixes feature/x
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -eq 0 ]
}

@test "review clean --keep-fixes after finish clears pending and keeps staged fixes" {
	# Happy path post-finish: drop the undo window, keep the deliverable even
	# when HEAD is not on review-fixes (e.g. develop after a switch).
	git review start feature/x >/dev/null
	printf 'edited\n' >f.txt
	git review finish >/dev/null
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	# Walk away like the sandbox / everyday case.
	git switch --quiet --discard-changes develop 2>/dev/null || {
		git reset --quiet --hard
		git clean --quiet -fd
		git switch --quiet develop
	}
	git reset --quiet --hard
	git clean --quiet -fd
	[ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ]
	[ -n "$(git for-each-ref refs/heads/review/feature/x)" ]
	[ -n "$(git for-each-ref refs/heads/review-fixes/feature/x)" ]

	run git review clean --keep-fixes feature/x
	[ "$status" -eq 0 ]

	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -eq 0 ]
	# Finish undo keys must go so list no longer reports finish pending.
	run git config --get-regexp '^branch\.review/feature/x\.reviewundo'
	[ "$status" -ne 0 ]
	[ -z "$output" ]
	run git review list --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" != *"finish	review/feature/x	pending"* ]]
	# Default clean still owns review-fixes when --keep-fixes is omitted.
	run git review clean feature/x
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -ne 0 ]
}

@test "review clean --keep-fixes without branch leaves every review-fixes/" {
	git branch review/feature/x develop
	git branch review-fixes/feature/x develop
	git branch review/feature/y develop
	git branch review-fixes/feature/y develop

	run git review clean --keep-fixes
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
	run git rev-parse --verify --quiet refs/heads/review/feature/y
	[ "$status" -ne 0 ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/y
	[ "$status" -eq 0 ]
}

@test "review clean --keep-fixes keeps the delta marker" {
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x)"
	git branch review/feature/x develop
	git branch review-fixes/feature/x develop

	run git review clean --keep-fixes feature/x
	[ "$status" -eq 0 ]
	[ "$(git config reviewworkflow.feature/x.reviewed)" = "$(git rev-parse origin/feature/x)" ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -eq 0 ]
}

@test "review clean rejects unknown flags but accepts --keep-fixes" {
	run git review clean --keep-fix feature/x
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown option --keep-fix"* ]]
}

@test "review clean skips edit banks when review branch is still checked out" {
	git review start feature/x --step
	printf 'edited\n' >f.txt
	git review next
	[ -n "$(git for-each-ref refs/review-edits/feature/x/)" ]
	# HEAD stays on review/* so clean skips deleting the branch; banks are still
	# live session state and must not be purged alongside the skip.
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]

	run git review clean feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"skipping"* ]]
	[ -n "$(git for-each-ref refs/review-edits/feature/x/)" ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -eq 0 ]
}

# -- --fixes-only: the mirror of --keep-fixes ---------------------------------

@test "review clean --fixes-only drops the extracted edits and leaves the session" {
	git branch review/feature/x develop
	git branch review-fixes/feature/x develop

	run git review clean --fixes-only feature/x
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -ne 0 ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -eq 0 ]
}

@test "review clean --fixes-only with no branch takes every fixes branch and no review" {
	git branch review/feature/x develop
	git branch review-fixes/feature/x develop
	git branch review-fixes/feature/y develop

	run git review clean --fixes-only
	[ "$status" -eq 0 ]
	[ -z "$(git for-each-ref refs/heads/review-fixes/)" ]
	[ "$(git for-each-ref --format='%(refname:short)' refs/heads/review/)" = "review/feature/x" ]
}

@test "review clean --fixes-only leaves banked edit refs and the finish undo alone" {
	git review start feature/x --step
	# A file of its own: an edit to f.txt overlaps the second commit and the
	# replay would stop on a conflict, which is a different test.
	printf 'note\n' >note.txt
	git review next
	git review finish >/dev/null

	# Preconditions: a finish undo point and a banked edit ref, both of which a
	# plain clean would tear down.
	[ -n "$(git config branch.review/feature/x.reviewundohead)" ]
	[ -n "$(git for-each-ref refs/review-edits/feature/x/)" ]

	git switch --quiet --discard-changes develop
	run git review clean --fixes-only feature/x
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -ne 0 ]
	# The session is untouched: you can still undo the finish.
	[ -n "$(git config branch.review/feature/x.reviewundohead)" ]
	[ -n "$(git for-each-ref refs/review-edits/feature/x/)" ]
	[ -n "$(git for-each-ref refs/review-undo/feature/x/)" ]
}

@test "review clean --fixes-only leaves the delta marker of an incomplete review" {
	# start records the tip it is about to review; a plain clean of an incomplete
	# review rolls that back, which is exactly what --fixes-only must not do.
	git review start feature/x >/dev/null
	marker="$(git config reviewworkflow.feature/x.reviewed)"
	[ -n "$marker" ]
	git branch review-fixes/feature/x develop

	git switch --quiet --discard-changes develop
	run git review clean --fixes-only feature/x
	[ "$status" -eq 0 ]
	# A plain clean would roll this back; --fixes-only never touches the session.
	[ "$(git config reviewworkflow.feature/x.reviewed)" = "$marker" ]
}

@test "review clean --fixes-only and --keep-fixes together are refused" {
	git branch review/feature/x develop
	git branch review-fixes/feature/x develop

	run git review clean --fixes-only --keep-fixes feature/x
	[ "$status" -eq 1 ]
	[[ "$output" == *"opposites"* ]]
	# And nothing was deleted.
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -eq 0 ]
}

@test "review clean --fixes-only says so when there is nothing to drop" {
	git branch review/feature/x develop

	run git review clean --fixes-only feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"no review-fixes/feature/x branch to clean"* ]]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -eq 0 ]
}
