#!/usr/bin/env bats
#
# Tests for web-install.ps1: the PowerShell network installer.
# Invoke-RestMethod and Invoke-WebRequest are mocked in the runner harness so
# tests run fully offline.  The suite is skipped when PowerShell is not found.

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	export REPO TMP
}

teardown() {
	rm -rf "$TMP"
}

# Locate pwsh/powershell and convert paths to Windows format when running under
# Git Bash (cygpath) so PowerShell can open the files.
_run_ps1_test() {
	local test_name="$1"
	local ps_exe
	ps_exe="$(command -v pwsh 2>/dev/null || command -v powershell 2>/dev/null || true)"
	[ -n "$ps_exe" ] || skip "PowerShell (pwsh) not available"

	local ps_tmp="$TMP" ps_repo="$REPO"
	if command -v cygpath >/dev/null 2>&1; then
		ps_tmp="$(cygpath -w "$TMP")"
		ps_repo="$(cygpath -w "$REPO")"
	fi

	"$ps_exe" -NonInteractive -NoProfile -File \
		"$BATS_TEST_DIRNAME/helpers/web_install_ps1_runner.ps1" \
		-TestName "$test_name" \
		-RepoPath "$ps_repo" \
		-TestTmpDir "$ps_tmp"
}

@test "web-install.ps1 installs all commands into PREFIX" {
	run _run_ps1_test "install_all_commands"
	[ "$status" -eq 0 ]
}

@test "web-install.ps1: REF env var skips the releases/latest API call" {
	run _run_ps1_test "ref_skips_api"
	[ "$status" -eq 0 ]
}
