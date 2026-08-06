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
	# 3 curated entries plus the committed walkthrough itself, uncovered: the
	# sidecar is content the PR adds like any other file (FR-020).
	[ "$(git config branch.review/feature/x.reviewwalkcount)" = "4" ]
	run git config branch.review/feature/x.reviewstep
	[ "$status" -ne 0 ]
	# Entry 1 is the first in the author's order: src/c.txt, not the diff order.
	[[ "$(git review status)" == *"[1/4] on src/c.txt"* ]]
	# The full PR diff is staged and editable, exactly like a whole review.
	run git diff --cached --name-only
	[[ "$output" == *"a.txt"* ]]
	[[ "$output" == *"b.txt"* ]]
	[[ "$output" == *"src/c.txt"* ]]
}

# ── the walkthrough itself joins the reading order (FR-020, US4) ──────────────

@test "the committed walkthrough itself is the last entry, uncovered, in --porcelain" {
	git review start feature/x >/dev/null
	run git review status --porcelain
	[ "$status" -eq 0 ]
	entries="$(printf '%s\n' "$output" | grep '^entry')"
	expected="$(printf 'entry\t1\tsrc/c.txt\t0\t1\nentry\t2\ta.txt\t0\t1\nentry\t3\tb.txt\t0\t1\nentry\t4\t.review/walkthrough.md\t0\t0')"
	[ "$entries" = "$expected" ]
}

@test "next walks all the way through the sidecar before reporting the end" {
	git review start feature/x >/dev/null
	git review next >/dev/null
	git review next >/dev/null
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[4/4] .review/walkthrough.md  (uncovered)"* ]]
	[[ "$output" == *"this file changes in the review and the walkthrough does not annotate it"* ]]
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"no more entries"* ]]
}

@test "a walk review opened before this feature (walkcount predates the sidecar entry) reaches it without error" {
	# FR-023: a review whose recorded walkcount does not count the sidecar (as
	# every walk review's did before this feature) must not report the extra
	# entry as a base-moved drift or any other error — the sequence simply grew.
	git review start feature/x >/dev/null
	git config branch.review/feature/x.reviewwalkcount 3

	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/4]"* ]]
	[[ "$output" != *"moved"* ]]
	[[ "$output" != *"corrupt"* ]]

	git review next >/dev/null
	git review next >/dev/null
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[4/4] .review/walkthrough.md  (uncovered)"* ]]
	[[ "$output" != *"moved"* ]]
	[[ "$output" != *"corrupt"* ]]
}

@test "a PR that only touches the sidecar degrades to whole but is never invisible there (FR-024)" {
	# No curated entry can ever intersect a range whose only file IS the
	# sidecar — a walkthrough never annotates itself — so this takes the same
	# "none of its entries apply" path as any other range a walkthrough does not
	# cover, exactly like the existing --delta degrade case. What changed is
	# what happens next: before US1, a degraded whole review showed nothing, so
	# this PR was entirely invisible. Now whole lists its one file, so the
	# degrade note and the whole listing agree, and nothing is hidden.
	git switch --quiet develop
	git switch --quiet -c feature/only-wt
	mkdir -p .review
	printf '# Walkthrough\n\nnothing to annotate yet\n' >.review/walkthrough.md
	git add .review/walkthrough.md
	git commit --quiet -m "add walkthrough only"
	git push --quiet -u origin feature/only-wt
	git switch --quiet develop

	run git review start feature/only-wt
	[ "$status" -eq 0 ]
	[[ "$output" == *"none of its entries apply to this review range; reviewing the whole diff: .review/walkthrough.md"* ]]
	run git config branch.review/feature/only-wt.reviewmode
	[ "$status" -ne 0 ]

	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"mode    whole"* ]]
	[[ "$output" == *"1  .review/walkthrough.md"* ]]
}

