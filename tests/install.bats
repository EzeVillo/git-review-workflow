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
	# The dispatcher is the only command on PATH: every verb (start/status/list/
	# preview/next/prev/finish/save/continue/abort/clean/forget) lives under it as
	# libexec, not a standalone binary.
	CMDS="git-review"

	# install.sh chmods the repo's own bin/ files, which fails when the repo is
	# mounted read-only (e.g. the Docker test harness uses -v ...:ro). Skip there
	# rather than report a failure; the real CI runs writable and exercises these.
	chmod +x "$REPO"/bin/git-review 2>/dev/null ||
		skip "repo is read-only; install.sh cannot run here"
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
	# Exercises the dispatcher AND verb routing: the installed git-review must
	# resolve its libexec (via the symlink back to the repo) and run the verb.
	run "$PREFIX/git-review" start -h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review start"* ]]
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
