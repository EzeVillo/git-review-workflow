#!/usr/bin/env bats
#
# Tests for advice: the notes a caller with its own interface does not need.
#
# Two kinds are advice, and the question for both is "does the caller already
# have this?" -- an offer of a command or a flag (it has the button) and state
# that already travels as a porcelain record (it has the row). Everything else
# a verb says is not advice and prints either way; those tests are here too,
# because the line between the two is the whole point and a change that quiets
# the wrong half would otherwise pass.
#
# Default is ON: a terminal keeps every note it has always had. The suites that
# assert on those notes never set anything, which is what makes this file the
# only place the off state is exercised.

bats_require_minimum_version 1.5.0

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
	git add a.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop

	git switch --quiet -c feature/plain
	printf 'a1\na2\n' >a.txt
	git add -A
	git commit --quiet -m work
	git push --quiet -u origin feature/plain
	git switch --quiet develop

	DRAFT="$(git rev-parse --git-dir)/review-walkthrough/feature/plain.md"
}

teardown() {
	rm -rf "$TMP"
}

# ── the switch ────────────────────────────────────────────────────────────────

@test "advice is on by default: the draft names the command that follows" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"then run git review walkthrough draft --build"* ]]
}

@test "GIT_REVIEW_ADVICE=0 drops the offer and keeps the result" {
	export GIT_REVIEW_ADVICE=0
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	# The offer is gone...
	[[ "$output" != *"git review walkthrough draft --build"* ]]
	# ...and what the verb DID is still said, in full.
	[[ "$output" == *"with 1 file(s) from origin/feature/plain"* ]]
	# Quieting a note never changes what happens on disk.
	[ -f "$DRAFT" ]
}

@test "reviewworkflow.advice=false drops the offer too" {
	git config reviewworkflow.advice false
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" != *"git review walkthrough draft --build"* ]]
	[ -f "$DRAFT" ]
}

@test "the environment wins over the config, as in git" {
	git config reviewworkflow.advice false
	export GIT_REVIEW_ADVICE=1
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"then run git review walkthrough draft --build"* ]]
}

@test "reviewworkflow.advice=true is the default, spelled out" {
	git config reviewworkflow.advice true
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"then run git review walkthrough draft --build"* ]]
}

@test "a junk value in the environment falls through to the default" {
	# Neither on nor off: unrecognised means "nobody asked for quiet", which is
	# the state a terminal must never lose a note to.
	export GIT_REVIEW_ADVICE=maybe
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"then run git review walkthrough draft --build"* ]]
}

# ── which notes are advice ────────────────────────────────────────────────────

@test "the authoring guide note is advice from end to end" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"no authoring guide"* ]]

	rm -f "$DRAFT"
	export GIT_REVIEW_ADVICE=0
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" != *"authoring guide"* ]]
}

@test "a guide in force is advice too: the guide record already carries it" {
	mkdir -p .review
	printf 'mark the entry that carries the change\n' >.review/walkthrough-guide.md
	git add .review/walkthrough-guide.md
	git commit --quiet -m guide

	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"authoring guide in force"* ]]

	rm -f "$DRAFT"
	export GIT_REVIEW_ADVICE=0
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" != *"in force"* ]]
}

@test "the draft shadowing the author's walkthrough is advice" {
	git switch --quiet feature/plain
	mkdir -p .review
	printf '## 1. a.txt\n\nwhy it matters\n' >.review/walkthrough.md
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough
	git push --quiet origin feature/plain
	git switch --quiet develop

	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"already carries a walkthrough from its author"* ]]

	rm -f "$DRAFT"
	export GIT_REVIEW_ADVICE=0
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" != *"from its author"* ]]
	# The shadowing still happens; only the sentence about it is gone.
	[ -f "$DRAFT" ]
}

@test "start keeps the state half of a mixed note and drops the flag half" {
	git switch --quiet feature/plain
	printf 'a1\na2\na3\n' >a.txt
	git add -A
	git commit --quiet -m 'local only'
	git switch --quiet develop

	run git review start feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"differs from your local"* ]]
	[[ "$output" == *"use --local"* ]]
	run git review abort
	[ "$status" -eq 0 ]

	export GIT_REVIEW_ADVICE=0
	run git review start feature/plain
	[ "$status" -eq 0 ]
	# The state survives: you are reading the remote, not what you checked out.
	[[ "$output" == *"differs from your local"* ]]
	# The offer does not.
	[[ "$output" != *"--local"* ]]
}

# ── what advice is NOT ────────────────────────────────────────────────────────

@test "an entry the PR no longer changes is named even with advice off" {
	# Not advice: no record carries it, so no panel row can answer it. This is
	# the case that separates "the caller already has this" from "this note is
	# long", and quieting it would lose prose somebody typed.
	git switch --quiet feature/plain
	printf 'b1\n' >b.txt
	git add -A
	git commit --quiet -m 'add b'
	git push --quiet origin feature/plain
	git switch --quiet develop

	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[ -f "$DRAFT" ]

	git switch --quiet feature/plain
	git rm --quiet b.txt
	git commit --quiet -m 'drop b'
	git push --quiet origin feature/plain
	git switch --quiet develop

	export GIT_REVIEW_ADVICE=0
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"dropped"* ]]
	[[ "$output" == *"b.txt"* ]]
}

# ── the record that replaces the sentence ─────────────────────────────────────

@test "draft --porcelain emits merged and nothing else on stdout" {
	run --separate-stderr git review walkthrough draft --porcelain feature/plain
	[ "$status" -eq 0 ]
	# A fresh skeleton is all additions: one file in range, nothing kept or
	# dropped. Exact equality, because the whole point of the record is that a
	# client reads fields and not prose.
	[ "$output" = "$(printf 'merged\t0\t1\t0')" ]
	[ -f "$DRAFT" ]
}

@test "draft --porcelain counts an update instead of describing it" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]

	git switch --quiet feature/plain
	printf 'b1\n' >b.txt
	git add -A
	git commit --quiet -m 'add b'
	git push --quiet origin feature/plain
	git switch --quiet develop

	run --separate-stderr git review walkthrough draft --porcelain feature/plain
	[ "$status" -eq 0 ]
	# a.txt kept with its number, b.txt added, nothing dropped.
	[ "$output" = "$(printf 'merged\t1\t1\t0')" ]
}

@test "init --porcelain has the same shape from the author's side" {
	git switch --quiet feature/plain
	run --separate-stderr git review walkthrough init --porcelain
	[ "$status" -eq 0 ]
	[ "$output" = "$(printf 'merged\t0\t1\t0')" ]
	[ -f .review/walkthrough.md ]
}

@test "draft --porcelain --stdout still writes nothing and prints the skeleton" {
	# --stdout owns stdout: the record would corrupt the file a redirect makes.
	run git review walkthrough draft --porcelain --stdout feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" != *"$(printf 'merged\t')"* ]]
	[ ! -f "$DRAFT" ]
}
