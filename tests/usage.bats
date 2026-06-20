#!/usr/bin/env bats
#
# Usage / argument-parsing tests for every subcommand. These exercise the paths
# that run before any git state is touched: --help / -h, unknown options and
# unexpected positional arguments. They need only the bin/ directory on PATH.

setup() {
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"
	# A scratch cwd so nothing here depends on the repo under test.
	TMP="$(mktemp -d)"
	cd "$TMP"
}

teardown() {
	rm -rf "$TMP"
}

# ── --help / -h prints usage and exits 0 ──────────────────────────────────────

@test "review-pr --help prints usage and exits 0" {
	run git-review-pr --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review-pr"* ]]
}

@test "review-pr -h prints usage and exits 0" {
	run git-review-pr -h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review-pr"* ]]
}

@test "review-next --help prints usage and exits 0" {
	run git-review-next --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review-next"* ]]
}

@test "review-prev --help prints usage and exits 0" {
	run git-review-prev --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review-prev"* ]]
}

@test "review-status --help prints usage and exits 0" {
	run git-review-status --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review-status"* ]]
}

@test "review-list --help prints usage and exits 0" {
	run git-review-list --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review-list"* ]]
}

@test "review-abort --help prints usage and exits 0" {
	run git-review-abort --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review-abort"* ]]
}

@test "finish-review --help prints usage and exits 0" {
	run git-finish-review --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git finish-review"* ]]
}

@test "clean-review --help prints usage and exits 0" {
	run git-clean-review --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git clean-review"* ]]
}

@test "review-forget --help prints usage and exits 0" {
	run git-review-forget --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review-forget"* ]]
}

# ── unknown options / unexpected arguments ────────────────────────────────────

@test "review-pr with no branch prints usage and exits 1" {
	run git-review-pr
	[ "$status" -eq 1 ]
	[[ "$output" == *"usage: git review-pr"* ]]
}

@test "review-pr rejects an unknown option" {
	run git-review-pr --bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unknown option --bogus"* ]]
}

@test "review-pr rejects a third positional argument" {
	run git-review-pr feature/x develop extra
	[ "$status" -ne 0 ]
	[[ "$output" == *"unexpected argument extra"* ]]
}

@test "review-pr --from without a commit fails" {
	run git-review-pr feature/x --from
	[ "$status" -ne 0 ]
	[[ "$output" == *"--from requires a commit"* ]]
}

@test "review-next rejects an unexpected argument" {
	run git-review-next bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unexpected argument bogus"* ]]
}

@test "review-prev rejects an unexpected argument" {
	run git-review-prev bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unexpected argument bogus"* ]]
}

@test "review-status rejects an unexpected argument" {
	run git-review-status bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unexpected argument bogus"* ]]
}

@test "review-abort rejects an unexpected argument" {
	run git-review-abort bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unexpected argument bogus"* ]]
}

@test "finish-review rejects an unknown option" {
	run git-finish-review --bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unknown option --bogus"* ]]
}

@test "clean-review rejects an unknown option" {
	run git-clean-review --bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unknown option --bogus"* ]]
}

@test "clean-review rejects a second positional argument" {
	run git-clean-review feature/x extra
	[ "$status" -eq 1 ]
	[[ "$output" == *"unexpected argument extra"* ]]
}

@test "review-forget rejects an unknown option" {
	run git-review-forget --bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unknown option --bogus"* ]]
}

@test "review-forget with no target prints usage and exits 1" {
	run git-review-forget
	[ "$status" -eq 1 ]
	[[ "$output" == *"usage: git review-forget"* ]]
}
