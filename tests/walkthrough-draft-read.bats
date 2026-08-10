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
# PR adds it), and it carries an entry here so that the reading order is all four
# entries rather than three plus one appended as uncovered — the totals in these
# tests are counted on that. Note that this shape is deliberately NOT buildable:
# annotatable_files filters .review/ out, so --build calls such an entry drift.
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

# The same reading order with two entries marked key. The author's walkthrough
# marks none, so under --keys the reviewer's sequence is two entries and falling
# back to the author's is observable as the sequence emptying — which is what
# puts the cursor out of range without touching HEAD.
write_keyed_draft() {
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
	# Attributed to whoever wrote the order that failed to apply. This PR carries a
	# walkthrough of its own, so blaming "feature/x has a walkthrough" would send
	# the reviewer to read the author's file looking for their own stale entry.
	[[ "$output" == *"you have a walkthrough draft for feature/x, but none of its entries apply"* ]]
	[[ "$output" != *"feature/x has a walkthrough, but"* ]]
}

@test "an author walkthrough that no longer applies offers the draft the assistant offers" {
	# config --porcelain answers "draft" for this situation; start used to answer
	# nothing, so the panel proposed a way out the terminal never mentioned.
	git switch --quiet feature/x
	printf '# Walkthrough\n\n## 1. gone.txt\nstale\n' >.review/walkthrough.md
	git add -A
	git commit --quiet -m stale
	git push --quiet origin feature/x
	git switch --quiet develop

	run git review start feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"feature/x has a walkthrough, but none of its entries apply"* ]]
	[[ "$output" == *"to read it in an order of your own instead: git review walkthrough draft feature/x"* ]]
	[ "$(git config branch.review/feature/x.reviewmode || echo whole)" = "whole" ]
}

@test "an empty draft falls back to the author's walkthrough instead of hiding it" {
	# Zero bytes is what an editor opened and closed, or a redirect, leaves behind.
	# It used to satisfy walk_read — rc 0, no content — so the author's walkthrough
	# was never consulted and the review landed in whole without a single note.
	mkdir -p "$(dirname "$DRAFT")"
	: >"$DRAFT"
	run git review start feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	# The author's order, in the author's words. Four entries, not three: the PR
	# adds the sidecar itself, and walk appends what the walkthrough does not name.
	[[ "$output" == *"[1/4] a.txt"* ]]
	[[ "$output" == *"AUTHOR says read a first"* ]]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"mode    walk "* ]]
	[[ "$output" != *"walk (draft)"* ]]
}

@test "a whitespace-only draft falls back the same way" {
	mkdir -p "$(dirname "$DRAFT")"
	printf '\n\n   \n\t\n' >"$DRAFT"
	run git review start feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	[[ "$output" == *"AUTHOR says read a first"* ]]
}

@test "an empty draft on a PR with no walkthrough says so instead of nothing" {
	# Same file, but now there is nothing to fall back to. The review is whole
	# either way; what changed is that it stopped being silent about why.
	git switch --quiet feature/x
	git rm --quiet .review/walkthrough.md
	git commit --quiet -m "drop the walkthrough"
	git push --quiet origin feature/x
	git switch --quiet develop

	mkdir -p "$(dirname "$DRAFT")"
	: >"$DRAFT"
	run git review start feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode || echo whole)" = "whole" ]
	[[ "$output" == *"your walkthrough draft for feature/x is empty"* ]]
	[[ "$output" == *"git review walkthrough draft feature/x --force"* ]]
}

@test "--keys over an empty draft blames the draft, not the PR" {
	git switch --quiet feature/x
	git rm --quiet .review/walkthrough.md
	git commit --quiet -m "drop the walkthrough"
	git push --quiet origin feature/x
	git switch --quiet develop

	mkdir -p "$(dirname "$DRAFT")"
	: >"$DRAFT"
	run git review start --keys feature/x
	[ "$status" -ne 0 ]
	[[ "$output" == *"your draft for feature/x is empty"* ]]
	! git rev-parse --verify --quiet refs/heads/review/feature/x >/dev/null
}

