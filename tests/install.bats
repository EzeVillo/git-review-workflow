#!/usr/bin/env bats
#
# Smoke test for install.sh / uninstall.sh: every command is linked into PREFIX
# and runs, and uninstall removes them all.

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	REPO="$BATS_TEST_DIRNAME/.."
	export PREFIX="$TMP/bin"
	CMDS="git-review-pr git-review-next git-review-prev git-review-status git-review-list git-review-abort git-finish-review git-clean-review"
}

teardown() {
	rm -rf "$TMP"
}

@test "install.sh links every command into PREFIX" {
	run sh "$REPO/install.sh"
	[ "$status" -eq 0 ]
	for c in $CMDS; do
		[ -e "$PREFIX/$c" ]
		[ -x "$PREFIX/$c" ]
	done
}

@test "an installed command runs from PREFIX" {
	sh "$REPO/install.sh"
	run "$PREFIX/git-review-pr" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review-pr"* ]]
}

@test "uninstall.sh removes every command" {
	sh "$REPO/install.sh"
	run sh "$REPO/uninstall.sh"
	[ "$status" -eq 0 ]
	for c in $CMDS; do
		[ ! -e "$PREFIX/$c" ]
	done
}