@test "start prints the first entry with its path and why" {
	run git review start feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/4] src/c.txt"* ]]
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
	[[ "$output" == *"[2/4] a.txt"* ]]
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
	[[ "$output" == *"[1/4] src/c.txt"* ]]
}

@test "next at the last entry reports the end and does not move" {
	git review start feature/x >/dev/null
	git review next >/dev/null
	git review next >/dev/null
	git review next >/dev/null
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "4" ]
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"no more entries"* ]]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "4" ]
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
	# FR-023: recoverable drift (HEAD moved off the review's base) is exit 3,
	# distinct from genuine corruption (exit 1) — see the next test.
	[ "$status" -eq 3 ]
	[[ "$output" == *"HEAD has moved off this review's base"* ]]
	[[ "$output" == *"git reset --soft"* ]]
	# Not the misleading diagnostic that blames the (intact) metadata.
	[[ "$output" != *"corrupt metadata"* ]]
	# status is the natural "what happened?" command and must diagnose it the same way.
	run git review status
	[ "$status" -eq 3 ]
	[[ "$output" == *"HEAD has moved off this review's base"* ]]
	# Recovery: a soft reset back to the base restages the whole diff and the cursor
	# works again, from where it was.
	git reset --soft HEAD^
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/4] on src/c.txt"* ]]
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/4] a.txt"* ]]
}

@test "a walkstep past the end with HEAD at the base still reports corrupt metadata" {
	git review start feature/x >/dev/null
	# HEAD unmoved: the range is intact (live total == walkcount), so a cursor past
	# the end is a hand-edited key — genuine corruption, not the HEAD-moved case.
	git config branch.review/feature/x.reviewwalkstep 99
	run git review next
	[ "$status" -eq 1 ]
	[[ "$output" == *"out of range (1..4)"* ]]
	[[ "$output" == *"corrupt metadata"* ]]
	[[ "$output" != *"HEAD has moved"* ]]
	[[ "$output" == *"git review abort"* ]]
}

# ── range filtering ───────────────────────────────────────────────────────────

@test "--from filters the walkthrough to the reviewed subrange" {
	# Review only commits after c1: that range changes b.txt and src/c.txt, but
	# not a.txt. So a.txt drops out and the curated sequence becomes src/c.txt
	# (1), b.txt (2) — plus the walkthrough file itself, which this subrange also
	# touches (the "rewt"-equivalent commit that adds .review/walkthrough.md is
	# c1's immediate successor here, so it is in range too), uncovered at (3).
	c1="$(git rev-parse feature/x~2)"
	run git review start feature/x --from "$c1"
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	[ "$(git config branch.review/feature/x.reviewwalkcount)" = "3" ]
	[[ "$output" == *"[1/3] src/c.txt"* ]]
	git review next >/dev/null
	run git review status
	[[ "$output" == *"[2/3] on b.txt"* ]]
	git review next >/dev/null
	run git review status
	[[ "$output" == *"[3/3] on .review/walkthrough.md  (uncovered)"* ]]
}

# ── heads-up and the key marker ───────────────────────────────────────────────

# Replace the committed walkthrough on feature/x with the content on stdin and
# push it, leaving the caller back on develop where setup left them.
recommit_walkthrough() {
	git switch --quiet feature/x
	cat >.review/walkthrough.md
	git add .review/walkthrough.md
	git commit --quiet -m rewt
	git push --quiet origin feature/x
	git switch --quiet develop
}

@test "start prints the author heads-up before the first entry" {
	recommit_walkthrough <<'EOF'
# Walkthrough

## Heads-up

session tokens now expire; anything caching them is suspect

## 1. src/c.txt
read the new helper first

## 2. a.txt
then the a change

## 3. b.txt
finally b
EOF
	run git review start feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"anything caching them is suspect"* ]]
	# It is read before the first file, so it must print above entry 1.
	hu="$(printf '%s\n' "$output" | grep -n 'anything caching them is suspect' | cut -d: -f1)"
	e1="$(printf '%s\n' "$output" | grep -n '^\[1/4\]' | cut -d: -f1)"
	[ -n "$hu" ]
	[ -n "$e1" ]
	[ "$hu" -lt "$e1" ]
}

