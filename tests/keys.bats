#!/usr/bin/env bats
#
# Tests for walk keys-only submode: git review start/compare --keys, next/prev,
# porcelain, save/continue, finish/abort, and rejection paths.
#

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
	# Two keys (c, a); b is annotated but not key. Sidecar is uncovered in full walk.
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## Heads-up
something delicate

## 1. src/c.txt
> key
read the new helper first

## 2. a.txt
> key
then the a change

## 3. b.txt
finally b (not essential)
EOF
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough
	git push --quiet -u origin feature/x

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

# ── start --keys ──────────────────────────────────────────────────────────────

@test "start --keys enters walk with only key entries" {
	run git review start feature/x --keys
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	[ "$(git config branch.review/feature/x.reviewwalkkeys)" = "1" ]
	[ "$(git config branch.review/feature/x.reviewwalkcount)" = "2" ]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "1" ]
	[[ "$output" == *"keys-only"* ]]
	[[ "$output" == *"[1/2] src/c.txt  (key)"* ]]
	# Full PR still staged.
	run git diff --cached --name-only
	[[ "$output" == *"a.txt"* ]]
	[[ "$output" == *"b.txt"* ]]
	[[ "$output" == *"src/c.txt"* ]]
}

@test "next and prev stay on keys only" {
	git review start feature/x --keys >/dev/null
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/2] a.txt  (key)"* ]]
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"no more entries"* ]]
	# Still on last key; never landed on b.txt or the sidecar.
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/2] on a.txt"* ]]
	[[ "$output" == *"keys-only"* ]]
	[[ "$output" != *"b.txt"* ]]
	run git review prev
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/2] src/c.txt  (key)"* ]]
}

@test "status --porcelain emits keys record and only essential entries" {
	git review start feature/x --keys >/dev/null
	run git review status --porcelain
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -qx 'keys'
	state="$(printf '%s\n' "$output" | grep '^state')"
	# position total recorded current essential — total/recorded = 2
	[[ "$state" == *$'\twalk\tapplied\t1\t2\t2\tsrc/c.txt\t1' ]]
	entries="$(printf '%s\n' "$output" | grep '^entry')"
	expected="$(printf 'entry\t1\tsrc/c.txt\t1\t1\nentry\t2\ta.txt\t1\t1')"
	[ "$entries" = "$expected" ]
	# No b.txt, no walkthrough sidecar.
	! printf '%s\n' "$output" | grep -q 'b.txt'
	! printf '%s\n' "$output" | grep -q 'walkthrough.md'
}

@test "start --keys with --step is rejected without creating a review branch" {
	run git review start feature/x --keys --step
	[ "$status" -ne 0 ]
	[[ "$output" == *"--keys cannot be combined with --step"* ]]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "start --keys with --no-walk is rejected without creating a review branch" {
	run git review start feature/x --keys --no-walk
	[ "$status" -ne 0 ]
	[[ "$output" == *"--keys cannot be combined with --no-walk"* ]]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "start --keys with zero keys fails without creating a review branch" {
	# Replace walkthrough with no > key markers.
	git switch --quiet feature/x
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. src/c.txt
no key here

## 2. a.txt
still none

## 3. b.txt
nor here
EOF
	git add .review/walkthrough.md
	git commit --quiet -m no-keys
	git push --quiet origin feature/x
	git switch --quiet develop

	run git review start feature/x --keys
	[ "$status" -ne 0 ]
	[[ "$output" == *"--keys requires at least one walkthrough entry marked > key"* ]]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "start --keys without a walkthrough fails without creating a review branch" {
	git switch --quiet feature/x
	# New branch tip without walkthrough: amend by removing sidecar on a fork.
	git switch --quiet -c feature/nowt
	git rm -q -r .review
	git commit --quiet -m drop-wt
	git push --quiet -u origin feature/nowt
	git switch --quiet develop

	run git review start feature/nowt --keys
	[ "$status" -ne 0 ]
	[[ "$output" == *"--keys requires a walkthrough"* ]]
	run git rev-parse --verify --quiet refs/heads/review/feature/nowt
	[ "$status" -ne 0 ]
}

@test "compare --keys sets keys and readonly" {
	git fetch --quiet origin feature/x:feature/x
	run git review compare develop feature/x --keys
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewwalkkeys)" = "1" ]
	[ "$(git config branch.review/feature/x.reviewreadonly)" = "1" ]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -qx 'keys'
	printf '%s\n' "$output" | grep -qx 'readonly'
	entries="$(printf '%s\n' "$output" | grep '^entry' | wc -l | tr -d ' ')"
	[ "$entries" = "2" ]
}

# ── save / continue / finish / abort / preview ────────────────────────────────

@test "save then continue restores keys-only cursor" {
	git review start feature/x --keys >/dev/null
	git review next >/dev/null
	printf 'edit\n' >>a.txt
	run git review save
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" != "review/feature/x" ]
	run git review continue
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewwalkkeys)" = "1" ]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "2" ]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -qx 'keys'
	[[ "$(printf '%s\n' "$output" | grep '^state')" == *$'\t2\t2\t2\ta.txt\t1' ]]
	# Edit survived.
	grep -q 'edit' a.txt
}

@test "finish after keys-only extracts edits without requiring non-keys" {
	git review start feature/x --keys >/dev/null
	printf 'fix-line\n' >>src/c.txt
	run git review finish
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	run git diff --cached
	[[ "$output" == *"+fix-line"* ]]
}

@test "abort discards a keys-only review" {
	git review start feature/x --keys >/dev/null
	printf 'x\n' >>a.txt
	run git review abort
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "preview on keys-only does not change step or keys flag" {
	git review start feature/x --keys >/dev/null
	git review next >/dev/null
	printf 'p\n' >>a.txt
	run git review preview --stat
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewwalkkeys)" = "1" ]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "2" ]
}
