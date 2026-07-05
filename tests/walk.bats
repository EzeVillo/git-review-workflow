#!/usr/bin/env bats
#
# Tests for walk mode: git review start auto-detecting a committed walkthrough,
# and git review next/prev/status/list/save/continue/finish/abort over it.
#
# The PR (feature/x) changes three files vs develop: a.txt and b.txt (edited),
# src/c.txt (added). The committed walkthrough orders them src/c.txt (1),
# a.txt (2), b.txt (3) — deliberately not the diff order, so the reading order is
# observable.

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"

	git config --global user.email t@example.com
	git config --global user.name tester
	git config --global init.defaultBranch develop
	git config --global core.autocrlf false

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
	mkdir -p src
	printf 'hello\n' >src/c.txt
	git add b.txt src/c.txt
	git commit --quiet -m c2-touch-b-add-c

	mkdir -p .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. src/c.txt
read the new helper first

## 2. a.txt
then the a change

## 3. b.txt
finally b
EOF
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough
	git push --quiet -u origin feature/x

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

# ── auto-detection at start ───────────────────────────────────────────────────

@test "start auto-detects the walkthrough and enters walk mode on entry 1" {
	run git review start feature/x
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	# The metadata records walk mode and the cursor, not step keys.
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "1" ]
	[ "$(git config branch.review/feature/x.reviewwalkcount)" = "3" ]
	run git config branch.review/feature/x.reviewstep
	[ "$status" -ne 0 ]
	# Entry 1 is the first in the author's order: src/c.txt, not the diff order.
	[[ "$(git review status)" == *"[1/3] on src/c.txt"* ]]
	# The full PR diff is staged and editable, exactly like a whole review.
	run git diff --cached --name-only
	[[ "$output" == *"a.txt"* ]]
	[[ "$output" == *"b.txt"* ]]
	[[ "$output" == *"src/c.txt"* ]]
}

@test "start prints the first entry with its path and why" {
	run git review start feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/3] src/c.txt"* ]]
	[[ "$output" == *"read the new helper first"* ]]
	# The header carries the bare path, no line suffix — clicking it just opens the
	# file. src/c.txt is added by the PR, which used to render as src/c.txt:1.
	[[ "$output" != *"src/c.txt:"* ]]
}

@test "--no-walk ignores the walkthrough and does a plain whole review" {
	run git review start feature/x --no-walk
	[ "$status" -eq 0 ]
	run git config branch.review/feature/x.reviewmode
	# whole mode records no reviewmode key at all.
	[ "$status" -ne 0 ]
	run git config branch.review/feature/x.reviewwalkstep
	[ "$status" -ne 0 ]
}

@test "--step takes precedence over the walkthrough" {
	run git review start feature/x --step
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "step" ]
	run git config branch.review/feature/x.reviewwalkstep
	[ "$status" -ne 0 ]
}

@test "--step notes that it is ignoring a present walkthrough" {
	run git review start feature/x --step
	[ "$status" -eq 0 ]
	[[ "$output" == *"has a walkthrough; --step ignores it"* ]]
}

@test "--step --no-walk does not note the walkthrough" {
	run git review start feature/x --step --no-walk
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "step" ]
	[[ "$output" != *"walkthrough"* ]]
}

# ── next / prev move only the cursor ──────────────────────────────────────────

@test "next advances the reading cursor without touching tree or index" {
	git review start feature/x >/dev/null
	idx_before="$(git diff --cached --name-only | sort)"
	wt_before="$(git status --porcelain)"
	run git review next
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "2" ]
	[[ "$output" == *"[2/3] a.txt"* ]]
	[[ "$output" == *"then the a change"* ]]
	# The staged diff and working tree are byte-identical before and after — the
	# cursor is a reading position, nothing more.
	[ "$(git diff --cached --name-only | sort)" = "$idx_before" ]
	[ "$(git status --porcelain)" = "$wt_before" ]
}

@test "prev moves the cursor back" {
	git review start feature/x >/dev/null
	git review next >/dev/null
	run git review prev
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "1" ]
	[[ "$output" == *"[1/3] src/c.txt"* ]]
}

@test "next at the last entry reports the end and does not move" {
	git review start feature/x >/dev/null
	git review next >/dev/null
	git review next >/dev/null
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "3" ]
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"no more entries"* ]]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "3" ]
}

@test "prev at the first entry reports it and does not move" {
	git review start feature/x >/dev/null
	run git review prev
	[ "$status" -eq 0 ]
	[[ "$output" == *"already at the first entry"* ]]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "1" ]
}