@test "start prints no preamble block when the walkthrough has no heads-up" {
	run git review start feature/x
	[ "$status" -eq 0 ]
	[[ "$output" != *"Heads-up"* ]]
	[[ "$output" == *"[1/4] src/c.txt"* ]]
}

@test "start labels the key entries and counts them in the summary" {
	recommit_walkthrough <<'EOF'
# Walkthrough

## 1. src/c.txt
> key
read the new helper first

## 2. a.txt
then the a change

## 3. b.txt
> key
finally b
EOF
	run git review start feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"4 entries (2 key)"* ]]
	[[ "$output" == *"[1/4] src/c.txt  (key)"* ]]
	# The marker is a label, never prose: it must not leak into the why.
	[[ "$output" != *"> key"* ]]
	[[ "$output" == *"read the new helper first"* ]]
}

@test "status labels the current entry when it is marked key" {
	recommit_walkthrough <<'EOF'
# Walkthrough

## 1. src/c.txt
> key
read the new helper first

## 2. a.txt
then the a change

## 3. b.txt
finally b
EOF
	git review start feature/x >/dev/null
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/4] on src/c.txt  (key)"* ]]
	git review next >/dev/null
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/4] on a.txt"* ]]
	[[ "$output" != *"(key)"* ]]
}

@test "next labels a key entry and leaves an unmarked one plain" {
	recommit_walkthrough <<'EOF'
# Walkthrough

## 1. src/c.txt
read the new helper first

## 2. a.txt
> key
then the a change

## 3. b.txt
finally b
EOF
	run git review start feature/x
	[ "$status" -eq 0 ]
	# Entry 1 is unmarked: no label at all.
	[[ "$output" == *"[1/4] src/c.txt"* ]]
	[[ "$output" != *"(key)"* ]]
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/4] a.txt  (key)"* ]]
	[[ "$output" == *"then the a change"* ]]
	[[ "$output" != *"> key"* ]]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "2" ]
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[3/4] b.txt"* ]]
	[[ "$output" != *"(key)"* ]]
}

# ── CRLF line endings ─────────────────────────────────────────────────────────

# Print the walkthrough blob committed on feature/x, byte for byte.
#
# The branch is resolved to a SHA first, on purpose. Under Git Bash on Windows,
# MSYS rewrites any argument that looks like a POSIX path list before git.exe
# sees it, and "feature/x:.review/walkthrough.md" looks exactly like one: two
# slash-bearing components around a colon. git.exe gets
# "feature\x;.review\walkthrough.md" and dies with "ambiguous argument". A SHA
# has no slash before the colon, so the heuristic leaves the argument alone.
# The commands themselves are safe: they resolve the rev with rev-parse before
# building the "<rev>:<path>" argument, so a SHA is all git ever gets there.
wt_blob() {
	git show "$(git rev-parse feature/x):.review/walkthrough.md"
}

# Commit the walkthrough on stdin to feature/x with CRLF endings — what a Windows
# author with core.autocrlf on pushes — and prove the committed blob really carries
# the CRs. The proof deliberately avoids awk: the gawk that ships with Git for
# Windows reads in text mode and eats the CR, which is exactly why this bug is
# invisible there. wc -c counts bytes and is honest on every platform. So on
# Windows these assertions hold even without the strip; their teeth are on Linux
# and macOS, where the CR reaches the parsers and used to kill walk mode outright.
recommit_walkthrough_crlf() {
	git switch --quiet feature/x
	cat >"$TMP/wt.lf"
	while IFS= read -r line; do printf '%s\r\n' "$line"; done \
		<"$TMP/wt.lf" >.review/walkthrough.md
	git add .review/walkthrough.md
	git commit --quiet -m rewt-crlf
	git push --quiet origin feature/x
	git switch --quiet develop

	lf_bytes=$(($(wc -c <"$TMP/wt.lf")))
	lf_lines=$(($(wc -l <"$TMP/wt.lf")))
	blob_bytes=$(($(wt_blob | wc -c)))
	[ "$lf_lines" -gt 0 ]
	[ "$blob_bytes" -eq "$((lf_bytes + lf_lines))" ]
}

