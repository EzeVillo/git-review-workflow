#!/usr/bin/env bats
#
# Tests for git review list, which shows every review/* branch in progress.

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"

	git config --global user.email t@example.com
	git config --global user.name tester
	git config --global init.defaultBranch develop

	ORIGIN="$TMP/origin.git"
	WORK="$TMP/work"
	git init --quiet --bare "$ORIGIN"
	git init --quiet "$WORK"
	cd "$WORK"
	git remote add origin "$ORIGIN"
	git config reviewworkflow.base develop

	printf 'a\n' >app.txt
	git add app.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop

	git switch --quiet -c feature/x
	printf 'a\nb\n' >app.txt
	git add app.txt
	git commit --quiet -m pr1
	git push --quiet -u origin feature/x

	git switch --quiet -c feature/y develop
	printf 'a\nc\n' >app.txt
	git add app.txt
	git commit --quiet -m pr1y
	git push --quiet -u origin feature/y

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

@test "review list reports no reviews when none exist" {
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"no reviews in progress"* ]]
}

@test "review list lists every review branch" {
	git review start feature/x
	# A whole review leaves a staged diff; clear it before starting another.
	git switch --quiet develop
	git reset --hard --quiet
	git review start feature/y --step
	git switch --quiet develop

	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"review/feature/x"* ]]
	[[ "$output" == *"whole"* ]]
	[[ "$output" == *"review/feature/y"* ]]
	[[ "$output" == *"step ["* ]]
}

@test "review list marks the current branch with an asterisk" {
	git review start feature/x
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"* review/feature/x"* ]]
}

@test "review list shows saved branches that lack metadata" {
	# An orphan saved branch (e.g. a review save that died before writing its
	# metadata) used to make review list print nothing at all: the "no reviews"
	# check sees a non-empty review-saved/* namespace, but describe() skipped the
	# branch for having no reviewsource.
	git branch review-saved/orphan develop
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"review-saved/orphan"* ]]
	[[ "$output" == *"(no metadata"* ]]
	# Recovery: forget --saved uses the source name (suffix), not the full ref.
	[[ "$output" == *"git review forget --saved orphan"* ]]
	[[ "$output" != *"no reviews in progress"* ]]
}

@test "review list still shows valid reviews alongside an orphan branch" {
	git review start feature/x
	git switch --quiet develop
	git branch review/orphan develop
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"review/feature/x"* ]]
	[[ "$output" == *"whole"* ]]
	[[ "$output" == *"review/orphan"* ]]
	[[ "$output" == *"(no metadata"* ]]
	# Active orphan: abort cannot run without reviewsource — point at branch -D.
	[[ "$output" == *"git branch -D review/orphan"* ]]
}

@test "review list rejects unexpected arguments" {
	run git review list bogus
	[ "$status" -ne 0 ]
	[[ "$output" == *"unexpected argument"* ]]
}

# ── list --porcelain (US6) ─────────────────────────────────────────────────────

@test "list --porcelain reports every branch with exact fields, including orphans and missing position" {
	git review start feature/x --step >/dev/null
	git switch --quiet develop
	git reset --hard --quiet
	git review start feature/y >/dev/null
	git switch --quiet develop
	git reset --hard --quiet

	git branch review/orphan develop
	git branch review-saved/gone develop

	# A branch with reviewsource but no persisted position/total: list --porcelain
	# must omit both fields, never emit "?" (contracts/list-porcelain.md).
	git branch review/partial develop
	git config branch.review/partial.reviewsource feature/x
	git config branch.review/partial.reviewmode step

	run git review list --porcelain
	[ "$status" -eq 0 ]

	x_line="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "branch" && $2 == "review/feature/x"')"
	[ "$x_line" = "$(printf 'branch\treview/feature/x\t0\t0\t0\tstep\t1\t1')" ]

	y_line="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "branch" && $2 == "review/feature/y"')"
	[ "$y_line" = "$(printf 'branch\treview/feature/y\t0\t0\t0\twhole')" ]

	orphan_line="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "branch" && $2 == "review/orphan"')"
	[ "$orphan_line" = "$(printf 'branch\treview/orphan\t0\t0\t1')" ]

	saved_line="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "branch" && $2 == "review-saved/gone"')"
	[ "$saved_line" = "$(printf 'branch\treview-saved/gone\t1\t0\t1')" ]

	partial_line="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "branch" && $2 == "review/partial"')"
	[ "$partial_line" = "$(printf 'branch\treview/partial\t0\t0\t0\tstep')" ]
	[[ "$partial_line" != *"?"* ]]
}

@test "list --porcelain reports zero lines and exit 0 with no reviews in the repository" {
	run git review list --porcelain
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}
