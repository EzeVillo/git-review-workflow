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

# ── guard: --abort never silently discards finish-branch work ──────────────────
#
# A finish leaves your edits on review-fixes/<branch> (or, with --onto-source, the
# PR branch). If you change that branch afterwards, --abort must refuse rather than
# throw the work away, with --force as the explicit escape. The guard is
# mode-agnostic: review-fixes is produced the same way in whole and step.

@test "abort (whole) refuses when review-fixes was edited, --force discards it" {
	git review-pr feature/x develop
	printf 'a1\na2\nWHOLEFIX\n' >a.txt
	git finish-review
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	# refine the finish branch's working tree after the finish
	printf 'a1\na2\nWHOLEFIX\nREFINED\n' >a.txt

	# plain --abort is refused and changes NOTHING: still on review-fixes, the
	# refinement intact, the finish branch and undo record untouched
	run git finish-review --abort
	[ "$status" -ne 0 ]
	[[ "$output" == *"has changes since the finish"* ]]
	[[ "$output" == *"--force"* ]]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	run cat a.txt
	[[ "$output" == *"REFINED"* ]]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -eq 0 ]
	[ -n "$(git config branch.review/feature/x.reviewundohead || true)" ]

	# --force tears it down: back on the review, finish branch gone, undo cleared
	run git finish-review --abort --force
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -ne 0 ]
	[ -z "$(git config branch.review/feature/x.reviewundohead || true)" ]
	[ -z "$(git config branch.review/feature/x.reviewundoouthead || true)" ]
}

@test "abort (whole) refuses when review-fixes has a new commit, --force discards it" {
	git review-pr feature/x develop
	printf 'a1\na2\nWHOLEFIX\n' >a.txt
	git finish-review
	# commit the staged edits on the finish branch — real work that abort would
	# otherwise turn into a dangling commit
	git commit -q -m "my review commit"

	run git finish-review --abort
	[ "$status" -ne 0 ]
	[[ "$output" == *"has changes since the finish"* ]]
	# nothing lost: the commit is still on review-fixes
	[ "$(git log -1 --format=%s review-fixes/feature/x)" = "my review commit" ]

	run git finish-review --abort --force
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -ne 0 ]
}

@test "abort (whole) does not false-positive: an untouched finish aborts cleanly" {
	# No false positive: recording the exit state must not make a clean,
	# unmodified finish look diverged.
	git review-pr feature/x develop
	printf 'a1\na2\nWHOLEFIX\n' >a.txt
	git finish-review
	# do not touch the finish branch at all
	run git finish-review --abort
	[ "$status" -eq 0 ]
	[[ "$output" != *"has changes since the finish"* ]]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git diff
	[[ "$output" == *"WHOLEFIX"* ]]
}

@test "abort --force on an untouched finish still works (force is harmless)" {
	git review-pr feature/x develop
	printf 'a1\na2\nWHOLEFIX\n' >a.txt
	git finish-review
	run git finish-review --abort --force
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git diff
	[[ "$output" == *"WHOLEFIX"* ]]
}

@test "abort (step) refuses when review-fixes was edited, --force discards it" {
	# The guard is mode-agnostic — a step-mode finish produces review-fixes too.
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	git review-next
	printf 'b1\nb2\nFIXB\n' >b.txt
	git finish-review
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	printf 'a1\na2\nFIXA\nSTEP-REFINED\n' >a.txt

	run git finish-review --abort
	[ "$status" -ne 0 ]
	[[ "$output" == *"has changes since the finish"* ]]
	# refused: still on the finish branch with the refinement and the step's
	# banked edits intact
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	run git rev-parse --verify --quiet refs/review-edits/feature/x/1
	[ "$status" -eq 0 ]

	run git finish-review --abort --force
	[ "$status" -eq 0 ]
	# back on the review at step 2 with B's edit live, exactly as a clean abort
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	[ "$(git config branch.review/feature/x.reviewstep)" = "2" ]
	run git diff
	[[ "$output" == *"FIXB"* ]]
}

@test "abort (--onto-source) refuses when the PR branch was edited, --force discards it" {
	git review-pr feature/x develop
	printf 'a1\na2\nONTOFIX\n' >a.txt
	git finish-review --onto-source
	[ "$(git rev-parse --abbrev-ref HEAD)" = "feature/x" ]
	printf 'a1\na2\nONTOFIX\nONTO-REFINED\n' >a.txt

	run git finish-review --abort
	[ "$status" -ne 0 ]
	[[ "$output" == *"has changes since the finish"* ]]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "feature/x" ]
	run cat a.txt
	[[ "$output" == *"ONTO-REFINED"* ]]

	run git finish-review --abort --force
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git diff
	[[ "$output" == *"ONTOFIX"* ]]
	[[ "$output" != *"ONTO-REFINED"* ]]
}

@test "abort --force (--onto-source) discards a new commit on the PR branch, resetting it to the tip" {
	# The PR branch feature/x already existed, so finish staged onto it without
	# committing. A commit made on it afterwards is real work the guard protects;
	# --force must discard it and leave feature/x back at the reviewed tip, with no
	# dangling commit on the branch.
	git review-pr feature/x develop
	printf 'a1\na2\nONTOFIX\n' >a.txt
	git finish-review --onto-source
	[ "$(git rev-parse --abbrev-ref HEAD)" = "feature/x" ]
	tip="$(git rev-parse feature/x)"   # finish staged without committing: still at tip
	git commit -q -am "my onto-source commit"
	[ "$(git rev-parse feature/x)" != "$tip" ]

	# guard refuses and the commit survives untouched
	run git finish-review --abort
	[ "$status" -ne 0 ]
	[[ "$output" == *"has changes since the finish"* ]]
	[ "$(git log -1 --format=%s feature/x)" = "my onto-source commit" ]

	# --force discards it: back on the review, feature/x reset to the reviewed tip
	run git finish-review --abort --force
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	[ "$(git rev-parse feature/x)" = "$tip" ]
	[ "$(git log -1 --format=%s feature/x)" != "my onto-source commit" ]
}

