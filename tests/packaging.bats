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
	for f in git-review git-review-pr git-review-next git-review-prev git-review-status \
	          git-review-preview git-review-list git-review-save git-review-continue \
	          git-review-abort git-finish-review git-clean-review git-review-forget-delta \
	          git-review-forget-saved git-review-lib.sh; do
		[ -f "$REPO/bin/$f" ]
		[ -x "$REPO/bin/$f" ]
	done
}

@test "homebrew: completion files referenced in the formula exist" {
	[ -f "$REPO/completions/git-review-workflow.bash" ]
	[ -f "$REPO/completions/git-review-workflow.zsh" ]
	[ -f "$REPO/completions/git-review-workflow.fish" ]
}

@test "homebrew: formula test-block commands succeed" {
	TMP="$(mktemp -d)"
	for f in "$REPO"/bin/git-*; do
		cp "$f" "$TMP/"
		chmod +x "$TMP/$(basename "$f")"
	done
	run "$TMP/git-review" --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"git review workflow"* ]]
	run "$TMP/git-review" --version
	[ "$status" -eq 0 ]
	[[ "$output" == *"$VERSION"* ]]
	run "$TMP/git-review-pr" --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review-pr"* ]]
	run "$TMP/git-finish-review" --h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git finish-review"* ]]
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
