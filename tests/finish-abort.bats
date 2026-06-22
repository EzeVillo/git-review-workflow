#!/usr/bin/env bats
#
# Tests for git finish-review --abort — undo the last finish and drop back onto
# review/<branch> exactly where editing left off, the way git merge --abort backs
# out a merge.
#
# Same fixture as preview.bats: feature/x has four commits on top of develop —
# A touches a.txt, B b.txt, C c.txt, D d.txt — which gives enough commits to bank
# edits across steps.

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

@test "abort (whole) returns to the review with edits live and the PR still staged" {
	git review-pr feature/x develop
	printf 'a1\na2\nWHOLEFIX\n' >a.txt
	git finish-review
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]

	run git finish-review --abort
	[ "$status" -eq 0 ]
	[[ "$output" == *"back on review/feature/x"* ]]
	# back on the review branch, edit live in the working tree, PR still staged
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git diff
	[[ "$output" == *"WHOLEFIX"* ]]
	run git diff --cached --name-only
	[[ "$output" == *"a.txt"* ]]
	# the branch finish created is gone, and the undo record is cleared
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -ne 0 ]
	[ -z "$(git config branch.review/feature/x.reviewundohead || true)" ]
}

@test "abort (whole) lets you keep editing and finish again" {
	git review-pr feature/x develop
	printf 'a1\na2\nWHOLEFIX\n' >a.txt
	git finish-review
	git finish-review --abort
	# refine the edit, then finish for real
	printf 'a1\na2\nWHOLEFIX2\n' >a.txt
	run git finish-review
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	run git diff --cached
	[[ "$output" == *"+WHOLEFIX2"* ]]
	[[ "$output" != *"+B"* ]]
}

@test "abort (whole) restores a brand-new untracked file edit" {
	git review-pr feature/x develop
	printf 'brand new\n' >newfile.txt
	git finish-review
	git finish-review --abort
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	# the file is back, untracked again as it was before finishing
	[ -f newfile.txt ]
	run git status --porcelain newfile.txt
	[[ "$output" == "?? newfile.txt" ]]
}

# ── step mode ─────────────────────────────────────────────────────────────────

@test "abort (step) returns to the step with edits live and banked edits intact" {
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	git review-next                 # bank A (step 1), now on B (step 2)
	printf 'b1\nb2\nFIXB\n' >b.txt  # current step edits, not banked
	git finish-review
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]

	run git finish-review --abort
	[ "$status" -eq 0 ]
	# back on the review branch, still on step 2, B's edit live in the tree
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	[ "$(git config branch.review/feature/x.reviewstep)" = "2" ]
	run git diff
	[[ "$output" == *"FIXB"* ]]
	# step 1 stays banked; the step finish banked (step 2) is rolled back to absent
	run git rev-parse --verify --quiet refs/review-edits/feature/x/1
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/review-edits/feature/x/2
	[ "$status" -ne 0 ]
}

@test "abort (step) keeps the step's commit staged and only the edit unstaged" {
	# No false positive: the per-step layout must come back exactly — the commit
	# under review staged, your edit on top unstaged — not collapsed together.
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	git review-next                 # now on B (step 2): b.txt gains "b2"
	printf 'b1\nb2\nFIXB\n' >b.txt
	git finish-review
	git finish-review --abort

	# the commit being reviewed (B adds b2) is staged, without the edit
	run git diff --cached
	[[ "$output" == *"+b2"* ]]
	[[ "$output" != *"FIXB"* ]]
	# the edit alone is unstaged
	run git diff
	[[ "$output" == *"+FIXB"* ]]
	[[ "$output" != *"+b2"* ]]
}

@test "abort (step) preserves navigation: review-prev still shows the earlier edit" {
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	git review-next                 # bank A (step 1), now on step 2
	printf 'b1\nb2\nFIXB\n' >b.txt
	git finish-review
	git finish-review --abort
	[ "$(git config branch.review/feature/x.reviewstep)" = "2" ]

	# walking back must restore step 1 with its edit, exactly as before finishing
	run git review-prev
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewstep)" = "1" ]
	run git diff
	[[ "$output" == *"FIXA"* ]]
}

@test "abort (step) restores edits made on a later step you had walked back from" {
	# Edit step 1, 2 and 3, walk back to step 2, finish from there, then abort.
	# Every step's edit must survive, forward and backward.
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	git review-next                 # bank 1, step 2
	printf 'b1\nb2\nFIXB\n' >b.txt
	git review-next                 # bank 2, step 3
	printf 'c\nFIXC\n' >c.txt
	git review-prev                 # bank 3, back to step 2 (FIXB restored)
	[ "$(git config branch.review/feature/x.reviewstep)" = "2" ]

	git finish-review               # finish from step 2
	git finish-review --abort

	# back on step 2 with its edit, and all three banked edits intact
	[ "$(git config branch.review/feature/x.reviewstep)" = "2" ]
	run git diff
	[[ "$output" == *"FIXB"* ]]
	for n in 1 2 3; do
		run git rev-parse --verify --quiet "refs/review-edits/feature/x/$n"
		[ "$status" -eq 0 ]
	done
	# walking forward to the step edited-then-left still shows that edit
	git review-next                 # step 3
	[ "$(git config branch.review/feature/x.reviewstep)" = "3" ]
	run git diff
	[[ "$output" == *"FIXC"* ]]
	# and walking back twice shows step 1's edit
	git review-prev                 # step 2
	run git review-prev             # step 1
	[ "$status" -eq 0 ]
	run git diff
	[[ "$output" == *"FIXA"* ]]
}

