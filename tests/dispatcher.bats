#!/usr/bin/env bats
#
# Tests for git-review — the entry-point dispatcher (--h / --version).

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
	VERSION="$(cat "$REPO/VERSION")"
	export PATH="$REPO/bin:$PATH"
}

# ── --h / -h / no arguments ────────────────────────────────────────────────

@test "git-review: no arguments prints help and exits 0" {
	run git-review
	[ "$status" -eq 0 ]
	[[ "$output" == *"git review workflow"* ]]
}

@test "git-review: --h prints help and exits 0" {
	run git-review --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"git review workflow"* ]]
}

@test "git-review: -h prints help and exits 0" {
	run git-review -h
	[ "$status" -eq 0 ]
	[[ "$output" == *"git review workflow"* ]]
}

@test "git-review: --h lists all subcommands" {
	run git-review --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"git review-pr"* ]]
	[[ "$output" == *"git review-next"* ]]
	[[ "$output" == *"git review-prev"* ]]
	[[ "$output" == *"git review-status"* ]]
	[[ "$output" == *"git review-list"* ]]
	[[ "$output" == *"git review-save"* ]]
	[[ "$output" == *"git review-continue"* ]]
	[[ "$output" == *"git review-abort"* ]]
	[[ "$output" == *"git finish-review"* ]]
	[[ "$output" == *"git clean-review"* ]]
	[[ "$output" == *"git review-forget-delta"* ]]
	[[ "$output" == *"git review-forget-saved"* ]]
}

# ── --version / -V ────────────────────────────────────────────────────────────

@test "git-review: --version prints the version and exits 0" {
	run git-review --version
	[ "$status" -eq 0 ]
	[ "$output" = "$VERSION" ]
}

@test "git-review: -V prints the version and exits 0" {
	run git-review -V
	[ "$status" -eq 0 ]
	[ "$output" = "$VERSION" ]
}

@test "git-review: --version output matches VERSION file" {
	run git-review --version
	[ "$status" -eq 0 ]
	[ "$output" = "$(cat "$REPO/VERSION")" ]
}

# ── unknown flags ─────────────────────────────────────────────────────────────

@test "git-review: unknown flag exits 1 with an error message" {
	run git-review --unknown
	[ "$status" -eq 1 ]
	[[ "$output" == *"error:"* ]]
}

@test "git-review: unknown flag also prints help on stderr" {
	run git-review --unknown
	[ "$status" -eq 1 ]
	[[ "$output" == *"git review workflow"* ]]
}