@test "edits survive moving the cursor back and forth" {
	git review start feature/x >/dev/null
	printf 'a1\na2\nFIX\n' >a.txt
	git review next >/dev/null
	git review prev >/dev/null
	# The edit made on a.txt is still there — walk never stashes or reverts it.
	run cat a.txt
	[[ "$output" == *"FIX"* ]]
}

@test "next after committing the staged diff reports HEAD moved off the base, not corrupt metadata" {
	git review start feature/x >/dev/null
	# Committing folds the whole-PR staged diff into HEAD, moving it off the base and
	# collapsing the HEAD..tip range the reading cursor is derived over.
	git commit --quiet -m "reviewer commits the staged diff"
	run git review next
	[ "$status" -eq 1 ]
	[[ "$output" == *"HEAD has moved off this review's base"* ]]
	[[ "$output" == *"git reset --soft"* ]]
	# Not the misleading diagnostic that blames the (intact) metadata.
	[[ "$output" != *"corrupt metadata"* ]]
	# status is the natural "what happened?" command and must diagnose it the same way.
	run git review status
	[ "$status" -eq 1 ]
	[[ "$output" == *"HEAD has moved off this review's base"* ]]
	# Recovery: a soft reset back to the base restages the whole diff and the cursor
	# works again, from where it was.
	git reset --soft HEAD^
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/3] on src/c.txt"* ]]
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/3] a.txt"* ]]
}

@test "a walkstep past the end with HEAD at the base still reports corrupt metadata" {
	git review start feature/x >/dev/null
	# HEAD unmoved: the range is intact (live total == walkcount), so a cursor past
	# the end is a hand-edited key — genuine corruption, not the HEAD-moved case.
	git config branch.review/feature/x.reviewwalkstep 99
	run git review next
	[ "$status" -eq 1 ]
	[[ "$output" == *"out of range (1..3)"* ]]
	[[ "$output" == *"corrupt metadata"* ]]
	[[ "$output" != *"HEAD has moved"* ]]
}

# ── range filtering ───────────────────────────────────────────────────────────

@test "--from filters the walkthrough to the reviewed subrange" {
	# Review only commits after c1: that range changes b.txt and src/c.txt (and the
	# walkthrough file), but not a.txt. So a.txt drops out and the sequence becomes
	# src/c.txt (1), b.txt (2).
	c1="$(git rev-parse feature/x~2)"
	run git review start feature/x --from "$c1"
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	[ "$(git config branch.review/feature/x.reviewwalkcount)" = "2" ]
	[[ "$output" == *"[1/2] src/c.txt"* ]]
	git review next >/dev/null
	run git review status
	[[ "$output" == *"[2/2] on b.txt"* ]]
}

# ── graceful degradation ──────────────────────────────────────────────────────

@test "a walkthrough whose entries do not intersect the range falls back to whole with a note" {
	# Set the delta marker with a full review, then push a commit touching a brand
	# new file the walkthrough does not mention.
	git review start feature/x >/dev/null
	git review finish >/dev/null
	git switch --quiet develop
	git branch -D review-fixes/feature/x >/dev/null 2>&1 || true
	git review clean feature/x >/dev/null 2>&1 || true

	git switch --quiet feature/x
	printf 'new\n' >e.txt
	git add e.txt
	git commit --quiet -m c3-add-e
	git push --quiet origin feature/x
	git switch --quiet develop

	run git review start feature/x --delta
	[ "$status" -eq 0 ]
	# Only e.txt is in the delta range; no walkthrough entry covers it, so it falls
	# back to a plain whole review with a note (no walk keys recorded).
	[[ "$output" == *"walkthrough"* ]]
	run git config branch.review/feature/x.reviewmode
	[ "$status" -ne 0 ]
}

@test "a malformed walkthrough falls back to a whole review with exit 0" {
	git switch --quiet develop
	git switch --quiet -c feature/broken
	printf 'd\n' >d.txt
	git add d.txt
	git commit --quiet -m d
	mkdir -p .review
	printf '# Walkthrough\n\nno entries at all here\n' >.review/walkthrough.md
	git add .review/walkthrough.md
	git commit --quiet -m brokenwt
	git push --quiet -u origin feature/broken
	git switch --quiet develop

	run git review start feature/broken
	[ "$status" -eq 0 ]
	[[ "$output" == *"walkthrough"* ]]
	run git config branch.review/feature/broken.reviewmode
	[ "$status" -ne 0 ]
}

