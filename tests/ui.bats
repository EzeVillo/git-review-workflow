#!/usr/bin/env bats
#
# Tests for `git review ui`: the handoff to the (separately installed)
# git-review-ui terminal UI. Covers resolution order ($GIT_REVIEW_UI before
# PATH), that it execs rather than forking (signals/exit code reach the
# caller unmodified), that it never confuses $GIT_REVIEW_UI (a path) with the
# installer's opt-in flag GIT_REVIEW_WITH_UI=1 (not a path), and the
# per-platform install hint printed when nothing is found.

bats_require_minimum_version 1.5.0

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	ORIGPATH="$PATH"
	unset GIT_REVIEW_UI
	unset GIT_REVIEW_WITH_UI
}

teardown() {
	rm -rf "$TMP"
}

# Directories whose real PATH entry holds a literal `brew` file/executable,
# dropped. Used to build a "Linux, no brew" PATH that stays true regardless of
# whether the host actually has Homebrew (a GitHub-hosted macOS or Linux
# runner might).
path_without_real_brew() {
	result=""
	oldifs="$IFS"
	IFS=:
	for d in $ORIGPATH; do
		if [ -n "$d" ] && [ ! -e "$d/brew" ]; then
			result="$result:$d"
		fi
	done
	IFS="$oldifs"
	printf '%s\n' "${result#:}"
}

# ── absence: no $GIT_REVIEW_UI, nothing named git-review-ui on PATH ───────────

@test "review ui refuses when the tui is absent and never invokes anything" {
	# A real executable named git-review-ui exists on disk, but its directory is
	# never added to PATH: if the verb ever invoked it (a stray fallback, a `.`
	# on PATH, anything not the documented resolution order) this marker would
	# appear.
	mkdir -p "$TMP/offpath"
	MARKER="$TMP/invoked"
	cat > "$TMP/offpath/git-review-ui" << EOF
#!/bin/sh
echo invoked > "$MARKER"
exit 0
EOF
	chmod +x "$TMP/offpath/git-review-ui"

	export PATH="$REPO/bin:$ORIGPATH"
	run --separate-stderr git review ui
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[[ "$stderr" == "error: the git review terminal UI (git-review-ui) is not installed."* ]]
	[[ "$stderr" != *npm* ]]
	[ ! -f "$MARKER" ]
}

@test "review ui still refuses when GIT_REVIEW_WITH_UI is set without GIT_REVIEW_UI" {
	# GIT_REVIEW_WITH_UI=1 is the installer's opt-in flag, not a path. Left
	# exported (e.g. from a shell that ran the one-liner installer), it must
	# never be read as $GIT_REVIEW_UI and handed to exec — that was the exact
	# bug this pair of tests locks down (T009).
	export GIT_REVIEW_WITH_UI=1
	export PATH="$REPO/bin:$ORIGPATH"
	run --separate-stderr git review ui
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[[ "$stderr" == "error: the git review terminal UI (git-review-ui) is not installed."* ]]
	# Not a shell-level exec failure (which a literal `exec 1` would produce):
	# only our own hint reached stderr.
	[[ "$stderr" != *"exec"* ]]
}

# ── resolution order: $GIT_REVIEW_UI beats PATH ───────────────────────────────

@test "review ui prefers GIT_REVIEW_UI over a git-review-ui found on PATH" {
	mkdir -p "$TMP/pathbin" "$TMP/direct"
	PATH_MARKER="$TMP/path-invoked"
	DIRECT_MARKER="$TMP/direct-invoked"

	cat > "$TMP/pathbin/git-review-ui" << EOF
#!/bin/sh
echo invoked > "$PATH_MARKER"
exit 13
EOF
	chmod +x "$TMP/pathbin/git-review-ui"

	cat > "$TMP/direct/fake-ui" << EOF
#!/bin/sh
echo invoked > "$DIRECT_MARKER"
exit 42
EOF
	chmod +x "$TMP/direct/fake-ui"

	export GIT_REVIEW_UI="$TMP/direct/fake-ui"
	export PATH="$REPO/bin:$TMP/pathbin:$ORIGPATH"
	run git review ui
	[ "$status" -eq 42 ]
	[ -f "$DIRECT_MARKER" ]
	[ ! -f "$PATH_MARKER" ]
}

# ── exec semantics: the fake's exit code and its arguments both arrive ────────

@test "review ui execs a git-review-ui on PATH and its exit code reaches the caller" {
	mkdir -p "$TMP/pathbin"
	MARKER="$TMP/args-seen"
	cat > "$TMP/pathbin/git-review-ui" << EOF
#!/bin/sh
printf '%s\n' "\$@" > "$MARKER"
exit 7
EOF
	chmod +x "$TMP/pathbin/git-review-ui"

	export PATH="$REPO/bin:$TMP/pathbin:$ORIGPATH"
	run git review ui foo bar
	[ "$status" -eq 7 ]
	[ -f "$MARKER" ]
	[ "$(cat "$MARKER")" = "$(printf 'foo\nbar')" ]
}