@test "abort (step) lets you keep navigating and finish for real afterwards" {
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	git review-next
	printf 'b1\nb2\nFIXB\n' >b.txt
	git finish-review
	git finish-review --abort
	# refine and complete the review
	printf 'b1\nb2\nFIXB2\n' >b.txt
	run git finish-review
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	run git diff --cached
	[[ "$output" == *"FIXA"* ]]
	[[ "$output" == *"FIXB2"* ]]
}

# ── step mode: the replay-conflict paths ──────────────────────────────────────

# feature/conflict: cf1 touches x.txt and a later cf3 changes the same region, so
# an edit banked on cf1 cannot replay onto the tip — finish leaves conflict
# markers. An edit on cf2 (a different file) replays cleanly. Leaves the review on
# step 3 with cf2's edit live and cf1's overlapping edit banked (ref 2).
#   steps: 1 cf-base  2 cf1-touch-x  3 cf2-touch-a  4 cf3-change-x
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

	git review-pr feature/conflict --step   # step 1 (cf-base)
	git review-next                          # step 2 (cf1, x.txt = X0\nX1)
	printf 'X0\nX1-EDITED\n' >x.txt          # edit that will overlap the tip
	git review-next                          # bank step 2, now step 3 (cf2)
	printf 'A0\nA1-EDITED\n' >cfa.txt        # edit that applies cleanly onto the tip
}

@test "abort bails out of a finish stopped mid-conflict, back to editing" {
	setup_conflict_pr
	run git finish-review            # conflicts on replay, leaves markers
	[ "$status" -ne 0 ]
	[ "$(git config branch.review/feature/conflict.reviewresume || true)" = "conflict" ]

	run git finish-review --abort
	[ "$status" -eq 0 ]
	# back on the review branch at step 3, the conflict cleared
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/conflict" ]
	[ "$(git config branch.review/feature/conflict.reviewstep)" = "3" ]
	[ -z "$(git config branch.review/feature/conflict.reviewresume || true)" ]
	run cat x.txt
	[[ "$output" != *"<<<<<<<"* ]]
	# the clean edit is live again and the overlapping edit is still banked
	run git diff
	[[ "$output" == *"A1-EDITED"* ]]
	run git rev-parse --verify --quiet refs/review-edits/feature/conflict/2
	[ "$status" -eq 0 ]
}

@test "abort undoes a finish that was completed via --resume" {
	setup_conflict_pr
	run git finish-review
	[ "$status" -ne 0 ]
	# resolve the conflict and complete the finish
	printf 'X0\nX1-RESOLVED\n' >x.txt
	git add x.txt
	run git finish-review --resume
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/conflict" ]

	# abort must still rewind to the pre-finish editing state
	run git finish-review --abort
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/conflict" ]
	[ "$(git config branch.review/feature/conflict.reviewstep)" = "3" ]
	run git diff
	[[ "$output" == *"A1-EDITED"* ]]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/conflict
	[ "$status" -ne 0 ]
}

# ── --onto-source ─────────────────────────────────────────────────────────────

@test "abort (--onto-source) returns to the review branch" {
	git review-pr feature/x develop
	printf 'a1\na2\nONTOFIX\n' >a.txt
	git finish-review --onto-source
	[ "$(git rev-parse --abbrev-ref HEAD)" = "feature/x" ]

	run git finish-review --abort
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git diff
	[[ "$output" == *"ONTOFIX"* ]]
}

# ── guards / cleanup ──────────────────────────────────────────────────────────

@test "abort with no prior finish fails" {
	git review-pr feature/x develop
	run git finish-review --abort
	[ "$status" -ne 0 ]
	[[ "$output" == *"no finish to abort"* ]]
}

@test "a second abort fails: there is no longer a finish to undo" {
	git review-pr feature/x develop
	printf 'a1\na2\nWHOLEFIX\n' >a.txt
	git finish-review
	git finish-review --abort
	# the undo record is consumed; aborting again has nothing to act on
	run git finish-review --abort
	[ "$status" -ne 0 ]
	[[ "$output" == *"no finish to abort"* ]]
}

@test "abort rejects being combined with other options" {
	run git finish-review --abort --resume
	[ "$status" -ne 0 ]
	[[ "$output" == *"takes no other options"* ]]
	run git finish-review --abort --onto-source
	[ "$status" -ne 0 ]
	[[ "$output" == *"takes no other options"* ]]
}

@test "clean-review removes a finish undo point left unaborted" {
	git review-pr feature/x develop
	printf 'a1\na2\nWHOLEFIX\n' >a.txt
	git finish-review
	# undo record is in place after a finish that was not aborted
	[ -n "$(git config branch.review/feature/x.reviewundohead || true)" ]
	git switch --quiet --discard-changes develop
	git clean-review feature/x
	[ -z "$(git config branch.review/feature/x.reviewundohead || true)" ]
	run git for-each-ref refs/review-undo/feature/x/
	[ -z "$output" ]
}
