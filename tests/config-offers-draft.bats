#!/usr/bin/env bats
#
# The draft / draft-resume reading offers in git review config --porcelain.
#
# These are what let the start assistant offer writing a reading order at the one
# moment the reviewer is asking how to read the PR. The clients never inspect a
# draft themselves, so what is asserted here is the whole of what they know.
#
# feature/plain has no walkthrough; feature/annotated has one from its author.

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
	printf 'hello\n' >c.txt
	git add -A
	git commit --quiet -m work
	git push --quiet -u origin feature/plain

	git switch --quiet develop
	git switch --quiet -c feature/annotated
	printf 'b1\n' >b.txt
	mkdir -p .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. b.txt
> key
the author's order
EOF
	git add -A
	git commit --quiet -m work
	git push --quiet -u origin feature/annotated

	git switch --quiet develop
	DRAFT="$(git rev-parse --git-dir)/review-walkthrough/feature/plain.md"
}

teardown() {
	rm -rf "$TMP"
}

# The offer ids emitted for <branch>, in order, one per line.
offers_for() {
	git review config --porcelain -- "$1" | awk -F'\t' '$1 == "offer" { print $2 }'
}

@test "a PR with no walkthrough offers draft, step and whole" {
	run offers_for feature/plain
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "draft" ]
	[ "${lines[1]}" = "step" ]
	[ "${lines[2]}" = "whole" ]
	[ "${#lines[@]}" -eq 3 ]
}

@test "a PR with the author's walkthrough is never offered draft" {
	run offers_for feature/annotated
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "walk" ]
	[ "${lines[1]}" = "keys" ]
	[ "${lines[2]}" = "step" ]
	[ "${lines[3]}" = "whole" ]
	[ "${#lines[@]}" -eq 4 ]
}

@test "once a draft exists the offer becomes draft-resume, alongside walk" {
	git review walkthrough draft feature/plain
	cat >"$DRAFT" <<'EOF'
# Walkthrough

## 1. c.txt
start here

## 2. a.txt
then a
EOF
	run offers_for feature/plain
	[ "$status" -eq 0 ]
	# walk, because the draft is already readable; draft-resume, because it can
	# still be worked on. Both, and in the contract's order.
	[ "${lines[0]}" = "walk" ]
	[ "${lines[1]}" = "draft-resume" ]
	[ "${lines[2]}" = "step" ]
	[ "${lines[3]}" = "whole" ]
	[ "${#lines[@]}" -eq 4 ]
}

@test "an unfilled draft still offers draft-resume and never draft" {
	git review walkthrough draft feature/plain
	run offers_for feature/plain
	[ "$status" -eq 0 ]
	# No walk: a skeleton has no numbered entries, so nothing intersects the range.
	[ "${lines[0]}" = "draft-resume" ]
	[ "${lines[1]}" = "step" ]
	[ "${lines[2]}" = "whole" ]
	[ "${#lines[@]}" -eq 3 ]
}

@test "a draft on an annotated PR replaces walk's source and offers draft-resume" {
	git review walkthrough draft feature/annotated 2>/dev/null
	d="$(git rev-parse --git-dir)/review-walkthrough/feature/annotated.md"
	cat >"$d" <<'EOF'
# Walkthrough

## 1. b.txt
the reviewer's order, no key at all

## 2. .review/walkthrough.md
the author's own file
EOF
	run offers_for feature/annotated
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "walk" ]
	# keys is gone: the reviewer's draft marks none, and viability is read off the
	# walkthrough in force, not off the author's.
	[ "${lines[1]}" = "draft-resume" ]
	[ "${lines[2]}" = "step" ]
	[ "${lines[3]}" = "whole" ]
	[ "${#lines[@]}" -eq 4 ]
}

@test "a draft for one branch does not affect another branch's offers" {
	git review walkthrough draft feature/plain
	run offers_for feature/annotated
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "walk" ]
	[ "${lines[1]}" = "keys" ]
	[ "${#lines[@]}" -eq 4 ]
}
