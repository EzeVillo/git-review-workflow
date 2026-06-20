#!/usr/bin/env bats
#
# Tests for web-uninstall.ps1: the PowerShell uninstaller. The suite is skipped
# when PowerShell is not found. Removal is checked against a real install dir,
# and PATH cleanup saves/restores the real user PATH so the machine is never
# left modified.

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
		"$BATS_TEST_DIRNAME/helpers/web_uninstall_ps1_runner.ps1" \
		-TestName "$test_name" \
		-RepoPath "$ps_repo" \
		-TestTmpDir "$ps_tmp"
}

@test "web-uninstall.ps1 removes every installed command" {
	run _run_ps1_test "remove_all_commands"
	[ "$status" -eq 0 ]
}

@test "web-uninstall.ps1 leaves unrelated files untouched" {
	run _run_ps1_test "keep_unrelated"
	[ "$status" -eq 0 ]
}

@test "web-uninstall.ps1 succeeds on a clean dir" {
	run _run_ps1_test "nothing_to_remove"
	[ "$status" -eq 0 ]
}

@test "web-uninstall.ps1 removes its dir from PATH and keeps the rest" {
	# The 'User' PATH scope is Windows-only; on Unix .NET treats it as a no-op
	# (Get returns null, Set is ignored), so there is nothing to assert there.
	case "$(uname -s)" in
		CYGWIN* | MINGW* | MSYS*) ;;
		*) skip "User PATH scope is Windows-only" ;;
	esac
	run _run_ps1_test "path_cleanup"
	[ "$status" -eq 0 ]
}

@test "web-uninstall.ps1 keeps PATH when the install dir is shared" {
	case "$(uname -s)" in
		CYGWIN* | MINGW* | MSYS*) ;;
		*) skip "User PATH scope is Windows-only" ;;
	esac
	run _run_ps1_test "path_kept_when_dir_shared"
	[ "$status" -eq 0 ]
}
