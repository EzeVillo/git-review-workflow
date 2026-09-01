#!/usr/bin/env bats
#
# The three release workflows build their GitHub Release body by extracting one
# section from a CHANGELOG. That extraction shipped broken: `$0 == v` against a
# heading that carries a date ("## [0.3.0] - 2026-08-30") never matches, so
# jetbrains-v0.3.0 was published with the fallback pointer instead of its notes,
# with every gate green. These tests run the real awk against the real files.

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
}

# The extraction exactly as the workflows spell it.
extract_section() {
	# usage: extract_section <version> <changelog>
	awk -v v="## [$1]" '
		index($0, v) == 1 { on = 1; next }
		on && /^## \[/ { exit }
		on { print }
	' "$2"
}

# The heading each changelog's newest section actually carries.
newest_heading() {
	grep -m1 '^## \[' "$1"
}

newest_version() {
	newest_heading "$1" | sed -E 's|^## \[([^]]+)\].*|\1|'
}

# A workflow with its comment lines dropped. The comment above each awk quotes
# both broken forms to say why they are wrong, and a sweep that cannot tell
# code from the comment explaining it is the same mistake one level up.
workflow_code() {
	grep -v '^[[:space:]]*#' "$1"
}

@test "release-notes: every changelog exists and has a versioned heading" {
	for f in CHANGELOG.md tui/CHANGELOG.md vscode-extension/CHANGELOG.md \
		jetbrains-plugin/CHANGELOG.md visualstudio-extension/CHANGELOG.md; do
		[ -f "$REPO/$f" ] || {
			echo "missing changelog: $f"
			return 1
		}
		run newest_version "$REPO/$f"
		[ "$status" -eq 0 ]
		[[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
			echo "$f: newest heading is not a bare semver: $output"
			return 1
		}
	done
}

@test "release-notes: the newest section of every changelog extracts non-empty" {
	for f in CHANGELOG.md tui/CHANGELOG.md vscode-extension/CHANGELOG.md \
		jetbrains-plugin/CHANGELOG.md visualstudio-extension/CHANGELOG.md; do
		version="$(newest_version "$REPO/$f")"
		body="$(extract_section "$version" "$REPO/$f")"
		[ -n "$(printf '%s' "$body" | tr -d '[:space:]')" ] || {
			echo "$f: extracting [$version] produced an empty body"
			echo "heading was: $(newest_heading "$REPO/$f")"
			return 1
		}
	done
}

# The regression itself: a dated heading has to match. Equality does not, which
# is what shipped.
@test "release-notes: a dated heading still extracts its section" {
	tmp="$BATS_TEST_TMPDIR/dated.md"
	printf '## [9.9.9] - 2026-01-01\n\nthe body\n\n## [9.9.8]\n\nolder\n' >"$tmp"
	[ "$(extract_section 9.9.9 "$tmp")" = "
the body" ]
}

@test "release-notes: extraction stops at the next version" {
	tmp="$BATS_TEST_TMPDIR/two.md"
	printf '## [2.0.0]\n\nnew\n\n## [1.0.0]\n\nold\n' >"$tmp"
	body="$(extract_section 2.0.0 "$tmp")"
	[[ "$body" == *"new"* ]]
	[[ "$body" != *"old"* ]]
}

# The closing bracket lives inside v so a prefix match cannot bleed into a
# longer version string.
@test "release-notes: a version is not a prefix of a longer one" {
	tmp="$BATS_TEST_TMPDIR/pre.md"
	printf '## [0.1.0-beta]\n\nbeta body\n' >"$tmp"
	[ -z "$(extract_section 0.1.0 "$tmp")" ]
}

@test "release-notes: an absent version extracts nothing so the fallback fires" {
	[ -z "$(extract_section 99.99.99 "$REPO/CHANGELOG.md")" ]
}

@test "release-notes: all three workflows use the prefix match, never equality" {
	for w in release.yml release-tui.yml release-jetbrains.yml; do
		f="$REPO/.github/workflows/$w"
		grep -Fq 'index($0, v) == 1' "$f" || {
			echo "$w does not use the prefix match"
			return 1
		}
		# Neither broken form may come back (see workflow_code above on why
		# comments are dropped first).
		! workflow_code "$f" | grep -Fq '$0 == v' || {
			echo "$w still has the equality match that never fires"
			return 1
		}
		workflow_code "$f" | grep -Fq -- '--notes-file' || {
			echo "$w does not pass --notes-file"
			return 1
		}
		! workflow_code "$f" | grep -Fq -- '--generate-notes' || {
			echo "$w still generates notes from the shared commit history"
			return 1
		}
	done
}

# The release job of release-tui.yml only downloaded artifacts; reading the
# changelog needs the tagged tree.
@test "release-notes: the tui release job checks out the tree it reads" {
	block="$(sed -n '/^  release:/,$p' "$REPO/.github/workflows/release-tui.yml")"
	[[ "$block" == *"actions/checkout@v4"* ]]
	[[ "$block" == *"tui/CHANGELOG.md"* ]]
}

@test "release-notes: the CLI changelog documents the version being shipped" {
	version="$(tr -d '[:space:]' <"$REPO/VERSION")"
	body="$(extract_section "$version" "$REPO/CHANGELOG.md")"
	[ -n "$(printf '%s' "$body" | tr -d '[:space:]')" ] || {
		echo "VERSION is $version but CHANGELOG.md has no section for it"
		return 1
	}
}

@test "release-notes: the tui changelog documents the version being shipped" {
	version="$(sed -nE 's#^const TUIVersion = "([^"]*)"#\1#p' \
		"$REPO/tui/internal/domain/version.go")"
	body="$(extract_section "$version" "$REPO/tui/CHANGELOG.md")"
	[ -n "$(printf '%s' "$body" | tr -d '[:space:]')" ] || {
		echo "TUIVersion is $version but tui/CHANGELOG.md has no section for it"
		return 1
	}
}
