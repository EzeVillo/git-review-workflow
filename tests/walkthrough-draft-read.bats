#!/usr/bin/env bats
#
# How a reviewer's draft is read: precedence over the author's committed
# walkthrough, and the guarantee that every surface of one review reads the same
# one. The failure this file exists to catch is silent — status --why showing the
# author's prose while next walks the reviewer's order, because some verb forgot
# to set the draft context.
#
# feature/x changes three files and carries a committed walkthrough of its own,
# so precedence is observable: the two orders are deliberately different.

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
	printf 'b1\nb2\n' >b.txt
	mkdir -p src .review
	printf 'hello\n' >src/c.txt
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. a.txt
AUTHOR says read a first

## 2. b.txt
AUTHOR on b

## 3. src/c.txt
AUTHOR on c
EOF
	git add -A
	git commit --quiet -m work
	git push --quiet -u origin feature/x

	git switch --quiet develop
	DRAFT="$(git rev-parse --git-dir)/review-walkthrough/feature/x.md"
}

teardown() {
	rm -rf "$TMP"
}

# A draft whose order is the exact reverse of the author's, so which one is in
# force can be read off entry 1 alone. The sidecar is part of the range too (the
# PR adds it), so it needs an entry or the drift check would reject the draft.
write_draft() {
	mkdir -p "$(dirname "$DRAFT")"
	cat >"$DRAFT" <<'EOF'
# Walkthrough

## 1. src/c.txt
REVIEWER says start at c

## 2. b.txt
REVIEWER on b

## 3. a.txt
REVIEWER on a

## 4. .review/walkthrough.md
REVIEWER on the author's own file
EOF
}

# ── precedence ────────────────────────────────────────────────────────────────

@test "with no draft the review reads the author's walkthrough" {
	run git review start feature/x
	[ "$status" -eq 0 ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"on a.txt"* ]]
	[[ "$output" != *"(draft)"* ]]
}

@test "a draft takes precedence over the author's walkthrough" {
	write_draft
	run git review start feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	run git review status
	[ "$status" -eq 0 ]
	# Entry 1 is the reviewer's, not the author's.
	[[ "$output" == *"on src/c.txt"* ]]
	[[ "$output" == *"(draft)"* ]]
}

@test "a draft is readable without ever running --build" {
	write_draft
	run git review start feature/x
	[ "$status" -eq 0 ]
	# Never validated, never renumbered: the order is the one that was typed.
	run git review status --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *"src/c.txt"* ]]
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"b.txt"* ]]
}

@test "every surface of one review reads the same walkthrough" {
	write_draft
	git review start feature/x

	# status: the cursor
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"on src/c.txt"* ]]

	# status --why: the prose for the entry under the cursor
	run git review status --why src/c.txt
	[ "$status" -eq 0 ]
	[[ "$output" == *"REVIEWER says start at c"* ]]
	[[ "$output" != *"AUTHOR"* ]]

	# next: the sequence
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"b.txt"* ]]
	run git review status --why b.txt
	[ "$status" -eq 0 ]
	[[ "$output" == *"REVIEWER on b"* ]]

	# prev: back the same way
	run git review prev
	[ "$status" -eq 0 ]
	[[ "$output" == *"src/c.txt"* ]]

	# list: the inventory row
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk (draft)"* ]]
}

@test "deleting the draft hands the review back to the author's order" {
	write_draft
	git review start feature/x
	run git review status
	[[ "$output" == *"on src/c.txt"* ]]
	# The cursor is re-derived on every verb, so removing the draft is enough.
	rm "$DRAFT"
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"on a.txt"* ]]
	[[ "$output" != *"(draft)"* ]]
}

@test "the draft is normalised like any walkthrough: CRLF and a BOM" {
	write_draft
	# What an editor on Windows leaves behind. Without normalisation the CR rides
	# on every path and no entry matches git's, so the whole order silently
	# collapses to the uncovered tail.
	printf '\357\273\277' >"$DRAFT.bom"
	sed 's/$/\r/' "$DRAFT" >>"$DRAFT.bom"
	mv "$DRAFT.bom" "$DRAFT"
	run git review start feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"4 entries"* ]]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"on src/c.txt"* ]]
}

# ── degradation ───────────────────────────────────────────────────────────────

