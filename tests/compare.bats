#!/usr/bin/env bats
#
# Tests for git review compare: a read-only review that stages the diff between
# two commit-ish (tags, branches, commits), with optional --step walking, and on
# which git review finish refuses because there is no writable source branch.
#
# The history below tags three points so compare can diff between them:
#   v1.0  (base)            app.txt = a\nb\nc
#   c1    touches app.txt   app.txt = a\nB\nc\nd
#   v2.0  touches more.txt  more.txt added
# So v1.0..v2.0 spans two commits (c1, then the v2.0 commit).

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"

	git config --global user.email t@example.com
	git config --global user.name tester
	git config --global init.defaultBranch develop

	WORK="$TMP/work"
	git init --quiet "$WORK"
	cd "$WORK"

	printf 'a\nb\nc\n' >app.txt
	git add app.txt
	git commit --quiet -m base
	git tag v1.0

	printf 'a\nB\nc\nd\n' >app.txt
	git add app.txt
	git commit --quiet -m c1-touch-app

	printf 'more\n' >more.txt
	git add more.txt
	git commit --quiet -m c2-add-more
	git tag v2.0

	# Land back on a normal branch so compare records a return point.
	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

@test "compare stages the diff between two tags, read-only, clean working tree" {
	run git review compare v1.0 v2.0
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/v2.0" ]
	[[ "$output" == *"read-only"* ]]

	# The staged diff is exactly v1.0..v2.0: both files changed since v1.0.
	run git diff --cached --name-only
	[[ "$output" == *"app.txt"* ]]
	[[ "$output" == *"more.txt"* ]]
	# Working tree is clean — nothing unstaged.
	run git diff --name-only
	[ -z "$output" ]
	# HEAD sits at the lower bound; the index holds the upper bound's tree.
	[ "$(git rev-parse HEAD)" = "$(git rev-parse v1.0^{commit})" ]

	# The read-only marker is recorded on the review branch.
	[ "$(git config branch.review/v2.0.reviewreadonly)" = "1" ]
}

@test "compare resolves arbitrary commit-ish and falls back to a short-hash branch name" {
	# <b> = HEAD~1 is not a valid ref component, so the branch is named after its
	# short hash instead of the literal "HEAD~1".
	short="$(git rev-parse --short "v2.0~1^{commit}")"
	run git review compare v1.0 HEAD~1
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/$short" ]
	# Only app.txt changed between v1.0 and the c1 commit.
	run git diff --cached --name-only
	[ "$output" = "app.txt" ]
}

@test "git review finish refuses on a read-only compare" {
	git review compare v1.0 v2.0
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"read-only"* ]]
	[[ "$output" == *"nothing to write back"* ]]
	# It refused before producing anything: no review-fixes branch was created.
	run git rev-parse --verify --quiet refs/heads/review-fixes/v2.0
	[ "$status" -ne 0 ]
	# Still on the review branch, untouched.
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/v2.0" ]
}

@test "compare --step starts on the first commit of the range" {
	run git review compare v1.0 v2.0 --step
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/v2.0" ]
	[[ "$output" == *"[1/2]"* ]]
	[[ "$output" == *"c1-touch-app"* ]]
	[ "$(git config branch.review/v2.0.reviewreadonly)" = "1" ]
	# First step stages c1's diff (app.txt); working tree clean.
	run git diff --cached --name-only
	[ "$output" = "app.txt" ]
	run git diff --name-only
	[ -z "$output" ]
}

@test "compare --step walks forward with git review next to the end" {
	git review compare v1.0 v2.0 --step
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/2]"* ]]
	[[ "$output" == *"c2-add-more"* ]]
	run git diff --cached --name-only
	[ "$output" = "more.txt" ]

	# Past the last commit, next reports the end (no writeback hint differs, but the
	# end-of-walk message is the same one start --step uses).
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"no more commits"* ]]
}

@test "compare --step walks back with git review prev" {
	git review compare v1.0 v2.0 --step
	git review next
	run git review prev
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/2]"* ]]
	[[ "$output" == *"c1-touch-app"* ]]
	run git diff --cached --name-only
	[ "$output" = "app.txt" ]
}

@test "git review finish refuses on a --step compare too" {
	git review compare v1.0 v2.0 --step
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"read-only"* ]]
	# No banked edits were extracted into a fixes branch.
	run git rev-parse --verify --quiet refs/heads/review-fixes/v2.0
	[ "$status" -ne 0 ]
}

@test "compare needs two commit-ish" {
	run git review compare v1.0
	[ "$status" -ne 0 ]
	[[ "$output" == *"two commit-ish"* ]]
	run git review compare
	[ "$status" -ne 0 ]
	[[ "$output" == *"two commit-ish"* ]]
}

@test "compare rejects an unknown commit-ish" {
	run git review compare v1.0 nope-no-such
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown commit: nope-no-such"* ]]
	# Nothing was created.
	run git rev-parse --verify --quiet refs/heads/review/nope-no-such
	[ "$status" -ne 0 ]
}

@test "compare refuses identical commit-ish" {
	run git review compare v2.0 v2.0
	[ "$status" -ne 0 ]
	[[ "$output" == *"same commit"* ]]
}

@test "compare refuses when a review branch already exists" {
	git review compare v1.0 v2.0
	git switch --quiet develop
	run git review compare v1.0 v2.0
	[ "$status" -ne 0 ]
	[[ "$output" == *"already exists"* ]]
}

@test "compare -h prints usage and exits 0" {
	run git review compare -h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review compare"* ]]
}

@test "compare accepts -- as the end-of-options separator" {
	run git review compare -- v1.0 v2.0
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/v2.0" ]
}