@test "start notes range files not covered by the walkthrough but still walks" {
	# Push a commit adding e.txt without updating the walkthrough, then do a full
	# review: e.txt is in range but has no entry, so walk mode still starts (the
	# other files are covered) and prints a coverage note.
	git switch --quiet feature/x
	printf 'extra\n' >e.txt
	git add e.txt
	git commit --quiet -m c3-add-e-no-wt
	git push --quiet origin feature/x
	git switch --quiet develop

	run git review start feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	[[ "$output" == *"not in the walkthrough"* ]]
	[[ "$output" == *"e.txt"* ]]
}

# ── status / list ─────────────────────────────────────────────────────────────

@test "status shows the walk cursor as [k/N] on <path>" {
	git review start feature/x >/dev/null
	git review next >/dev/null
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk  [2/3] on a.txt"* ]]
}

@test "list shows the walk review with its [k/N] position" {
	git review start feature/x >/dev/null
	git review next >/dev/null
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk [2/3]"* ]]
	[[ "$output" == *"review/feature/x"* ]]
}

# ── save / continue ───────────────────────────────────────────────────────────

@test "save then continue restores walk mode on the exact same entry, with edits" {
	git review start feature/x >/dev/null
	git review next >/dev/null
	printf 'a1\na2\nWALKFIX\n' >a.txt
	run git review save
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
	run git rev-parse --verify --quiet refs/heads/review-saved/feature/x
	[ "$status" -eq 0 ]
	# The saved branch carries walk mode and the cursor.
	[ "$(git config branch.review-saved/feature/x.reviewmode)" = "walk" ]
	[ "$(git config branch.review-saved/feature/x.reviewwalkstep)" = "2" ]

	run git review continue
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "2" ]
	[[ "$output" == *"[2/3] a.txt"* ]]
	# The edit came back.
	run cat a.txt
	[[ "$output" == *"WALKFIX"* ]]
	# The saved branch is gone.
	run git rev-parse --verify --quiet refs/heads/review-saved/feature/x
	[ "$status" -ne 0 ]
}

# ── abort ─────────────────────────────────────────────────────────────────────

@test "abort deletes the walk branch and its cursor keys and rolls back the delta marker" {
	git review start feature/x >/dev/null
	# The marker was set to the reviewed tip by start.
	[ -n "$(git config reviewworkflow.feature/x.reviewed || true)" ]
	run git review abort
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
	# Cursor keys go with the branch section.
	run git config branch.review/feature/x.reviewwalkstep
	[ "$status" -ne 0 ]
	# A first-ever review that is aborted clears the marker (no prior review).
	run git config reviewworkflow.feature/x.reviewed
	[ "$status" -ne 0 ]
}

# ── finish (walk extracts exactly like whole) ─────────────────────────────────

@test "finish extracts walk edits exactly like a whole review" {
	git review start feature/x >/dev/null
	printf 'a1\na2\nFIXA\n' >a.txt
	printf 'hello\nFIXC\n' >src/c.txt
	run git review finish
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	run git diff --cached
	[[ "$output" == *"+FIXA"* ]]
	[[ "$output" == *"+FIXC"* ]]
	# The author's own lines are the tip's, not part of the extracted fix.
	[[ "$output" != *"+a2"* ]]
}

@test "finish rejects corrupt metadata: walk keys without reviewmode=walk" {
	git review start feature/x --no-walk >/dev/null
	# Inject a walk key onto a non-walk review.
	git config branch.review/feature/x.reviewwalkstep 1
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"walkthrough keys but reviewmode is not 'walk'"* ]]
	# The review branch is untouched.
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
}

# ── compare + walk ────────────────────────────────────────────────────────────

@test "compare enters walk mode from <b>'s tree and stays read-only" {
	run git review compare develop feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	[ "$(git config branch.review/feature/x.reviewreadonly)" = "1" ]
	[[ "$output" == *"[1/3] src/c.txt"* ]]
	# finish refuses on a read-only compare regardless of walk mode.
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"read-only compare review"* ]]
	# next still works (read-only), moving the cursor.
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/3] a.txt"* ]]
	# abort cleans it up.
	run git review abort
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "compare --no-walk reads the whole diff without a cursor" {
	run git review compare develop feature/x --no-walk
	[ "$status" -eq 0 ]
	run git config branch.review/feature/x.reviewmode
	[ "$status" -ne 0 ]
	[ "$(git config branch.review/feature/x.reviewreadonly)" = "1" ]
}
