#!/usr/bin/env bats
#
# Tests for git-clean-review after the --forget split:
#   - it deletes both review/ and review-fixes/ branches, even if only one exists
#   - it drops banked edit refs even when no review branches remain
#   - it no longer owns the --delta marker (--forget is gone; use review-forget-delta)

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

# ── delete both namespaces, even if only one is present ────────────────────────

@test "clean-review <branch> deletes both review/ and review-fixes/ when both exist" {
	git branch review/feature/x develop
	git branch review-fixes/feature/x develop

	run git clean-review feature/x
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -ne 0 ]
}

@test "clean-review <branch> deletes review-fixes/ even when review/ is absent" {
	git branch review-fixes/feature/x develop

	run git clean-review feature/x
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -ne 0 ]
}

# ── drop banked edit refs even with no review branches left ────────────────────

@test "clean-review drops orphaned edit refs when no review branches remain" {
	git review-pr feature/x --step
	printf 'edited\n' >f.txt
	git review-next
	# leave and delete the review branch by hand, orphaning the banked edit ref
	git switch --quiet --discard-changes develop
	git branch -D review/feature/x >/dev/null

	# precondition: an edit ref exists and no review branches do
	[ -n "$(git for-each-ref refs/review-edits/feature/x/)" ]
	[ -z "$(git for-each-ref refs/heads/review/ refs/heads/review-fixes/)" ]

	run git clean-review
	[ "$status" -eq 0 ]
	# the orphaned edit ref must be gone
	[ -z "$(git for-each-ref refs/review-edits/feature/x/)" ]
}

# ── tear down the undo point fully, even on the branch we refuse to delete ──────

@test "clean-review removes every reviewundo* key, even for the current branch it skips" {
	git review-pr feature/x >/dev/null
	# leave an unresolved finish: record_exit writes reviewundoouthead/outtree
	printf 'edited\n' >f.txt
	git finish-review >/dev/null
	# stand back on the review branch so clean-review skips deleting it; the branch
	# survives, so its config is only cleaned by the explicit unset loop, not by
	# the branch -D that would otherwise drop the whole section.
	git switch --quiet review/feature/x

	run git clean-review feature/x
	[ "$status" -eq 0 ]

	# no reviewundo* key may linger — a missing key in the unset list orphans it
	run git config --get-regexp '^branch\.review/feature/x\.reviewundo'
	[ "$status" -ne 0 ]
	[ -z "$output" ]
}

# ── --forget is gone; the marker is no longer this command's concern ───────────

@test "clean-review rejects the removed --forget option" {
	run git clean-review feature/x --forget
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown option --forget"* ]]
}

@test "clean-review keeps the delta marker (forgetting moved to review-forget-delta)" {
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x)"
	git branch review/feature/x develop

	run git clean-review feature/x
	[ "$status" -eq 0 ]
	[ "$(git config reviewworkflow.feature/x.reviewed)" = "$(git rev-parse origin/feature/x)" ]
}