@test "a walkthrough committed with CRLF still drives walk mode" {
	recommit_walkthrough_crlf <<'EOF'
# Walkthrough

## Heads-up

session tokens now expire; anything caching them is suspect

## 1. src/c.txt
> key
read the new helper first

## 2. a.txt
then the a change

## 3. b.txt
finally b
EOF
	run git review start feature/x
	[ "$status" -eq 0 ]
	# The CR used to make every path differ from git's, so no entry intersected the
	# range: start degraded to a plain whole review with a note.
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	[ "$(git config branch.review/feature/x.reviewwalkcount)" = "4" ]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "1" ]
	[[ "$output" != *"none of its entries apply"* ]]
	# Author order, key marker and heads-up all survive the round trip.
	[[ "$output" == *"4 entries (1 key)"* ]]
	[[ "$output" == *"[1/4] src/c.txt  (key)"* ]]
	[[ "$output" == *"read the new helper first"* ]]
	[[ "$output" == *"anything caching them is suspect"* ]]
	[[ "$output" != *"> key"* ]]
	# Nothing printed may carry a stray CR: stripping only the parsed paths would
	# still leak one into the why prose and the heads-up.
	[[ "$output" != *$'\r'* ]]

	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/4] a.txt"* ]]
	[[ "$output" == *"then the a change"* ]]
	[[ "$output" != *"(key)"* ]]
	[[ "$output" != *$'\r'* ]]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "2" ]

	# status reads the same cursor and the same walkthrough.
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/4] on a.txt"* ]]
	[[ "$output" != *$'\r'* ]]
}

@test "a CRLF walkthrough that really drifts still degrades to a whole review" {
	# The strip must not invent entries: a walkthrough whose paths do not exist in
	# the range degrades with a note, CRLF or not.
	recommit_walkthrough_crlf <<'EOF'
# Walkthrough

## 1. nope/one.txt
not in this PR

## 2. nope/two.txt
neither is this
EOF
	run git review start feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"walkthrough"* ]]
	run git config branch.review/feature/x.reviewmode
	[ "$status" -ne 0 ]
	run git config branch.review/feature/x.reviewwalkstep
	[ "$status" -ne 0 ]
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

@test "start notes range files not covered by the walkthrough, appends them to the reading order" {
	# Push a commit adding e.txt without updating the walkthrough: e.txt is in
	# range but has no entry, so walk mode still starts (the other files are
	# covered) and the note says where it went — the end of the reading order,
	# not a separate list.
	git switch --quiet feature/x
	printf 'extra\n' >e.txt
	git add e.txt
	git commit --quiet -m c3-add-e-no-wt
	git push --quiet origin feature/x
	git switch --quiet develop

	run git review start feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	# 3 curated entries plus two uncovered ones, appended at the end in git's own
	# order: the committed walkthrough itself (".review/" sorts before "e") and
	# e.txt.
	[ "$(git config branch.review/feature/x.reviewwalkcount)" = "5" ]
	[[ "$output" == *"not in the walkthrough are added to the end of the reading order: .review/walkthrough.md e.txt"* ]]
	[[ "$output" == *"walkthrough: 5 entries"* ]]
}

