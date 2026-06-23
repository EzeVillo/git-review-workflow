#!/usr/bin/env bats
#
# Tests for web-uninstall.sh: the one-line Unix uninstaller.
#
# These are written to avoid false positives: every removal test first asserts
# the files are present, so an uninstaller that silently did nothing would fail
# rather than pass. They also assert the uninstaller does not delete unrelated
# files that happen to share the install directory.

CMDS="git-review git-review-pr git-review-next git-review-prev git-review-status git-review-list git-review-save git-review-continue git-review-abort git-finish-review git-clean-review git-review-forget-delta git-review-forget-saved"

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PREFIX="$TMP/bin"
	REPO="$BATS_TEST_DIRNAME/.."
	mkdir -p "$PREFIX"
}

teardown() {
	rm -rf "$TMP"
}

# Populate PREFIX with real command files, exactly as an install would.
_install_commands() {
	for f in "$REPO"/bin/git-*; do
		cp "$f" "$PREFIX/$(basename "$f")"
		chmod +x "$PREFIX/$(basename "$f")"
	done
}

@test "web-uninstall.sh removes every installed command" {
	_install_commands
	# Guard against a false positive: the files must really be there first.
	for c in $CMDS; do
		[ -e "$PREFIX/$c" ]
	done

	run sh "$REPO/web-uninstall.sh"
	[ "$status" -eq 0 ]

	for c in $CMDS; do
		[ ! -e "$PREFIX/$c" ]
	done
}

@test "web-uninstall.sh reports each command it removed" {
	_install_commands
	run sh "$REPO/web-uninstall.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Removed git review commands"* ]]
	for c in $CMDS; do
		[[ "$output" == *"$c"* ]]
	done
}

@test "web-uninstall.sh leaves unrelated files in the install dir untouched" {
	_install_commands
	# Files that are not ours, including one that shares the git- prefix but is
	# not in our command list — a naive glob would wrongly delete it.
	printf 'keep me\n' > "$PREFIX/unrelated.txt"
	printf '#!/bin/sh\n' > "$PREFIX/git-other-tool"
	chmod +x "$PREFIX/git-other-tool"

	run sh "$REPO/web-uninstall.sh"
	[ "$status" -eq 0 ]

	[ -e "$PREFIX/unrelated.txt" ]
	[ -e "$PREFIX/git-other-tool" ]
	[ "$(cat "$PREFIX/unrelated.txt")" = "keep me" ]
}

@test "web-uninstall.sh honors PREFIX and ignores a different dir" {
	other="$TMP/other"
	mkdir -p "$other"
	cp "$REPO/bin/git-review" "$other/git-review"
	_install_commands

	run sh "$REPO/web-uninstall.sh"
	[ "$status" -eq 0 ]

	# Removed from PREFIX, but the copy in an unrelated dir is left alone.
	[ ! -e "$PREFIX/git-review" ]
	[ -e "$other/git-review" ]
}

@test "web-uninstall.sh succeeds and says nothing to remove on a clean dir" {
	run sh "$REPO/web-uninstall.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"nothing to remove"* ]]
}

@test "web-uninstall.sh is idempotent: a second run is a clean no-op" {
	_install_commands
	run sh "$REPO/web-uninstall.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Removed git review commands"* ]]

	run sh "$REPO/web-uninstall.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"nothing to remove"* ]]
}

@test "web-uninstall.sh undoes a web-install.sh install" {
	# True round-trip against the real installer (curl stubbed, offline).
	ARC_DIR="$TMP/arc/git-review-workflow-v0.0.1"
	mkdir -p "$ARC_DIR/bin"
	for f in "$REPO"/bin/git-*; do
		cp "$f" "$ARC_DIR/bin/"
	done
	FAKE_TARBALL="$TMP/release.tar.gz"
	tar -czf "$FAKE_TARBALL" -C "$TMP/arc" git-review-workflow-v0.0.1
	export FAKE_TARBALL

	MOCK_BIN="$TMP/mock-bin"
	mkdir -p "$MOCK_BIN"
	cat > "$MOCK_BIN/curl" << 'CURLSTUB'
#!/bin/sh
url=""
while [ $# -gt 0 ]; do
	case "$1" in -*) shift ;; *) url="$1"; shift ;; esac
done
case "$url" in
	*/releases/latest) printf '{"tag_name":"v0.0.1"}\n' ;;
	*.tar.gz)          cat "$FAKE_TARBALL" ;;
	*)                 printf '{}' ;;
esac
CURLSTUB
	chmod +x "$MOCK_BIN/curl"
	export PATH="$MOCK_BIN:$PATH"

	# Use `run` so bats closes FD 3 for the installer; otherwise the spawned
	# `curl | tar` pipeline can inherit it and, on slower process teardown
	# (Windows), leave it open long enough for bats to undercount the suite.
	run sh "$REPO/web-install.sh"
	[ "$status" -eq 0 ]
	[ -e "$PREFIX/git-review-pr" ]   # installed for real before we remove it

	run sh "$REPO/web-uninstall.sh"
	[ "$status" -eq 0 ]
	for c in $CMDS; do
		[ ! -e "$PREFIX/$c" ]
	done
}