@test "a draft whose entries are all out of range degrades to whole with a note" {
	mkdir -p "$(dirname "$DRAFT")"
	cat >"$DRAFT" <<'EOF'
# Walkthrough

## 1. nothing/here.txt
stale entry for a file this PR does not touch
EOF
	run git review start feature/x
	[ "$status" -eq 0 ]
	# Degraded, not aborted: the review still happened.
	[[ "$output" == *"reviewing the whole diff"* ]]
	[ "$(git config branch.review/feature/x.reviewmode || echo whole)" = "whole" ]
}

@test "a corrupt draft never aborts the review" {
	mkdir -p "$(dirname "$DRAFT")"
	printf 'not a walkthrough at all\n\x01\x02\n' >"$DRAFT"
	run git review start feature/x
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	# Degraded to whole with a note, exactly like a stale one — never a walk with
	# a cursor over nothing, and never the author's order behind the reviewer's
	# back. The mode key is absent in whole mode, hence the default.
	[[ "$output" == *"reviewing the whole diff"* ]]
	[ "$(git config branch.review/feature/x.reviewmode || echo whole)" = "whole" ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"mode    whole"* ]]
	# No cursor to move, and nothing claiming to be a reading order.
	run git review next
	[ "$status" -ne 0 ]
	[[ "$output" != *"(draft)"* ]]
}

@test "deleting the draft names the real cause even when the PR has a walkthrough" {
	# The draft marks two entries key; the author's walkthrough marks none. Start
	# --keys, then delete the draft: the review falls back to the author's order,
	# where nothing is key, and the keys-only sequence empties.
	#
	# walk_read still succeeds here — the sidecar answers — so a diagnostic keyed
	# on "there is no walkthrough left" blamed HEAD instead, telling the reviewer
	# to run git reset --soft over a HEAD that never moved.
	mkdir -p "$(dirname "$DRAFT")"
	cat >"$DRAFT" <<'EOF'
# Walkthrough

## 1. src/c.txt
> key
REVIEWER says start at c

## 2. b.txt
> key
REVIEWER on b

## 3. a.txt
REVIEWER on a

## 4. .review/walkthrough.md
REVIEWER on the author's own file
EOF
	run git review start --keys feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"2 keys"* ]]

	rm "$DRAFT"
	run git review status
	[ "$status" -ne 0 ]
	[[ "$output" == *"the walkthrough this review was reading is gone"* ]]
	[[ "$output" == *"git review walkthrough draft feature/x"* ]]
	[[ "$output" != *"HEAD has moved off"* ]]
	[[ "$output" != *"git reset --soft"* ]]
}

# ── compare ───────────────────────────────────────────────────────────────────

@test "compare on a branch with a draft reads the draft" {
	write_draft
	run git review compare develop feature/x
	[ "$status" -eq 0 ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"on src/c.txt"* ]]
}

@test "compare on a remote-tracking branch keeps reading the draft afterwards" {
	# The review's identity is <b> ("origin/feature/x"); the draft it opens on is
	# the branch's ("feature/x"). Every verb after the compare re-derives the
	# reading order, so unless the compare recorded which draft it read, they all
	# look one up under the review's own name, find none, and silently switch to
	# the author's order — the exact drift this file exists to catch.
	write_draft
	run git review compare develop origin/feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/4] src/c.txt"* ]]
	[ "$(git config branch.review/origin/feature/x.reviewwalkdraft)" = "feature/x" ]

	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"on src/c.txt"* ]]
	[[ "$output" == *"(draft)"* ]]
	run git review status --why src/c.txt
	[ "$status" -eq 0 ]
	[[ "$output" == *"REVIEWER says start at c"* ]]
	[[ "$output" != *"AUTHOR"* ]]
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"b.txt"* ]]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -Fxq 'draft'
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk (draft)"* ]]
}

@test "compare between loose revisions reads the author's walkthrough" {
	write_draft
	tip="$(git rev-parse origin/feature/x)"
	base="$(git rev-parse origin/develop)"
	run git review compare "$base" "$tip"
	[ "$status" -eq 0 ]
	run git review status
	[ "$status" -eq 0 ]
	# No branch was named, so there is no draft to look up: the author's order.
	[[ "$output" == *"on a.txt"* ]]
	[[ "$output" != *"(draft)"* ]]
}
