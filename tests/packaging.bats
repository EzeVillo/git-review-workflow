#!/usr/bin/env bats
#
# Structural tests for the Homebrew formula and Scoop manifest.
# These catch stale metadata (wrong version, missing files, broken field names)
# without requiring Homebrew or Scoop to be installed.

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
	FORMULA="$REPO/Formula/git-review-workflow.rb"
	MANIFEST="$REPO/bucket/git-review-workflow.json"
	VERSION="$(cat "$REPO/VERSION")"
}

# ── Homebrew formula ──────────────────────────────────────────────────────────

@test "homebrew: formula version matches VERSION file" {
	grep -qE 'version "'"$VERSION"'"' "$FORMULA"
}

@test "homebrew: all bin files referenced in the formula exist and are executable" {
	for f in git-review-pr git-review-next git-review-prev git-review-status \
	          git-review-list git-review-abort git-finish-review git-clean-review; do
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
	run "$TMP/git-review-pr" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review-pr"* ]]
	run "$TMP/git-finish-review" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git finish-review"* ]]
	rm -rf "$TMP"
}

# ── Scoop manifest ────────────────────────────────────────────────────────────

@test "scoop: manifest is valid JSON" {
	python3 -c "" 2>/dev/null || skip "python3 not available"
	python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$MANIFEST"
}

@test "scoop: manifest version, fields, and extract_dir are consistent" {
	python3 -c "" 2>/dev/null || skip "python3 not available"
	python3 "$BATS_TEST_DIRNAME/helpers/check_scoop_fields.py" "$MANIFEST" "$VERSION"
}
