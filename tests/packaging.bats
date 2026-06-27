#!/usr/bin/env bats
#
# Structural tests for the Homebrew formula.
# These catch stale metadata (wrong version, missing files, broken field names)
# without requiring Homebrew to be installed.

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
	FORMULA="$REPO/Formula/git-review-workflow.rb"
	VERSION="$(cat "$REPO/VERSION")"
}

# ── Homebrew formula ──────────────────────────────────────────────────────────

@test "homebrew: formula version matches VERSION file" {
	grep -qE 'version "'"$VERSION"'"' "$FORMULA"
}

@test "homebrew: all bin files referenced in the formula exist and are executable" {
	# Top-level files the formula installs (the dispatcher and the sourced lib).
	for f in git-review git-review-lib.sh; do
		[ -f "$REPO/bin/$f" ]
		[ -x "$REPO/bin/$f" ]
	done
	# Private verbs the formula installs as libexec (git-review-verbs/).
	for v in start compare status list preview next prev finish save continue abort clean forget; do
		[ -f "$REPO/bin/git-review-verbs/$v" ]
		[ -x "$REPO/bin/git-review-verbs/$v" ]
	done
}

@test "homebrew: completion files referenced in the formula exist" {
	[ -f "$REPO/completions/git-review-workflow.bash" ]
	[ -f "$REPO/completions/git-review-workflow.zsh" ]
	[ -f "$REPO/completions/git-review-workflow.fish" ]
}

@test "homebrew: formula test-block commands succeed" {
	TMP="$(mktemp -d)"
	# Mirror the keg layout: the dispatcher, the sourced lib and the private verbs
	# directory live together (libexec), so copy bin/ whole rather than flat —
	# the dispatcher resolves its verbs and sourced lib from there.
	cp -R "$REPO"/bin/. "$TMP/"
	for f in "$TMP"/git-*; do
		if [ -f "$f" ]; then chmod +x "$f"; fi
	done
	run "$TMP/git-review" --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"git review workflow"* ]]
	run "$TMP/git-review" --version
	[ "$status" -eq 0 ]
	[[ "$output" == *"$VERSION"* ]]
	# Verb routing through the dispatcher (the verbs are libexec beside it).
	run "$TMP/git-review" start -h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review start"* ]]
	run "$TMP/git-review" finish -h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review finish"* ]]
	rm -rf "$TMP"
}

# ── Executable bits ─────────────────────────────────────────────────────────────
#
# These assert the *git index* mode (100755), not the filesystem permission.
# Checking `git ls-files -s` is what the CI lint job does, and unlike `test -x`
# it is deterministic across platforms: on Windows (and any core.fileMode=false
# checkout) the working-tree bit is meaningless, so a `test -x` check there can
# pass even when the committed mode is 100644. This is the gap that let
# bin/git-review-lib.sh ship as 100644.

# Returns the git index mode for the given tracked path.
git_mode() {
	git -C "$REPO" ls-files -s -- "$1" | awk '{print $1}'
}

@test "exec bits: every tracked file under bin/ is committed as 100755" {
	# Iterates the index instead of a hardcoded list, so any file added to
	# bin/ in the future is covered automatically. Mirrors the CI lint check.
	bad=""
	while IFS= read -r line; do
		mode=$(printf '%s' "$line" | awk '{print $1}')
		path=$(printf '%s' "$line" | cut -f2)
		# A .gitkeep marker, if present, is not a script, so it is not expected to
		# be executable.
		case "$path" in */.gitkeep) continue ;; esac
		[ "$mode" = "100755" ] || bad="$bad $path($mode)"
	done < <(git -C "$REPO" ls-files -s -- bin/)
	[ -z "$bad" ] || { echo "non-executable bin/ files:$bad"; false; }
}

@test "exec bits: bin/ is non-empty (guards against a vacuous pass)" {
	count=$(git -C "$REPO" ls-files -- bin/ | wc -l)
	[ "$count" -gt 0 ]
}

@test "exec bits: root installer/uninstaller scripts are committed as 100755" {
	for f in install.sh uninstall.sh web-install.sh web-uninstall.sh bump-version.sh; do
		[ -f "$REPO/$f" ]
		mode=$(git_mode "$f")
		[ "$mode" = "100755" ] || { echo "$f is $mode, expected 100755"; false; }
	done
}
