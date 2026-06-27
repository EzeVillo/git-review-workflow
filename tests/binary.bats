#!/usr/bin/env bats
#
# Tests for review edits that touch *binary* files.
#
# Regression for a class of bug where the patch was captured in a shell variable
# (command substitution) and replayed with `printf | git apply`. Command
# substitution strips NUL bytes and the trailing newline, so a binary hunk came
# out corrupt — git apply then rejected it ("corrupt binary patch"). review finish
# failed outright; review save → review continue silently *lost* the binary edit.
# The fix routes every patch through a pipe or a temp file, never a variable.
#
# Each test compares the extracted/restored blob against the original by object
# id (git hash-object), so a single dropped or altered byte fails the assert —
# there are no substring approximations on binary content.
#
# Fixture: develop carries a committed binary (logo.bin); feature/x adds two
# commits (a.txt, then note.txt) so the same suite covers whole and step mode.

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

	printf 'a1\n' >a.txt
	write_bin logo.bin base
	git add a.txt logo.bin
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop

	git switch --quiet -c feature/x
	printf 'a1\na2\n' >a.txt
	git add a.txt
	git commit --quiet -m c1-touch-a
	printf 'n\n' >note.txt
	git add note.txt
	git commit --quiet -m c2-touch-note
	git push --quiet -u origin feature/x

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

# write_bin <path> <salt>: write bytes that include a NUL, high bytes and no
# trailing newline — exactly the content command substitution used to mangle.
# The salt makes distinct files distinguishable by content.
write_bin() {
	printf 'PNG\000\001\002\377\376\200\177%s\000\n\rTAIL' "$2" >"$1"
}

# ── whole-PR mode ─────────────────────────────────────────────────────────────

@test "finish (whole) extracts a newly added binary file byte-for-byte" {
	git review start feature/x develop
	write_bin img.bin add
	orig="$(git hash-object img.bin)"

	run git review finish
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	# the file is staged as an addition...
	run git diff --cached --name-only
	[[ "$output" == *"img.bin"* ]]
	# ...and the staged blob is identical to the edit, to the byte
	[ "$(git rev-parse ':img.bin')" = "$orig" ]
}

@test "finish --onto-source (whole) extracts a binary file byte-for-byte" {
	git review start feature/x develop
	write_bin img.bin add
	orig="$(git hash-object img.bin)"

	run git review finish --onto-source
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "feature/x" ]
	[ "$(git rev-parse ':img.bin')" = "$orig" ]
}

@test "finish (whole) extracts a *modification* of an existing binary file" {
	git review start feature/x develop
	# logo.bin already exists in the PR tree; overwrite it with new bytes
	write_bin logo.bin EDITED
	new="$(git hash-object logo.bin)"
	# guard the test itself: the edit must actually change the blob
	[ "$new" != "$(git rev-parse 'feature/x:logo.bin')" ]

	run git review finish
	[ "$status" -eq 0 ]
	run git diff --cached --name-only
	[[ "$output" == *"logo.bin"* ]]
	[ "$(git rev-parse ':logo.bin')" = "$new" ]
}

@test "save -> continue (whole) restores a binary edit, then finish extracts it" {
	git review start feature/x develop
	write_bin img.bin saved
	orig="$(git hash-object img.bin)"

	git review save
	run git review continue feature/x
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	# the binary edit is back in the working tree, byte-identical (this is the
	# regression: it used to vanish on resume)
	[ -f img.bin ]
	[ "$(git hash-object img.bin)" = "$orig" ]

	# and it survives all the way through finish
	run git review finish
	[ "$status" -eq 0 ]
	[ "$(git rev-parse ':img.bin')" = "$orig" ]
}

# ── step mode ─────────────────────────────────────────────────────────────────

@test "finish (step) replays a binary edit banked on an earlier commit" {
	git review start feature/x --step
	write_bin img.bin step1
	orig="$(git hash-object img.bin)"
	git review next                 # bank step 1 (the binary), move to step 2

	run git review finish
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	[ "$(git rev-parse ':img.bin')" = "$orig" ]
}

@test "step navigation banks and restores a binary edit unchanged" {
	git review start feature/x --step
	write_bin img.bin nav
	orig="$(git hash-object img.bin)"
	git review next                 # bank step 1
	run git review prev             # back to step 1 — the binary must come back
	[ "$status" -eq 0 ]
	[ -f img.bin ]
	[ "$(git hash-object img.bin)" = "$orig" ]
}

@test "preview (step) shows a banked binary edit instead of dropping it" {
	git review start feature/x --step
	write_bin img.bin prev
	size="$(wc -c <img.bin | tr -d ' ')"
	git review next                 # bank step 1, now on step 2

	run git review preview --stat
	[ "$status" -eq 0 ]
	# the binary edit is present in the preview...
	[[ "$output" == *"img.bin"* ]]
	[[ "$output" == *"Bin "* ]]
	[[ "$output" == *"$size bytes"* ]]
	# ...not omitted as an unappliable overlap (the pre-fix failure mode)
	[[ "$output" != *"overlap"* ]]
}