@test "abort after a --resume finish refuses when review-fixes was edited, --force discards it" {
	# The guard applies to a finish completed through --resume just as to a direct
	# one: record_exit runs at the end of the resume too.
	setup_conflict_pr
	run git finish-review
	[ "$status" -ne 0 ]
	printf 'X0\nX1-RESOLVED\n' >x.txt
	git add x.txt
	run git finish-review --resume
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/conflict" ]
	# refine the finish branch after the resume completed
	printf 'X0\nX1-RESOLVED\nRESUME-REFINED\n' >x.txt

	run git finish-review --abort
	[ "$status" -ne 0 ]
	[[ "$output" == *"has changes since the finish"* ]]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/conflict" ]
	run cat x.txt
	[[ "$output" == *"RESUME-REFINED"* ]]

	run git finish-review --abort --force
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/conflict" ]
}

@test "abort from the review branch still catches a new commit on review-fixes" {
	# If you switch back to review/<branch> by hand before aborting, the working
	# tree is the review's, not the finish branch's — so the guard falls back to
	# the committed-divergence check, which still catches a commit on review-fixes.
	git review-pr feature/x develop
	printf 'a1\na2\nWHOLEFIX\n' >a.txt
	git finish-review
	git commit -q -m "my review commit"
	git switch -q review/feature/x
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]

	run git finish-review --abort
	[ "$status" -ne 0 ]
	[[ "$output" == *"has changes since the finish"* ]]
	# the commit on review-fixes is untouched
	[ "$(git log -1 --format=%s review-fixes/feature/x)" = "my review commit" ]

	run git finish-review --abort --force
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -ne 0 ]
}

@test "abort mid-conflict discards the resolution without --force, like rebase --abort" {
	# Mid-conflict there is no review-fixes yet, so the divergence guard does not
	# apply: resolving the markers and then aborting drops the resolution the way
	# git rebase --abort does — no refusal, no --force needed.
	setup_conflict_pr
	run git finish-review
	[ "$status" -ne 0 ]
	[[ "$output" == *"like git rebase --abort"* ]]
	# resolve the markers in the working tree
	printf 'X0\nX1-RESOLVED\n' >x.txt
	git add x.txt

	run git finish-review --abort
	[ "$status" -eq 0 ]
	[[ "$output" != *"has changes since the finish"* ]]
	# back on the review at step 3, the resolution gone, the clean edit live again
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/conflict" ]
	[ "$(git config branch.review/feature/conflict.reviewstep)" = "3" ]
	run cat x.txt
	[[ "$output" != *"X1-RESOLVED"* ]]
	run git diff
	[[ "$output" == *"A1-EDITED"* ]]
}

@test "finish warns that --abort will not discard edits without --force" {
	git review-pr feature/x develop
	printf 'a1\na2\nWHOLEFIX\n' >a.txt
	run git finish-review
	[ "$status" -eq 0 ]
	[[ "$output" == *"--abort"* ]]
	[[ "$output" == *"--force"* ]]
}

@test "step finish warns the same way" {
	git review-pr feature/x --step
	printf 'a1\na2\nFIXA\n' >a.txt
	run git finish-review
	[ "$status" -eq 0 ]
	[[ "$output" == *"--force"* ]]
}

@test "--force without --abort is rejected" {
	git review-pr feature/x develop
	run git finish-review --force
	[ "$status" -ne 0 ]
	[[ "$output" == *"only applies to --abort"* ]]
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

@test "--onto-source --resume with nothing in progress reports nothing to resume" {
	# --resume alongside --onto-source is a valid combo, but with no conflict in
	# progress there is nothing to pick up.
	git review-pr feature/x --step
	run git finish-review --onto-source --resume
	[ "$status" -ne 0 ]
	[[ "$output" == *"nothing to resume"* ]]
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

@test "abort fails clearly when the undo snapshot refs were deleted by hand" {
	# The undo snapshot (pre-finish index and working tree) lives only in
	# refs/review-undo/<branch>/. If those refs are removed while the config undo
	# record survives, abort cannot restore the review — it must say so plainly and
	# touch nothing, not die with an opaque "Needed a single revision" or mutate the
	# tree part-way through.
	git review-pr feature/x develop
	printf 'a1\na2\nWHOLEFIX\n' >a.txt
	git finish-review
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	# delete the snapshot refs by hand, leaving the config undo record behind
	for ref in $(git for-each-ref --format='%(refname)' refs/review-undo/feature/x/); do
		git update-ref -d "$ref"
	done
	[ -n "$(git config branch.review/feature/x.reviewundohead || true)" ]
	headbefore="$(git rev-parse HEAD)"

	run git finish-review --abort
	[ "$status" -ne 0 ]
	[[ "$output" == *"undo snapshot for review/feature/x is gone"* ]]
	[[ "$output" == *"git clean-review feature/x"* ]]
	# no opaque git plumbing error leaked through
	[[ "$output" != *"Needed a single revision"* ]]
	# nothing was mutated: still on the finish branch, HEAD and the edit untouched
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	[ "$(git rev-parse HEAD)" = "$headbefore" ]
	run cat a.txt
	[[ "$output" == *"WHOLEFIX"* ]]

	# the documented recovery path actually clears the stale record
	git switch --quiet --discard-changes develop
	git clean-review feature/x
	[ -z "$(git config branch.review/feature/x.reviewundohead || true)" ]
}