@test "an unannotated entry sits at the end of the reading order, marked uncovered, with no why" {
	git switch --quiet feature/x
	printf 'extra\n' >e.txt
	git add e.txt
	git commit --quiet -m c3-add-e-no-wt
	git push --quiet origin feature/x
	git switch --quiet develop

	git review start feature/x >/dev/null
	git review next >/dev/null
	git review next >/dev/null
	# Position 4 is the committed walkthrough itself, uncovered — it sorts before
	# e.txt in git's own order.
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[4/5] .review/walkthrough.md  (uncovered)"* ]]
	[[ "$output" == *"this file changes in the review and the walkthrough does not annotate it"* ]]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "4" ]

	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[5/5] e.txt  (uncovered)"* ]]
	[[ "$output" == *"this file changes in the review and the walkthrough does not annotate it"* ]]
	[[ "$output" != *"(key)"* ]]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "5" ]

	# Only past the last appended entry does the sequence actually end.
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"no more entries"* ]]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "5" ]
}

@test "status marks an unannotated entry as uncovered and counts it in the total" {
	git switch --quiet feature/x
	printf 'extra\n' >e.txt
	git add e.txt
	git commit --quiet -m c3-add-e-no-wt
	git push --quiet origin feature/x
	git switch --quiet develop

	git review start feature/x >/dev/null
	git review next >/dev/null
	git review next >/dev/null
	git review next >/dev/null
	git review next >/dev/null
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk  [5/5] on e.txt  (uncovered)"* ]]
}

@test "a key entry stays marked key even when the review also has unannotated entries" {
	recommit_walkthrough <<'EOF'
# Walkthrough

## 1. src/c.txt
> key
read the new helper first

## 2. a.txt
then the a change

## 3. b.txt
finally b
EOF
	git switch --quiet feature/x
	printf 'extra\n' >e.txt
	git add e.txt
	git commit --quiet -m c3-add-e-no-wt
	git push --quiet origin feature/x
	git switch --quiet develop

	run git review start feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"5 entries (1 key)"* ]]
	[[ "$output" == *"[1/5] src/c.txt  (key)"* ]]
}

@test "a walk review whose recorded walkcount predates unannotated entries still reaches all of them" {
	# Simulates a review opened before unannotated files joined the reading
	# order: reviewwalkcount is stale (lower than what the sequence now
	# derives), but next/status must still walk the whole thing without a
	# config migration — the denominator is always the derived total.
	git switch --quiet feature/x
	printf 'extra\n' >e.txt
	git add e.txt
	git commit --quiet -m c3-add-e-no-wt
	git push --quiet origin feature/x
	git switch --quiet develop

	git review start feature/x >/dev/null
	git config branch.review/feature/x.reviewwalkcount 3

	git review next >/dev/null
	git review next >/dev/null
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[4/5] .review/walkthrough.md  (uncovered)"* ]]

	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[5/5] e.txt  (uncovered)"* ]]

	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"no more entries"* ]]

	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk  [5/5] on e.txt  (uncovered)"* ]]
}

# ── status / list ─────────────────────────────────────────────────────────────

@test "status shows the walk cursor as [k/N] on <path>" {
	git review start feature/x >/dev/null
	git review next >/dev/null
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk  [2/4] on a.txt"* ]]
}

@test "list shows the walk review with its [k/N] position" {
	git review start feature/x >/dev/null
	git review next >/dev/null
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk [2/4]"* ]]
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
	[[ "$output" == *"[2/4] a.txt"* ]]
	# The edit came back.
	run cat a.txt
	[[ "$output" == *"WALKFIX"* ]]
	# The saved branch is gone.
	run git rev-parse --verify --quiet refs/heads/review-saved/feature/x
	[ "$status" -ne 0 ]
}

@test "continue reprints [k/N] against the derived total, including an unannotated entry" {
	git switch --quiet feature/x
	printf 'extra\n' >e.txt
	git add e.txt
	git commit --quiet -m c3-add-e-no-wt
	git push --quiet origin feature/x
	git switch --quiet develop

	git review start feature/x >/dev/null
	git review next >/dev/null
	git review next >/dev/null
	git review next >/dev/null
	git review next >/dev/null
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "5" ]
	run git review save
	[ "$status" -eq 0 ]

	run git review continue
	[ "$status" -eq 0 ]
	[[ "$output" == *"[5/5] e.txt"* ]]
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

