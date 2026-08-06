#!/usr/bin/env bats
#
# Reading offers from git review config --porcelain (008-start-layout-offers).
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

	# feature/plain: changes, no walkthrough
	git switch --quiet -c feature/plain
	printf 'a1\na2\n' >a.txt
	git add a.txt
	git commit --quiet -m plain
	git push --quiet -u origin feature/plain

	# feature/walk: walkthrough, no keys
	git switch --quiet develop
	git switch --quiet -c feature/walk
	printf 'a1\na2\n' >a.txt
	printf 'b1\nb2\n' >b.txt
	git add a.txt b.txt
	git commit --quiet -m walk-files
	mkdir -p .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. a.txt
why a

## 2. b.txt
why b
EOF
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough
	git push --quiet -u origin feature/walk

	# feature/keys: walkthrough with keys
	git switch --quiet develop
	git switch --quiet -c feature/keys
	printf 'a1\na2\n' >a.txt
	printf 'b1\nb2\n' >b.txt
	mkdir -p src
	printf 'c\n' >src/c.txt
	git add a.txt b.txt src/c.txt
	git commit --quiet -m keys-files
	mkdir -p .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. src/c.txt
> key
key file

## 2. a.txt
> key
also key

## 3. b.txt
not key
EOF
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough-keys
	git push --quiet -u origin feature/keys

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

offer_lines() {
	printf '%s\n' "$output" | awk -F'\t' '$1=="offer" {print $2"\t"$3}'
}

@test "offers without walkthrough: step and whole available only" {
	run git review config --porcelain -- feature/plain
	[ "$status" -eq 0 ]
	[ "$(offer_lines)" = "$(printf 'step\tavailable\nwhole\tavailable')" ]
}

@test "offers with walkthrough no keys: walk recommended, no keys" {
	run git review config --porcelain -- feature/walk
	[ "$status" -eq 0 ]
	[ "$(offer_lines)" = "$(printf 'walk\trecommended\nstep\tavailable\nwhole\tavailable')" ]
}

@test "offers with keys: walk recommended plus keys available" {
	run git review config --porcelain -- feature/keys
	[ "$status" -eq 0 ]
	[ "$(offer_lines)" = "$(printf 'walk\trecommended\nkeys\tavailable\nstep\tavailable\nwhole\tavailable')" ]
}

@test "offers --local uses local tip" {
	# Remote tip keeps walkthrough; force local feature/walk to plain (no walk).
	git branch -f feature/walk origin/feature/plain
	run git review config --porcelain --local -- feature/walk
	[ "$status" -eq 0 ]
	[ "$(offer_lines)" = "$(printf 'step\tavailable\nwhole\tavailable')" ]
	run git review config --porcelain -- feature/walk
	[ "$status" -eq 0 ]
	[ "$(offer_lines)" = "$(printf 'walk\trecommended\nstep\tavailable\nwhole\tavailable')" ]
}

@test "offers --delta without marker fails" {
	run git review config --porcelain --delta -- feature/plain
	[ "$status" -ne 0 ]
	# diagnostic is on stderr; bats may not put it in $output — status is enough
}

@test "offers --delta with marker and no intersecting walk degrades to step+whole" {
	# First full review tip at keys tip; then add a commit with only non-key path
	# is hard. Simpler: record marker at current tip then add commits that are
	# only outside walkthrough paths... Use marker at tip of keys, push new
	# commit that only touches uncovered file so curated keys still apply.
	# Instead: marker after first commit of walk branch before walkthrough
	# landed — delta range may exclude walkthrough entries.
	git switch --quiet feature/keys
	# Parent of walkthrough commit has files but walkthrough is only on tip.
	# Marker at commit before walkthrough: range tip.. has walkthrough only as
	# new file - walk_sequence should still see entries for a,b,c in range.
	# Better stale case: walkthrough lists paths not in delta range.
	git switch --quiet develop
	git switch --quiet -c feature/stale
	printf 'x\n' >only.txt
	git add only.txt
	git commit --quiet -m only
	mkdir -p .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. missing.txt
> key
gone
EOF
	git add .review/walkthrough.md
	git commit --quiet -m wt-stale
	git push --quiet -u origin feature/stale
	# Delta from first commit: only walkthrough.md added; missing.txt not in range
	first="$(git rev-parse feature/stale^)"
	git config "reviewworkflow.feature/stale.reviewed" "$first"
	run git review config --porcelain --delta -- feature/stale
	[ "$status" -eq 0 ]
	# walk_sequence empty for missing path -> no walk/keys
	[ "$(offer_lines)" = "$(printf 'step\tavailable\nwhole\tavailable')" ]
}

@test "offers --local and --offline are mutually exclusive" {
	run git review config --porcelain --local --offline -- feature/plain
	[ "$status" -ne 0 ]
}

@test "offers without fetch: remote URL is unreachable but tracking ref exists" {
	# Point origin at a path that cannot be fetched, keep tracking ref.
	git remote set-url origin "$TMP/does-not-exist.git"
	run git review config --porcelain -- feature/keys
	[ "$status" -eq 0 ]
	[ "$(offer_lines)" = "$(printf 'walk\trecommended\nkeys\tavailable\nstep\tavailable\nwhole\tavailable')" ]
}

@test "offers --local missing branch fails hard" {
	run git review config --porcelain --local -- no-such-branch
	[ "$status" -ne 0 ]
}
