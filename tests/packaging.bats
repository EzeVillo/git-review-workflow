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
	          git-review-list git-review-abort git-finish-review git-clean-review \
	          git-review-forget; do
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