@test "finish with no edits lands on empty review-fixes and abort restores walk" {
	# Mid-cursor shape (same as the sandbox's saved feature/search): finish
	# without reviewer edits must still close the session — empty review-fixes
	# at the tip — not strand you on review/* (panel still offering Next/Finish)
	# or leave HEAD off the base so status dies with "HEAD has moved off".
	git review start feature/x >/dev/null
	git review next >/dev/null
	base="$(git rev-parse HEAD)"
	tip="$(git rev-parse feature/x)"
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "2" ]

	run git review finish
	[ "$status" -eq 0 ]
	[[ "$output" == *"no review changes"* ]]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	[ "$(git rev-parse HEAD)" = "$tip" ]
	run git diff --cached --quiet
	[ "$status" -eq 0 ]
	# Not on review/*: status is "no active review here", not a walk range error.
	run git review status --porcelain
	[ "$status" -eq 2 ]

	run git review finish --abort
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	[ "$(git rev-parse HEAD)" = "$base" ]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "2" ]

	run git review status --porcelain
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -q $'^state\treview/feature/x\tfeature/x\t.*\twalk\t'

	run git review next
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "3" ]
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
	[[ "$output" == *"[1/4] src/c.txt"* ]]
	# finish refuses on a read-only compare regardless of walk mode.
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"read-only compare review"* ]]
	# next still works (read-only), moving the cursor.
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/4] a.txt"* ]]
	# abort cleans it up.
	run git review abort
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "compare degrades with a note naming the sidecar when only it changed in range (T015)" {
	# The commit right before "walkthrough" only added the sidecar; comparing up
	# to it leaves none of the walkthrough's own entries (src/c.txt, a.txt,
	# b.txt) in range, so this takes the degrade path — and the note must name
	# the sidecar, exactly like start's equivalent case.
	c2="$(git rev-parse feature/x~1)"
	run git review compare "$c2" feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"none of its entries apply to $c2..feature/x; reading the whole diff: .review/walkthrough.md"* ]]
	run git config branch.review/feature/x.reviewmode
	[ "$status" -ne 0 ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"1  .review/walkthrough.md"* ]]
	git review abort >/dev/null
}

@test "compare --no-walk reads the whole diff without a cursor" {
	run git review compare develop feature/x --no-walk
	[ "$status" -eq 0 ]
	run git config branch.review/feature/x.reviewmode
	[ "$status" -ne 0 ]
	[ "$(git config branch.review/feature/x.reviewreadonly)" = "1" ]
}

# ── non-ASCII paths, BOM and stray whitespace ─────────────────────────────────
#
# Three ways a path written in the walkthrough can stop being byte-equal to the
# path git reports for the same file. Each one used to drop the entry out of the
# derived sequence in silence: the reviewer got a shorter walk, or no walk at all,
# and the only hint was a note listing the file as "not in the walkthrough".

# Commit the walkthrough on stdin to feature/x verbatim, push it, and leave the
# checkout back on develop the way setup left it.
recommit_walkthrough() {
	git switch --quiet feature/x
	cat >.review/walkthrough.md
	git add .review/walkthrough.md
	git commit --quiet -m rewt
	git push --quiet origin feature/x
	git switch --quiet develop
}