@test "--keys over an empty draft still finds the author's keys" {
	# The other half: an empty draft must not make --keys report that the PR has no
	# walkthrough when the PR has one with a key in it.
	git switch --quiet feature/x
	printf '# Walkthrough\n\n## 1. a.txt\n> key\nauthor key\n\n## 2. b.txt\nb\n\n## 3. src/c.txt\nc\n\n## 4. .review/walkthrough.md\nsidecar\n' >.review/walkthrough.md
	git add -A
	git commit --quiet -m keys
	git push --quiet origin feature/x
	git switch --quiet develop

	mkdir -p "$(dirname "$DRAFT")"
	: >"$DRAFT"
	run git review start --keys feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"keys-only: 1 key"* ]]
	[[ "$output" == *"[1/1] a.txt"* ]]
}

@test "a draft naming a path with an accent and a space reads it" {
	# The sidecar's bytes arrive through git show; a draft's arrive through a file
	# redirect. Same normalisation, different route in, and the symptom of getting
	# it wrong is the same invisible one: the entry silently drops out of the
	# reading order, or build names the identical file on both sides of a drift
	# error. The author's walkthrough has tests on this axis; the draft had none
	# beyond CRLF and a BOM.
	git switch --quiet feature/x
	mkdir -p src
	printf 'x\n' >"src/métricas de sesión.js"
	git add -A
	git commit --quiet -m accents
	git push --quiet origin feature/x
	git switch --quiet develop

	# .review/ is never annotated (annotatable_files filters it), so it gets no
	# entry here and the reader appends it as uncovered — which is the other half
	# of the same byte comparison.
	mkdir -p "$(dirname "$DRAFT")"
	cat >"$DRAFT" <<'EOF'
# Walkthrough

## 1. src/métricas de sesión.js
> key
REVIEWER starts on the accented one

## 2. a.txt
REVIEWER on a

## 3. b.txt
REVIEWER on b

## 4. src/c.txt
REVIEWER on c
EOF
	# --build first: the drift check compares every entry against git's own paths,
	# so it is the strictest reading of those bytes there is.
	run git review walkthrough draft --build feature/x
	[ "$status" -eq 0 ]
	[[ "$output" != *"not changed in the PR"* ]]
	[[ "$output" != *"missing from the walkthrough"* ]]
	[ "$(grep -c '^## 1\. src/métricas de sesión\.js$' "$DRAFT")" = "1" ]

	run git review start feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	# Four annotated entries plus the sidecar, appended because nothing annotates it.
	[ "$(git config branch.review/feature/x.reviewwalkcount)" = "5" ]
	[[ "$output" == *"[1/5] src/métricas de sesión.js  (key)"* ]]
	[[ "$output" == *"REVIEWER starts on the accented one"* ]]
	# The accented path matched, so it is not among the ones reported as uncovered —
	# asserted on that note's own line, since the path is all over the rest.
	uncovered="$(printf '%s\n' "$output" | grep 'not in the walkthrough are added')"
	[[ "$uncovered" == *": .review/walkthrough.md"* ]]
	[[ "$uncovered" != *"métricas"* ]]
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

@test "emptying the draft mid-review says empty, and names a command that works" {
	write_keyed_draft
	run git review start --keys feature/x
	[ "$status" -eq 0 ]
	git review next >/dev/null

	# Select-all and save is a likelier accident than deleting the file, and the
	# two are the same thing to walk_read. They are not the same thing to the
	# reviewer, who has the file open -- and the fix differs: draft refuses to
	# overwrite a file that exists, so "write it again" without --force would land
	# them on a second error for following the first one.
	: >"$DRAFT"
	run git review status
	[ "$status" -eq 1 ]
	[[ "$output" == *"the walkthrough this review was reading is gone"* ]]
	[[ "$output" == *"the file is now empty"* ]]
	[[ "$output" != *"no longer exists"* ]]
	[[ "$output" == *"git review walkthrough draft --force feature/x"* ]]

	# The command it names is one that works from here.
	run git review walkthrough draft --force feature/x
	[ "$status" -eq 0 ]
	[ -s "$DRAFT" ]
}

@test "following the redraft the CLI suggests never answers corrupt metadata" {
	# The whole loop, exactly as a reviewer walks it: the draft goes, the CLI says
	# to write it again, they do -- and the skeleton it writes back has no numbered
	# entry yet, so the sequence is empty while the draft is still very much in
	# force. That used to come out as "corrupt metadata? Discard the review", which
	# is untrue and names discarding as the only way out, at the end of a path the
	# product itself had just recommended.
	write_keyed_draft
	run git review start --keys feature/x
	[ "$status" -eq 0 ]
	git review next >/dev/null
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "2" ]

	rm "$DRAFT"
	run git review status
	[ "$status" -eq 1 ]
	[[ "$output" == *"git review walkthrough draft feature/x"* ]]

	run git review walkthrough draft feature/x
	[ "$status" -eq 0 ]
	run git review status
	[ "$status" -eq 1 ]
	[[ "$output" == *"has no entries in this review's range"* ]]
	[[ "$output" == *"git review walkthrough draft --build feature/x"* ]]
	[[ "$output" != *"corrupt metadata"* ]]
	[[ "$output" != *"HEAD has moved off"* ]]

	# And it really is recoverable: number the entries, build with the command the
	# message named, and the review reads again at the cursor it was on -- rather
	# than the review being discarded, which is all the old message offered.
	# Without the .review/ entry here, unlike write_keyed_draft: --build calls that
	# one drift, and this step has to be the buildable shape a reviewer following
	# the message would end up with.
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
EOF
	run git review walkthrough draft --build feature/x
	[ "$status" -eq 0 ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"(draft)"* ]]
	[[ "$output" == *"[2/2] on b.txt"* ]]
}

