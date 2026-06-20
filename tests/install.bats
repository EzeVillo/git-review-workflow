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
	CMDS="git-review-pr git-review-next git-review-prev git-review-status git-review-list git-review-abort git-finish-review git-clean-review git-review-forget"
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
	# Guard against a false positive: removal only means something if the links
	# were actually there to begin with.
	for c in $CMDS; do
		[ -e "$PREFIX/$c" ]
	done

	run sh "$REPO/uninstall.sh"
	[ "$status" -eq 0 ]
	for c in $CMDS; do
		[ ! -e "$PREFIX/$c" ]
	done
}

@test "uninstall.sh leaves unrelated files in PREFIX untouched" {
	sh "$REPO/install.sh"
	printf 'keep me\n' > "$PREFIX/unrelated.txt"
	printf '#!/bin/sh\n' > "$PREFIX/git-other-tool"

	run sh "$REPO/uninstall.sh"
	[ "$status" -eq 0 ]
	[ -e "$PREFIX/unrelated.txt" ]
	[ -e "$PREFIX/git-other-tool" ]
	[ "$(cat "$PREFIX/unrelated.txt")" = "keep me" ]
}
