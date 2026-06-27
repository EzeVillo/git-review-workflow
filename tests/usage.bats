#!/usr/bin/env bats
#
# Usage / argument-parsing tests for every subcommand. These exercise the paths
# that run before any git state is touched: --h / -h, unknown options and
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

# ── --h / -h prints usage and exits 0 ──────────────────────────────────────

@test "review start --h prints usage and exits 0" {
	run git review start --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review start"* ]]
}

@test "review start -h prints usage and exits 0" {
	run git review start -h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review start"* ]]
}

@test "review next --h prints usage and exits 0" {
	run git review next --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review next"* ]]
}

@test "review prev --h prints usage and exits 0" {
	run git review prev --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review prev"* ]]
}

@test "review status --h prints usage and exits 0" {
	run git review status --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review status"* ]]
}

@test "review preview --h prints usage and exits 0" {
	run git review preview --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review preview"* ]]
}

@test "review list --h prints usage and exits 0" {
	run git review list --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review list"* ]]
}

@test "review save --h prints usage and exits 0" {
	run git review save --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review save"* ]]
}

@test "review continue --h prints usage and exits 0" {
	run git review continue --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review continue"* ]]
}

@test "review abort --h prints usage and exits 0" {
	run git review abort --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review abort"* ]]
}

@test "review finish --h prints usage and exits 0" {
	run git review finish --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review finish"* ]]
}

@test "review clean --h prints usage and exits 0" {
	run git review clean --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review clean"* ]]
}

@test "review forget --delta --h prints usage and exits 0" {
	run git review forget --delta --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review forget"* ]]
}

@test "review forget --saved --h prints usage and exits 0" {
	run git review forget --saved --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review forget"* ]]
}

# ── unknown options / unexpected arguments ────────────────────────────────────

@test "review start with no branch is accepted and proceeds to the git-repo check" {
	# No <branch> now means the current branch, so the parser no longer rejects it
	# up front. In this non-repo scratch dir it gets as far as the git-repo check,
	# proving the omitted branch is a valid invocation, not a usage error.
	run git review start
	[ "$status" -ne 0 ]
	[[ "$output" == *"not a git repository"* ]]
	[[ "$output" != *"usage: git review start"* ]]
}

@test "review start rejects an unknown option" {
	run git review start --bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unknown option --bogus"* ]]
}

@test "review start rejects a third positional argument" {
	run git review start feature/x develop extra
	[ "$status" -ne 0 ]
	[[ "$output" == *"unexpected argument extra"* ]]
}

@test "review start --from without a commit fails" {
	run git review start feature/x --from
	[ "$status" -ne 0 ]
	[[ "$output" == *"--from requires a commit"* ]]
}

@test "review next rejects an unexpected argument" {
	run git review next bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unexpected argument bogus"* ]]
}

@test "review next rejects a dash-leading argument" {
	run git review next --foo
	[ "$status" -ne 0 ]
	[[ "$output" == *"unexpected argument --foo"* ]]
}

@test "review prev rejects an unexpected argument" {
	run git review prev bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unexpected argument bogus"* ]]
}

@test "review status rejects an unexpected argument" {
	run git review status bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unexpected argument bogus"* ]]
}

@test "review preview rejects an unexpected argument" {
	run git review preview bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unexpected argument bogus"* ]]
}

@test "review abort rejects an unexpected argument" {
	run git review abort bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unexpected argument bogus"* ]]
}

@test "review save rejects an unexpected argument" {
	run git review save bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unexpected argument bogus"* ]]
}

@test "review continue rejects an unknown option" {
	run git review continue --bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unknown option --bogus"* ]]
}

@test "review finish rejects an unknown option" {
	run git review finish --bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unknown option --bogus"* ]]
}

@test "review clean rejects an unknown option" {
	run git review clean --bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unknown option --bogus"* ]]
}

@test "review clean rejects a second positional argument" {
	run git review clean feature/x extra
	[ "$status" -eq 1 ]
	[[ "$output" == *"unexpected argument extra"* ]]
}

@test "review forget --delta rejects an unknown option" {
	run git review forget --delta --bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unknown option --bogus"* ]]
}

@test "review forget --delta with no target prints usage and exits 1" {
	run git review forget --delta
	[ "$status" -eq 1 ]
	[[ "$output" == *"usage: git review forget"* ]]
}

@test "review forget --saved rejects an unknown option" {
	run git review forget --saved --bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unknown option --bogus"* ]]
}

@test "review forget --saved with no target prints usage and exits 1" {
	run git review forget --saved
	[ "$status" -eq 1 ]
	[[ "$output" == *"usage: git review forget"* ]]
}
