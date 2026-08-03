#!/usr/bin/env bats
#
# Tests for `git review status --porcelain` and `git review status --why`: the
# machine-readable contract in contracts/status-porcelain.md (list --porcelain
# gets its own tests in tests/list.bats). The PR fixture mirrors
# tests/walk.bats: feature/x changes a.txt and b.txt (edited) and adds
# src/c.txt vs develop.

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"
	REPO="$BATS_TEST_DIRNAME/.."

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
	git push --quiet -u origin feature/x

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

# Replace the committed walkthrough on feature/x with the content on stdin and
# push it, leaving the caller back on develop where setup left them.
recommit_walkthrough() {
	git switch --quiet feature/x
	mkdir -p .review
	cat >.review/walkthrough.md
	git add .review/walkthrough.md
	git commit --quiet -m rewt
	git push --quiet origin feature/x
	git switch --quiet develop
}

# Snapshot review config, git's own status --porcelain and refs/review-edits/,
# assert nothing changed after the caller has run its read-only commands.
assert_zero_mutation() {
	before_config="$(git config --get-regexp 'branch\..*\.review' || true)"
	before_status="$(git status --porcelain)"
	before_refs="$(git for-each-ref refs/review-edits/)"

	"$@"

	after_config="$(git config --get-regexp 'branch\..*\.review' || true)"
	after_status="$(git status --porcelain)"
	after_refs="$(git for-each-ref refs/review-edits/)"

	[ "$before_config" = "$after_config" ]
	[ "$before_status" = "$after_status" ]
	[ "$before_refs" = "$after_refs" ]
}

# ── state record (US1) ─────────────────────────────────────────────────────────

@test "status --porcelain emits the exact state line for whole mode" {
	run git review start feature/x
	[ "$status" -eq 0 ]
	tip="$(git rev-parse origin/feature/x)"
	expected="$(printf 'state\treview/feature/x\tfeature/x\t%s\twhole\tnone' "$tip")"
	run git review status --porcelain
	[ "$status" -eq 0 ]
	# The first line, like the step and walk versions of this test: whole mode
	# stopped being a single-line output when the `base` record joined it, and
	# what this test is about is the arity and content of `state` itself.
	firstline="$(printf '%s\n' "$output" | sed -n '1p')"
	[ "$firstline" = "$expected" ]
}

@test "status --porcelain emits the exact state line for step mode" {
	tip="$(git rev-parse origin/feature/x)"
	c1short="$(git rev-parse --short "$(git rev-list --reverse develop..origin/feature/x | sed -n 1p)")"
	run git review start feature/x --step
	[ "$status" -eq 0 ]
	expected="$(printf 'state\treview/feature/x\tfeature/x\t%s\tstep\tnone\t1\t2\t2\t%s' "$tip" "$c1short")"
	run git review status --porcelain
	[ "$status" -eq 0 ]
	firstline="$(printf '%s\n' "$output" | sed -n '1p')"
	[ "$firstline" = "$expected" ]
}

@test "status --porcelain emits the exact state line for walk mode, marking the key entry" {
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
	tip="$(git rev-parse origin/feature/x)"
	run git review start feature/x
	[ "$status" -eq 0 ]
	expected="$(printf 'state\treview/feature/x\tfeature/x\t%s\twalk\tapplied\t1\t3\t3\tsrc/c.txt\t1' "$tip")"
	run git review status --porcelain
	[ "$status" -eq 0 ]
	firstline="$(printf '%s\n' "$output" | sed -n '1p')"
	[ "$firstline" = "$expected" ]
}

