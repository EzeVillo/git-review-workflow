#!/usr/bin/env bats
#
# Tests for git review preview — show the edits made so far without disturbing
# them, so editing can continue from where it was.
#
# The PR (feature/x) has four commits on top of develop: A touches a.txt,
# B touches b.txt, C touches c.txt, D touches d.txt — the same fixture as
# save.bats, which gives enough commits to bank edits across steps.

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

@test "preview (whole) shows your edits and leaves the review untouched" {
	git review start feature/x develop
	printf 'a1\na2\nWHOLEFIX\n' >a.txt
	run git review preview
	[ "$status" -eq 0 ]
	[[ "$output" == *"+WHOLEFIX"* ]]
	# still on the review branch, edit still in the working tree, PR still staged
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git diff
	[[ "$output" == *"WHOLEFIX"* ]]
	run git diff --cached --name-only
	[[ "$output" == *"a.txt"* ]]
	# and review finish still works afterwards — preview banked/committed nothing
	git review finish
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	run git diff --cached
	[[ "$output" == *"+WHOLEFIX"* ]]
}

@test "preview (whole) includes brand-new untracked files" {
	git review start feature/x develop
	printf 'brand new\n' >newfile.txt
	run git review preview
	[ "$status" -eq 0 ]
	[[ "$output" == *"newfile.txt"* ]]
	[[ "$output" == *"+brand new"* ]]
}

@test "preview (whole) with no edits says so and exits 0" {
	git review start feature/x develop
	run git review preview
	[ "$status" -eq 0 ]
	[[ "$output" == *"no review changes yet"* ]]
}

@test "preview --stat shows a summary" {
	git review start feature/x develop
	printf 'a1\na2\nWHOLEFIX\n' >a.txt
	run git review preview --stat
	[ "$status" -eq 0 ]
	[[ "$output" == *"a.txt"* ]]
	[[ "$output" == *"changed"* ]]
	# a summary, not the full diff — the added line must not appear
	[[ "$output" != *"+WHOLEFIX"* ]]
}

@test "preview (whole) shows file deletions" {
	git review start feature/x develop
	rm a.txt
	run git review preview
	[ "$status" -eq 0 ]
	[[ "$output" == *"deleted file"* ]]
	[[ "$output" == *"a.txt"* ]]
}

@test "preview (whole, --from) shows edits against the tip regardless of range" {
	# The range flag chooses the lower bound; preview always diffs against the tip,
	# so an edit shows the same whether the review is full or --from a commit.
	first="$(git rev-list --reverse --first-parent feature/x ^develop | sed -n '1p')"
	git review start feature/x --from "$first"
	printf 'd\nFROMFIX\n' >d.txt
	run git review preview
	[ "$status" -eq 0 ]
	[[ "$output" == *"+FROMFIX"* ]]
}

# ── step mode ─────────────────────────────────────────────────────────────────

@test "preview (step) shows banked and current-step edits together" {
	git review start feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	git review next                 # bank A, now on B (step 2)
	printf 'b1\nb2\nFIXB\n' >b.txt  # current step edits, not banked
	run git review preview
	[ "$status" -eq 0 ]
	[[ "$output" == *"+FIXA"* ]]    # banked edit on step 1
	[[ "$output" == *"+FIXB"* ]]    # uncommitted edit on the current step
}