# Add a non-ASCII path to the PR, then prove the hazard is live on this platform:
# under git's default core.quotePath that path is reported escaped and quoted, so
# it could never equal the literal one an author writes. A platform that did not
# round-trip the name has nothing to exercise and skips. The name is built from
# octal escapes so this file stays pure ASCII, and its character has no canonical
# decomposition, so macOS filesystem normalisation cannot make the test flaky; an
# accented name behaves identically.
add_nonascii_to_pr() {
	git switch --quiet feature/x
	NONASCII="src/$(printf '\346\226\207\346\233\270').txt"
	printf 'u\n' >"$NONASCII"
	git add "$NONASCII"
	git commit --quiet -m c3-add-nonascii
	git push --quiet origin feature/x
	git switch --quiet develop
	quoted="$(git -c core.quotePath=true diff --name-only develop feature/x | grep -c '^"' || true)"
	[ "$quoted" -eq 1 ] || skip "this platform does not round-trip a non-ASCII path"
}

@test "a walkthrough entry for a non-ASCII path stays on the reading path" {
	add_nonascii_to_pr
	recommit_walkthrough <<EOF
# Walkthrough

## 1. $NONASCII
> key
read the unicode helper first

## 2. src/c.txt
read the new helper first

## 3. a.txt
then the a change

## 4. b.txt
finally b
EOF
	run git review start feature/x
	[ "$status" -eq 0 ]
	# The escaped path never matched the literal one, so this entry was filtered
	# out of the sequence: a 4-entry walk with the key file silently off the path
	# (plus the committed walkthrough itself, uncovered, at the very end).
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	[ "$(git config branch.review/feature/x.reviewwalkcount)" = "5" ]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "1" ]
	[[ "$output" == *"5 entries (1 key)"* ]]
	[[ "$output" == *"[1/5] $NONASCII  (key)"* ]]
	[[ "$output" == *"read the unicode helper first"* ]]
	# It is on the path, so it is not reported as uncovered — only the sidecar
	# is (it always is, having no entry of its own), and nothing printed carries
	# git's C-escaping.
	[[ "$output" == *"not in the walkthrough are added to the end of the reading order: .review/walkthrough.md"* ]]
	[[ "$output" != *'\'* ]]

	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/5] src/c.txt"* ]]
	[[ "$output" != *"(key)"* ]]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "2" ]

	run git review prev
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/5] $NONASCII  (key)"* ]]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "1" ]

	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/5] on $NONASCII"* ]]
}