# ── -h: the verb's own usage, without resolving the tui at all ───────────────

@test "review ui -h prints usage and exits 0 without resolving the tui" {
	mkdir -p "$TMP/decoy"
	MARKER="$TMP/decoy-invoked"
	cat > "$TMP/decoy/git-review-ui" << EOF
#!/bin/sh
echo invoked > "$MARKER"
exit 99
EOF
	chmod +x "$TMP/decoy/git-review-ui"

	# Even $GIT_REVIEW_UI itself points at a (different) decoy: -h must win
	# before either resolution step runs.
	cat > "$TMP/decoy/direct-ui" << EOF
#!/bin/sh
echo invoked > "$MARKER"
exit 98
EOF
	chmod +x "$TMP/decoy/direct-ui"

	export GIT_REVIEW_UI="$TMP/decoy/direct-ui"
	export PATH="$REPO/bin:$TMP/decoy:$ORIGPATH"
	run git review ui -h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review ui"* ]]
	[ ! -f "$MARKER" ]
}

# ── the per-platform install hint (FR-081), uname/brew stubbed ───────────────

@test "review ui hint on macOS points at brew install from the project tap" {
	mkdir -p "$TMP/mockbin"
	cat > "$TMP/mockbin/uname" << 'EOF'
#!/bin/sh
echo Darwin
EOF
	chmod +x "$TMP/mockbin/uname"

	export PATH="$TMP/mockbin:$REPO/bin:$ORIGPATH"
	run --separate-stderr git review ui
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"brew install EzeVillo/git-review-workflow/git-review-ui"* ]]
	[[ "$stderr" != *npm* ]]
}

@test "review ui hint on Linux with brew on PATH points at brew install" {
	mkdir -p "$TMP/mockbin"
	cat > "$TMP/mockbin/uname" << 'EOF'
#!/bin/sh
echo Linux
EOF
	chmod +x "$TMP/mockbin/uname"
	cat > "$TMP/mockbin/brew" << 'EOF'
#!/bin/sh
exit 0
EOF
	chmod +x "$TMP/mockbin/brew"

	export PATH="$TMP/mockbin:$REPO/bin:$ORIGPATH"
	run --separate-stderr git review ui
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"brew install EzeVillo/git-review-workflow/git-review-ui"* ]]
	[[ "$stderr" != *npm* ]]
}

@test "review ui hint on Linux without brew points at web-install.sh with its flag" {
	mkdir -p "$TMP/mockbin"
	cat > "$TMP/mockbin/uname" << 'EOF'
#!/bin/sh
echo Linux
EOF
	chmod +x "$TMP/mockbin/uname"

	# A PATH built from scratch: our mock uname, the dispatcher, and the real
	# PATH with every directory that holds a real `brew` removed — true "no
	# brew" regardless of whether this host (e.g. a GitHub-hosted runner) has
	# Homebrew installed.
	export PATH="$TMP/mockbin:$REPO/bin:$(path_without_real_brew)"
	run --separate-stderr git review ui
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"curl -fsSL https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-install.sh | GIT_REVIEW_WITH_UI=1 sh"* ]]
	[[ "$stderr" != *"brew install"* ]]
	[[ "$stderr" != *npm* ]]
}

@test "review ui hint on Windows points at web-install.ps1 -WithUi" {
	mkdir -p "$TMP/mockbin"
	cat > "$TMP/mockbin/uname" << 'EOF'
#!/bin/sh
echo MINGW64_NT-10.0-19045
EOF
	chmod +x "$TMP/mockbin/uname"

	export PATH="$TMP/mockbin:$REPO/bin:$ORIGPATH"
	run --separate-stderr git review ui
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"web-install.ps1"* ]]
	[[ "$stderr" == *"-WithUi"* ]]
	[[ "$stderr" != *"brew install"* ]]
	[[ "$stderr" != *npm* ]]
}

@test "review ui hint on an unmatched platform points at the releases page" {
	mkdir -p "$TMP/mockbin"
	cat > "$TMP/mockbin/uname" << 'EOF'
#!/bin/sh
echo SunOS
EOF
	chmod +x "$TMP/mockbin/uname"

	export PATH="$TMP/mockbin:$REPO/bin:$ORIGPATH"
	run --separate-stderr git review ui
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"https://github.com/EzeVillo/git-review-workflow/releases"* ]]
	[[ "$stderr" != *"brew install"* ]]
	[[ "$stderr" != *"web-install"* ]]
	[[ "$stderr" != *npm* ]]
}