@test "status --porcelain total differs from recorded when the base drifts but the cursor stays in range" {
	recommit_walkthrough <<'EOF'
# Walkthrough

## 1. src/c.txt
read the new helper first

## 2. a.txt
then the a change

## 3. b.txt
finally b
EOF
	tip="$(git rev-parse origin/feature/x)"
	git review start feature/x >/dev/null
	# Fold a.txt and b.txt into HEAD (a partial commit), leaving only src/c.txt in
	# the reviewed range; the cursor (still at entry 1, src/c.txt) stays in range,
	# so this is 0/success, not the exit-3 drift case (that lives in walk.bats).
	git commit --quiet -m "advance a and b" -- a.txt b.txt

	run git review status --porcelain
	[ "$status" -eq 0 ]
	expected="$(printf 'state\treview/feature/x\tfeature/x\t%s\twalk\tapplied\t1\t1\t3\tsrc/c.txt\t0' "$tip")"
	firstline="$(printf '%s\n' "$output" | sed -n '1p')"
	[ "$firstline" = "$expected" ]
	entries="$(printf '%s\n' "$output" | grep '^entry')"
	[ "$entries" = "$(printf 'entry\t1\tsrc/c.txt\t0\t1')" ]
}

@test "status --porcelain output does not change when status's human-facing text is rewritten" {
	git review start feature/x >/dev/null
	before="$(git review status --porcelain)"

	# The repo is mounted read-only under tests/run-docker.sh, so copy bin/ to a
	# writable scratch dir and rewrite a human-facing message in the copy — proves
	# --porcelain output is independent of the human text (FR-003/SC-004), without
	# touching the shipped script.
	scratch="$TMP/scratch-bin"
	mkdir -p "$scratch/git-review-verbs"
	cp "$REPO/bin/git-review" "$scratch/"
	cp "$REPO/bin/git-review-lib.sh" "$scratch/"
	cp "$REPO"/bin/git-review-verbs/* "$scratch/git-review-verbs/"
	chmod +x "$scratch/git-review" "$scratch"/git-review-verbs/*
	sed 's/review of %s (tip %s)/REWRITTEN review of %s (tip %s)/' \
		"$scratch/git-review-verbs/status" >"$scratch/git-review-verbs/status.new"
	mv "$scratch/git-review-verbs/status.new" "$scratch/git-review-verbs/status"
	chmod +x "$scratch/git-review-verbs/status"

	humantext="$(PATH="$scratch:$PATH" git review status)"
	[[ "$humantext" == *"REWRITTEN review of"* ]]

	after="$(PATH="$scratch:$PATH" git review status --porcelain)"
	[ "$before" = "$after" ]
}

# ── entry records (US2) ────────────────────────────────────────────────────────

@test "status --porcelain entry sequence excludes out-of-range entries and marks essential correctly, non-ASCII paths literal" {
	# Chinese characters via octal escapes: a single, unambiguous byte sequence
	# that cannot be affected by macOS filesystem Unicode normalisation.
	NONASCII="src/$(printf '\346\226\207\346\233\270').txt"
	git switch --quiet feature/x
	printf 'u\n' >"$NONASCII"
	git add "$NONASCII"
	git commit --quiet -m c3-add-nonascii
	c1="$(git rev-list --reverse develop..HEAD | sed -n 1p)"
	git push --quiet origin feature/x
	git switch --quiet develop

	quoted="$(git -c core.quotePath=true diff --name-only develop feature/x | grep -c '^"' || true)"
	[ "$quoted" -eq 1 ] || skip "this platform does not round-trip a non-ASCII path"

	recommit_walkthrough <<EOF
# Walkthrough

## 1. a.txt
main change

## 2. b.txt
side change

## 3. src/c.txt
> key
new helper

## 4. $NONASCII
unicode helper
EOF

	# --from c1 excludes c1 (a.txt) from the reviewed range: entry 1 must drop out
	# of the derived sequence entirely, and the survivors renumber 1..3.
	run git review start feature/x --from "$c1"
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	entries="$(printf '%s\n' "$output" | grep '^entry')"
	expected="$(printf 'entry\t1\tb.txt\t0\t1\nentry\t2\tsrc/c.txt\t1\t1\nentry\t3\t%s\t0\t1' "$NONASCII")"
	[ "$entries" = "$expected" ]
}

@test "status --porcelain emits zero entry lines for whole mode without an applicable walkthrough" {
	run git review start feature/x
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	n="$(printf '%s\n' "$output" | grep -c '^entry' || true)"
	[ "$n" -eq 0 ]
}

@test "a BOM or CRLF walkthrough yields the same porcelain entry sequence as a clean one" {
	cat >"$TMP/wt.lf" <<'EOF'
# Walkthrough

## 1. src/c.txt
read first

## 2. a.txt
then a

## 3. b.txt
finally b
EOF
	recommit_walkthrough <"$TMP/wt.lf"
	git review start feature/x >/dev/null
	clean="$(git review status --porcelain | grep '^entry')"
	git review abort >/dev/null

	git switch --quiet feature/x
	{ printf '\357\273\277'; cat "$TMP/wt.lf"; } >.review/walkthrough.md
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough-bom
	git push --quiet origin feature/x
	git switch --quiet develop
	git review start feature/x >/dev/null
	bom="$(git review status --porcelain | grep '^entry')"
	[ "$bom" = "$clean" ]
	git review abort >/dev/null

	git switch --quiet feature/x
	while IFS= read -r line; do printf '%s\r\n' "$line"; done <"$TMP/wt.lf" >.review/walkthrough.md
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough-crlf
	git push --quiet origin feature/x
	git switch --quiet develop
	git review start feature/x >/dev/null
	crlf="$(git review status --porcelain | grep '^entry')"
	[ "$crlf" = "$clean" ]
}

@test "a path with spaces stays literal and a path with a quote comes out git-quoted, unmodified" {
	# A literal double quote in a filename cannot be passed reliably as a
	# command-line argument to a native Windows executable (git.exe): the CRT
	# argv parser treats '"' as a quoting delimiter, not a literal character,
	# so `git add` ends up looking for a different pathspec than the file that
	# was actually created and fails with "did not match any files".
	case "$(uname -s)" in
		CYGWIN* | MINGW* | MSYS*) skip "a literal double quote in a filename is not representable as a Windows command-line argument" ;;
	esac
	git switch --quiet feature/x
	printf 'v\n' >'has space.txt'
	printf 'v\n' >'has"quote.txt'
	git add 'has space.txt' 'has"quote.txt'
	git commit --quiet -m "add odd paths"
	git push --quiet origin feature/x
	git switch --quiet develop

	lower="$(git merge-base develop origin/feature/x)"
	tip="$(git rev-parse origin/feature/x)"
	quotedname="$(git -c core.quotePath=false diff --name-only "$lower" "$tip" -- 'has"quote.txt')"
	[ -n "$quotedname" ]

	recommit_walkthrough <<'EOF'
# Walkthrough

## 1. src/c.txt
covered

## 2. a.txt
covered

## 3. b.txt
covered
EOF
	run git review start feature/x
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	# Not a separate uncovered record: two more entries, appended to the end of
	# the reading order, unannotated — same literal-vs-quoted rules as any path.
	# Positions 4/5 are whichever order changed_paths reports the two in, so
	# compare id/essential/annotated only, not the exact position-to-file pairing.
	entries="$(printf '%s\n' "$output" | grep '^entry')"
	n="$(printf '%s\n' "$entries" | grep -c . || true)"
	[ "$n" -eq 5 ]
	tail="$(printf '%s\n' "$entries" | tail -n 2 | cut -f3- | LC_ALL=C sort)"
	expected="$(printf 'has space.txt\t0\t0\n%s\t0\t0' "$quotedname" | LC_ALL=C sort)"
	[ "$tail" = "$expected" ]
}

# ── --why (US4) ─────────────────────────────────────────────────────────────────

@test "status --why prints only the entry's explanatory text, verbatim, and errors cleanly" {
	recommit_walkthrough <<'EOF'
# Walkthrough

## 1. src/c.txt
> key
first line of why
second line of why

## 2. a.txt
single line why

## 3. b.txt
EOF
	git review start feature/x >/dev/null

	run git review status --why src/c.txt
	[ "$status" -eq 0 ]
	expected="$(printf 'first line of why\nsecond line of why')"
	[ "$output" = "$expected" ]
	[[ "$output" != *"> key"* ]]

	run git review status --why a.txt
	[ "$status" -eq 0 ]
	[ "$output" = "single line why" ]

	# Entry with no body at all: empty stdout, exit 0 (Acceptance Scenario 3).
	run git review status --why b.txt
	[ "$status" -eq 0 ]
	[ "$output" = "" ]

	run git review status --why nosuchpath.txt
	[ "$status" -eq 1 ]
	[[ "$output" == *"not in the current walkthrough sequence"* ]]
}

@test "status --why fails outside walk mode" {
	git review start feature/x >/dev/null
	run git review status --why a.txt
	[ "$status" -eq 1 ]
	[[ "$output" == *"--why only applies"* ]]
}

@test "status --porcelain and --why are mutually exclusive" {
	git review start feature/x >/dev/null
	run git review status --porcelain --why a.txt
	[ "$status" -eq 1 ]
	[[ "$output" == *"mutually exclusive"* ]]
}

# ── annotated field (US5) ─────────────────────────────────────────────────────

@test "status --porcelain appends a file missing from the walkthrough as an unannotated entry, never as its own record type" {
	recommit_walkthrough <<'EOF'
# Walkthrough

## 1. src/c.txt
covered

## 2. a.txt
covered
EOF
	# b.txt stays out of the walkthrough on purpose.
	run git review start feature/x
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	n="$(printf '%s\n' "$output" | grep -c '^uncovered' || true)"
	[ "$n" -eq 0 ]
	entries="$(printf '%s\n' "$output" | grep '^entry')"
	expected="$(printf 'entry\t1\tsrc/c.txt\t0\t1\nentry\t2\ta.txt\t0\t1\nentry\t3\tb.txt\t0\t0')"
	[ "$entries" = "$expected" ]
	total="$(printf '%s\n' "$output" | sed -n '1p' | cut -f8)"
	[ "$total" -eq 3 ]
}

@test "status --porcelain marks every entry annotated when the walkthrough covers the whole range" {
	recommit_walkthrough <<'EOF'
# Walkthrough

## 1. src/c.txt
covered

## 2. a.txt
covered

## 3. b.txt
covered
EOF
	run git review start feature/x
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	n="$(printf '%s\n' "$output" | grep -c '^uncovered' || true)"
	[ "$n" -eq 0 ]
	unannotated="$(printf '%s\n' "$output" | grep '^entry' | awk -F'\t' '$5 == 0' | grep -c . || true)"
	[ "$unannotated" -eq 0 ]
}

# ── step entry records ────────────────────────────────────────────────────────

@test "status --porcelain marks banked steps by whole position, not by numeric prefix" {
	# Eleven commits so position 1 is a prefix of position 11: the banked field
	# is derived from one bulk listing of refs/review-edits/<src>/ plus a shell
	# membership test, and a test that matched the ref name as a substring would
	# report step 1 as banked because step 11 is.
	git switch --quiet -c feature/many develop
	n=1
	while [ "$n" -le 11 ]; do
		printf 'm%s\n' "$n" >>m.txt
		git add m.txt
		git commit --quiet -m "m$n"
		n=$((n + 1))
	done
	git switch --quiet develop

	run git review start feature/many --offline --step
	[ "$status" -eq 0 ]
	n=1
	while [ "$n" -le 10 ]; do
		run git review next
		[ "$status" -eq 0 ]
		n=$((n + 1))
	done
	# Edit step 11 and step back, which banks it and leaves the cursor on 10.
	printf 'edit\n' >>m.txt
	run git review prev
	[ "$status" -eq 0 ]

	# The precondition this test rests on: exactly one banked ref, and it is 11.
	[ "$(git for-each-ref --format='%(refname)' refs/review-edits/feature/many/)" = "refs/review-edits/feature/many/11" ]

	run git review status --porcelain
	[ "$status" -eq 0 ]
	banked="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "entry" && $4 == 1 { print $2 }')"
	[ "$banked" = "11" ]
	# And the sequence itself is intact: eleven entries, every other one at 0.
	unbanked="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "entry" && $4 == 0 { print $2 }')"
	[ "$unbanked" = "$(seq 1 10)" ]
}

@test "status --porcelain abbreviates entry SHAs exactly like git rev-parse --short" {
	# The bulk list is git rev-list --abbrev-commit with no explicit --abbrev=<n>,
	# so it must follow core.abbrev the same way the per-commit rev-parse --short
	# it replaced did. A pinned length would pass at the default and diverge here.
	git config core.abbrev 12
	run git review start feature/x --step
	[ "$status" -eq 0 ]

	c1short="$(git rev-parse --short "$(git rev-list --reverse develop..origin/feature/x | sed -n 1p)")"
	c2short="$(git rev-parse --short "$(git rev-list --reverse develop..origin/feature/x | sed -n 2p)")"
	[ "${#c1short}" -eq 12 ]

	run git review status --porcelain
	[ "$status" -eq 0 ]
	entries="$(printf '%s\n' "$output" | grep '^entry')"
	expected="$(printf 'entry\t1\t%s\t0\nentry\t2\t%s\t0' "$c1short" "$c2short")"
	[ "$entries" = "$expected" ]
	# The state record's current field is abbreviated from the same list.
	[ "$(printf '%s\n' "$output" | sed -n '1p' | cut -f10)" = "$c1short" ]
}

# ── subject/author records (003 US1) ──────────────────────────────────────────

@test "status --porcelain emits one subject and one author line per step position" {
	run git review start feature/x --step
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]

	# Distinct subjects on purpose: the whole point of aligning the two git log
	# runs with `commits` by line number is that position N carries commit N's
	# text. Identical subjects would pass even fully misaligned.
	subjects="$(printf '%s\n' "$output" | grep '^subject')"
	expected="$(printf 'subject\t1\tc1-touch-a\nsubject\t2\tc2-touch-b-add-c')"
	[ "$subjects" = "$expected" ]

	authors="$(printf '%s\n' "$output" | grep '^author')"
	expected="$(printf 'author\t1\ttester <t@example.com>\nauthor\t2\ttester <t@example.com>')"
	[ "$authors" = "$expected" ]

	# One per position, matching the entry records exactly: a consumer pairs by
	# position, so a missing line is a hole and an extra one is a lie.
	[ "$(printf '%s\n' "$output" | grep -c '^entry')" -eq 2 ]
}

@test "status --porcelain emits no subject or author record in whole mode" {
	run git review start feature/x
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	found="$(printf '%s\n' "$output" | grep -cE '^(subject|author)' || true)"
	[ "$found" -eq 0 ]
	# And the mode really is the one under test, not a review that failed to start.
	[ "$(printf '%s\n' "$output" | sed -n '1p' | cut -f5)" = "whole" ]
}

@test "status --porcelain emits no subject or author record in walk mode" {
	recommit_walkthrough <<'EOF'
# Walkthrough

## 1. src/c.txt
new helper

## 2. a.txt
main change

## 3. b.txt
side change
EOF
	run git review start feature/x
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	found="$(printf '%s\n' "$output" | grep -cE '^(subject|author)' || true)"
	[ "$found" -eq 0 ]
	[ "$(printf '%s\n' "$output" | sed -n '1p' | cut -f5)" = "walk" ]
}

# ── base record (003 US2) ─────────────────────────────────────────────────────

@test "status --porcelain emits the base record in whole mode" {
	run git review start feature/x
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	# Single record, no position: the base belongs to the review, not to an entry.
	[ "$(printf '%s\n' "$output" | grep '^base')" = "$(printf 'base\tdevelop')" ]
	# And `state` is still the first line, ahead of it.
	[ "$(printf '%s\n' "$output" | sed -n '1p' | cut -f1)" = "state" ]
}

@test "status --porcelain omits the base record when no base is recorded" {
	run git review start feature/x
	[ "$status" -eq 0 ]
	git config --unset branch.review/feature/x.reviewbase

	run git review status --porcelain
	[ "$status" -eq 0 ]
	# Omitted whole, never emitted blank: `base` with an empty field would read
	# as "the base is the empty string" instead of "there is none".
	n="$(printf '%s\n' "$output" | grep -c '^base' || true)"
	[ "$n" -eq 0 ]
	# The review is still perfectly readable without it.
	[ "$(printf '%s\n' "$output" | sed -n '1p' | cut -f5)" = "whole" ]
}

@test "status --porcelain emits no base record in step or walk mode" {
	run git review start feature/x --step
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | grep -c '^base' || true)" -eq 0 ]
	[ "$(printf '%s\n' "$output" | sed -n '1p' | cut -f5)" = "step" ]

	run git review abort
	[ "$status" -eq 0 ]
	recommit_walkthrough <<'EOF'
# Walkthrough

## 1. a.txt
main change

## 2. b.txt
side change

## 3. src/c.txt
new helper
EOF
	run git review start feature/x
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | grep -c '^base' || true)" -eq 0 ]
	[ "$(printf '%s\n' "$output" | sed -n '1p' | cut -f5)" = "walk" ]
}

# ── cross-cutting: zero mutation, separate channels, additivity ─────────────────

@test "status --porcelain and list --porcelain make zero mutations in whole mode" {
	git review start feature/x >/dev/null
	assert_zero_mutation sh -c 'git review status --porcelain >/dev/null && git review list --porcelain >/dev/null'
}

@test "status --porcelain and list --porcelain make zero mutations in step mode" {
	git review start feature/x --step >/dev/null
	assert_zero_mutation sh -c 'git review status --porcelain >/dev/null && git review list --porcelain >/dev/null'
}

@test "status --porcelain, --why and list --porcelain make zero mutations in walk mode" {
	recommit_walkthrough <<'EOF'
# Walkthrough

## 1. src/c.txt
covered

## 2. a.txt
covered

## 3. b.txt
covered
EOF
	git review start feature/x >/dev/null
	assert_zero_mutation sh -c \
		'git review status --porcelain >/dev/null && git review status --why src/c.txt >/dev/null && git review list --porcelain >/dev/null'
}

@test "status --porcelain and --why never put data on stderr, and diagnostics never land on stdout" {
	recommit_walkthrough <<'EOF'
# Walkthrough

## 1. src/c.txt
covered

## 2. a.txt
covered

## 3. b.txt
covered
EOF
	git review start feature/x >/dev/null

	git review status --porcelain >"$TMP/out" 2>"$TMP/err"
	[ ! -s "$TMP/err" ]
	[ -s "$TMP/out" ]

	git review status --why src/c.txt >"$TMP/out" 2>"$TMP/err"
	[ ! -s "$TMP/err" ]

	# An unknown --why path is a diagnostic: it must land on stderr, never stdout.
	git review status --why nosuchpath.txt >"$TMP/out" 2>"$TMP/err" || true
	[ ! -s "$TMP/out" ]
	[ -s "$TMP/err" ]
}

@test "a consumer reading only label and path/id stays correct even with an unknown record type (additivity, FR-002)" {
	recommit_walkthrough <<'EOF'
# Walkthrough

## 1. src/c.txt
covered

## 2. a.txt
covered

## 3. b.txt
EOF
	git review start feature/x >/dev/null
	out="$(git review status --porcelain)"

	firstentry="$(printf '%s\n' "$out" | grep '^entry' | sed -n '1p' | cut -f1-2)"
	[ "$firstentry" = "$(printf 'entry\t1')" ]

	# A record type this consumer does not know must not disturb the cut -f1-2
	# recipe on the records it does know (the promise, fixed by test).
	withbogus="$(printf '%s\nbogus\tsome-field\textra\n' "$out")"
	bogusline="$(printf '%s\n' "$withbogus" | grep '^bogus' | cut -f1-2)"
	[ "$bogusline" = "$(printf 'bogus\tsome-field')" ]
}