@test "a non-ASCII file left out of the walkthrough is named readably and walked as uncovered" {
	# The complement of the test above: the note must still fire, must name the
	# file the way the author would have to type it into the walkthrough, and the
	# file itself must still be reachable — at the end of the reading order.
	add_nonascii_to_pr
	run git review start feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	# 3 curated entries plus two uncovered ones, in git's own order: the
	# committed walkthrough itself (".review/" sorts before "src/") and the
	# non-ASCII file.
	[ "$(git config branch.review/feature/x.reviewwalkcount)" = "5" ]
	[[ "$output" == *"not in the walkthrough are added to the end of the reading order: .review/walkthrough.md $NONASCII"* ]]
	[[ "$output" != *'\'* ]]

	git review next >/dev/null
	git review next >/dev/null
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[4/5] .review/walkthrough.md  (uncovered)"* ]]
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[5/5] $NONASCII  (uncovered)"* ]]
	[[ "$output" != *'\'* ]]
}

# Commit the walkthrough on stdin behind a UTF-8 BOM — what a Windows author's
# editor writes on its own — and prove the committed blob really carries it: three
# bytes more than the source, and those three are the BOM. The proof avoids awk on
# purpose, the same way the CRLF one does.
recommit_walkthrough_bom() {
	cat >"$TMP/wt.lf"
	{ printf '\357\273\277'; cat "$TMP/wt.lf"; } >"$TMP/wt.bom"
	recommit_walkthrough <"$TMP/wt.bom"

	lf_bytes=$(($(wc -c <"$TMP/wt.lf")))
	blob_bytes=$(($(wt_blob | wc -c)))
	[ "$lf_bytes" -gt 0 ]
	[ "$blob_bytes" -eq "$((lf_bytes + 3))" ]
	[ "$(wt_blob | head -c 3)" = "$(printf '\357\273\277')" ]
}

@test "a walkthrough committed with a UTF-8 BOM still drives walk mode" {
	recommit_walkthrough_bom <<'EOF'
# Walkthrough

## Heads-up

session tokens now expire; anything caching them is suspect

## 1. src/c.txt
> key
read the new helper first

## 2. a.txt
then the a change

## 3. b.txt
finally b
EOF
	run git review start feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	[ "$(git config branch.review/feature/x.reviewwalkcount)" = "4" ]
	[[ "$output" == *"4 entries (1 key)"* ]]
	[[ "$output" == *"[1/4] src/c.txt  (key)"* ]]
	# The BOM used to hide the "# Walkthrough" heading from the preamble reader,
	# which then printed the heading back at the reviewer as the heads-up.
	[[ "$output" == *"anything caching them is suspect"* ]]
	[[ "$output" != *"# Walkthrough"* ]]
	# The BOM itself must not reach the terminal on the first line of anything.
	[[ "$output" != *"$(printf '\357\273\277')"* ]]
}

@test "a BOM on a walkthrough that opens with an entry does not hide that entry" {
	recommit_walkthrough_bom <<'EOF'
## 1. src/c.txt
read the new helper first

## 2. a.txt
then the a change

## 3. b.txt
finally b
EOF
	run git review start feature/x
	[ "$status" -eq 0 ]
	# Without the strip the first entry was unparseable, so the walk was one short
	# and src/c.txt came back as an uncovered file instead.
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	[ "$(git config branch.review/feature/x.reviewwalkcount)" = "4" ]
	[[ "$output" == *"[1/4] src/c.txt"* ]]
	# Only the sidecar is uncovered — src/c.txt is not named in that note.
	[[ "$output" == *"not in the walkthrough are added to the end of the reading order: .review/walkthrough.md"* ]]
}

@test "trailing whitespace on an entry heading does not drop it from the walk" {
	# One space after src/c.txt and one tab after a.txt, written with printf so no
	# editor or formatter can quietly clean them up. Both are invisible on screen
	# and both used to make the entry compare unequal to git's path.
	{
		printf '# Walkthrough\n\n'
		printf '## 1. src/c.txt \n> key\nread the new helper first\n\n'
		printf '## 2. a.txt\t\nthen the a change\n\n'
		printf '## 3. b.txt\nfinally b\n'
	} | recommit_walkthrough
	run git review start feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	[ "$(git config branch.review/feature/x.reviewwalkcount)" = "4" ]
	[[ "$output" == *"4 entries (1 key)"* ]]
	# The path is shown trimmed, so it stays clickable in an IDE terminal, and the
	# body still resolves (it is looked up by the very path that was untrimmed).
	[[ "$output" == *"[1/4] src/c.txt  (key)"* ]]
	[[ "$output" == *"read the new helper first"* ]]
	# Only the sidecar is uncovered — src/c.txt is not named in that note.
	[[ "$output" == *"not in the walkthrough are added to the end of the reading order: .review/walkthrough.md"* ]]

	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/4] a.txt"* ]]
	[[ "$output" == *"then the a change"* ]]
	[[ "$output" != *"(key)"* ]]
}

@test "a walkthrough whose only entries carry stray whitespace still degrades on real drift" {
	# The trim must not invent entries: paths that are not in the range stay out of
	# the walk, trailing whitespace or not.
	{
		printf '# Walkthrough\n\n'
		printf '## 1. nope/one.txt \nnot in this PR\n\n'
		printf '## 2. nope/two.txt\t\nneither is this\n'
	} | recommit_walkthrough
	run git review start feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"none of its entries apply to this review range"* ]]
	run git config branch.review/feature/x.reviewmode
	[ "$status" -ne 0 ]
	run git config branch.review/feature/x.reviewwalkstep
	[ "$status" -ne 0 ]
}