@test "editing your own draft shorter re-seats the cursor instead of blaming HEAD" {
	# The draft is the one walkthrough a reviewer is invited to edit mid-review, and
	# under --keys the sequence really does shrink when they unmark an entry. The
	# cursor then sits past the end — which used to be reported as "HEAD has moved
	# off this review's base ... did you run git commit?", with an instruction to
	# run git reset --soft over a HEAD that had not moved, and no way back short of
	# discarding the review.
	mkdir -p "$(dirname "$DRAFT")"
	cat >"$DRAFT" <<'EOF'
# Walkthrough

## 1. a.txt
> key
one

## 2. b.txt
> key
two

## 3. src/c.txt
> key
three

## 4. .review/walkthrough.md
> key
four
EOF
	run git review start --keys feature/x
	[ "$status" -eq 0 ]
	git review next
	git review next
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "3" ]
	head_before="$(git rev-parse HEAD)"

	# Two entries stop being keys. Same file, same review, nothing committed.
	cat >"$DRAFT" <<'EOF'
# Walkthrough

## 1. a.txt
> key
one

## 2. b.txt
two, no longer key

## 3. src/c.txt
three, no longer key

## 4. .review/walkthrough.md
> key
four
EOF
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"your walkthrough draft for feature/x now has 2 entries in this review's range"* ]]
	[[ "$output" == *"the cursor was at 3 and moved to 2"* ]]
	[[ "$output" != *"HEAD has moved off"* ]]
	[[ "$output" != *"git reset --soft"* ]]
	[ "$(git rev-parse HEAD)" = "$head_before" ]

	# Re-seated for good, not just for that one command: the review is usable again.
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "2" ]
	[ "$(git config branch.review/feature/x.reviewwalkcount)" = "2" ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" != *"moved to 2"* ]]
	run git review prev
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/2] a.txt"* ]]
}

@test "a stray commit under a draft review still gets the HEAD diagnostic" {
	# The other side of the same fork: the reviewer's draft is in force and intact,
	# but HEAD really did move. Recovering the cursor here would hide a staged diff
	# that has just been folded into a commit, so the range check has to ask git
	# where HEAD is rather than infer it from the sequence having got shorter.
	write_draft
	run git review start feature/x
	[ "$status" -eq 0 ]
	git review next
	git review next
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "3" ]

	git commit --quiet -m "the stray commit"

	run git review status
	[ "$status" -eq 3 ]
	[[ "$output" == *"HEAD has moved off this review's base"* ]]
	[[ "$output" == *"did you run git commit?"* ]]
	[[ "$output" != *"moved to"* ]]
	# Nothing was re-seated behind the reviewer's back.
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "3" ]
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