@test "preview (step) does not bank the current step or move the position" {
	git review start feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	git review next                 # bank A, now on B (step 2)
	printf 'b1\nb2\nFIXB\n' >b.txt
	git review preview >/dev/null
	# still on step 2 with B's edit live in the working tree
	[ "$(git config branch.review/feature/x.reviewstep)" = "2" ]
	run git diff
	[[ "$output" == *"FIXB"* ]]
	# only A is banked — preview must not have banked the current step
	run git for-each-ref refs/review-edits/feature/x/
	[ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
}

# ── 3-way merge (context the PR shifted) ──────────────────────────────────────

@test "preview (step) merges a banked edit whose context the PR later changed" {
	# feature/merge: cg1 creates g.txt; cg2 changes a line within 3 lines of the
	# one we edit. A plain apply of our banked edit onto the tip fails (the hunk
	# context no longer matches), but a 3-way merge lands it — so preview must show
	# the edit, not omit it with a conflict note.
	git switch --quiet develop
	git switch --quiet -c feature/merge
	printf 'G1\nG2\nG3\nG4\nG5\nG6\nG7\n' >g.txt
	git add g.txt
	git commit --quiet -m cg1
	printf 'G1-PR\nG2\nG3\nG4\nG5\nG6\nG7\n' >g.txt
	git add g.txt
	git commit --quiet -m cg2-change-context
	git push --quiet -u origin feature/merge
	git switch --quiet develop

	git review start feature/merge --step            # step 1 (cg1, g.txt = G1..G7)
	printf 'G1\nG2\nG3\nG4-MINE\nG5\nG6\nG7\n' >g.txt
	git review next                               # bank step 1, now on step 2 (tip)

	run git review preview
	[ "$status" -eq 0 ]
	[[ "$output" == *"G4-MINE"* ]]                # 3-way merged onto the shifted tip
	[[ "$output" == *"G1-PR"* ]]                  # against the PR's tip content
	[[ "$output" != *"overlap the PR tip"* ]]     # and no conflict note
}

# ── overlapping edits (the conflict note) ─────────────────────────────────────

# Build feature/conflict: a PR where commit cf1 touches x.txt and a later commit
# cf3 changes the same region, so an edit banked on cf1 cannot replay onto the
# tip — while an edit on cf2 (a different file) can. Leaves the review on step 3
# with cf2's edit live and cf1's overlapping edit banked. Steps are:
#   1 cf-base  2 cf1-touch-x  3 cf2-touch-a  4 cf3-change-x
setup_conflict_pr() {
	git switch --quiet develop
	git switch --quiet -c feature/conflict
	printf 'X0\n' >x.txt
	printf 'A0\n' >cfa.txt
	git add x.txt cfa.txt
	git commit --quiet -m cf-base
	printf 'X0\nX1\n' >x.txt
	git add x.txt
	git commit --quiet -m cf1-touch-x
	printf 'A0\nA1\n' >cfa.txt
	git add cfa.txt
	git commit --quiet -m cf2-touch-a
	printf 'X0\nX1-CHANGED\n' >x.txt
	git add x.txt
	git commit --quiet -m cf3-change-x
	git push --quiet -u origin feature/conflict
	git switch --quiet develop

	git review start feature/conflict --step   # step 1 (cf-base)
	git review next                          # step 2 (cf1, x.txt = X0\nX1)
	printf 'X0\nX1-EDITED\n' >x.txt          # edit that will overlap the tip
	git review next                          # bank step 2, now step 3 (cf2)
	printf 'A0\nA1-EDITED\n' >cfa.txt        # edit that applies cleanly onto the tip
}

@test "preview (step) notes overlapping edits and still shows the rest" {
	setup_conflict_pr
	run git review preview
	[ "$status" -eq 0 ]
	# the clean edit is shown, the overlapping one is omitted, and the note fires
	[[ "$output" == *"A1-EDITED"* ]]
	[[ "$output" != *"X1-EDITED"* ]]
	[[ "$output" == *"overlap the PR tip"* ]]
}

@test "preview's overlap note matches what review finish actually hits" {
	# The note is only honest if review finish really conflicts in the same state.
	setup_conflict_pr
	git review preview >/dev/null 2>&1
	# preview left the state intact, so review finish runs from the same place
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"overlap the PR tip"* ]]
}

# ── no residue / idempotence ────────────────────────────────────────────────────

@test "preview leaves no temporary index files behind and is repeatable" {
	git review start feature/x develop
	printf 'a1\na2\nWHOLEFIX\n' >a.txt
	git review preview >/dev/null
	git review preview >/dev/null
	run sh -c 'ls "$(git rev-parse --git-dir)"/review preview-* 2>/dev/null'
	[ -z "$output" ]
}

# ── guards ──────────────────────────────────────────────────────────────────────

@test "preview (step) rejects a step past the last commit instead of exit 128" {
	git review start feature/x --step
	git config branch.review/feature/x.reviewstep 99
	run git review preview
	[ "$status" -ne 0 ]
	[[ "$output" == *"out of range (1..4)"* ]]
}

@test "preview (step) rejects step 0 and a non-numeric step" {
	git review start feature/x --step
	git config branch.review/feature/x.reviewstep 0
	run git review preview
	[ "$status" -ne 0 ]
	[[ "$output" == *"out of range (1..4)"* ]]

	git config branch.review/feature/x.reviewstep abc
	run git review preview
	[ "$status" -ne 0 ]
	[[ "$output" == *"not a positive integer"* ]]
}

@test "preview (step) accepts the last valid step (no off-by-one false positive)" {
	git review start feature/x --step
	# walk to the final step (4 of 4) the normal way; preview must still work
	git review next >/dev/null
	git review next >/dev/null
	git review next >/dev/null
	[ "$(git config branch.review/feature/x.reviewstep)" = "4" ]
	printf 'd\nFIXD\n' >d.txt
	run git review preview
	[ "$status" -eq 0 ]
	[[ "$output" == *"+FIXD"* ]]
	[[ "$output" != *"out of range"* ]]
}

@test "preview off a review branch fails" {
	run git review preview
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}

@test "preview refuses while review finish is mid-conflict" {
	setup_conflict_pr
	# drive review finish into its conflict state (markers in the tree, reviewresume set)
	run git review finish
	[ "$status" -ne 0 ]
	# previewing now would show conflict markers as content, so it must refuse
	run git review preview
	[ "$status" -ne 0 ]
	[[ "$output" == *"mid-conflict"* ]]
}

@test "preview (step) reports a deleted reviewcount key instead of dying silently" {
	# review preview reads step metadata with || true; a key removed by hand must be
	# reported, not let set -e kill the script with no message.
	git review start feature/x --step
	printf 'a1\na2\nX\n' >a.txt
	git config --unset branch.review/feature/x.reviewcount
	run git review preview
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
}
