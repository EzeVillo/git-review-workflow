#!/usr/bin/env bats
#
# A release bumps the version in several places at once. The files that ship
# *inside* the tarball (VERSION, bin/git-review, package.json) must be bumped in
# the tagged commit; the file that points *at* the tarball (the Homebrew formula)
# is pinned afterwards by the release workflow. If any of them drift out of sync,
# the tag would ship — or advertise, or publish to npm — the wrong version.
#
# These tests assert that single invariant directly, so a partial bump fails
# loudly and names exactly which file lagged behind.

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
	VERSION="$(cat "$REPO/VERSION")"
}

@test "version: VERSION file is a bare semver with no trailing junk" {
	[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "version: bin/git-review embeds the same version as the VERSION file" {
	embedded="$(sed -nE 's#^VERSION="([^"]*)".*#\1#p' "$REPO/bin/git-review")"
	[ "$embedded" = "$VERSION" ]
}

@test "version: Homebrew formula matches the VERSION file" {
	pinned="$(sed -nE 's#^  version "([^"]*)".*#\1#p' "$REPO/Formula/git-review-workflow.rb")"
	[ "$pinned" = "$VERSION" ]
}

@test "version: package.json matches the VERSION file" {
	# The npm package publishes whatever version package.json carries, so it must
	# agree with the VERSION file shipped alongside it in the tagged commit.
	pinned="$(sed -nE 's#^  "version": "([^"]*)".*#\1#p' "$REPO/package.json")"
	[ "$pinned" = "$VERSION" ]
}

@test "version: README does not hardcode a version number" {
	# The README points at the VERSION file instead of repeating the number,
	# so it can never go stale. Guard against the old hardcoded form coming back.
	! grep -qE '\*\*Version:\*\* +`[0-9]' "$REPO/README.md"
}

# --- VS Code extension (versioned independently of the CLI) -----------------
#
# package.json is what vsce publishes; package-lock.json repeats the package's
# own version at the root and under packages[""]. Both are stamped by
# vscode-extension/bump-version.sh.

vscode_ext_version() {
	sed -nE 's#^  "version": "([^"]*)".*#\1#p' "$REPO/vscode-extension/package.json"
}

@test "version: vscode-extension package.json is a bare semver" {
	v="$(vscode_ext_version)"
	[[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "version: vscode-extension package-lock matches package.json" {
	pkg="$(vscode_ext_version)"
	# Both own-version fields follow a "name": "git-review-workflow" line
	# (root + packages[""]); dependency versions must not be in this list.
	# shellcheck disable=SC2016 # awk program is single-quoted on purpose
	got="$(awk '
		/"name": "git-review-workflow"/ { stamp = 1; next }
		stamp && /"version":/ {
			sub(/.*"version": "/, "")
			sub(/".*/, "")
			print
			stamp = 0
		}
	' "$REPO/vscode-extension/package-lock.json")"
	count="$(printf '%s\n' "$got" | grep -c .)"
	[ "$count" -eq 2 ] || { echo "expected 2 package-lock own-versions, got $count: $got"; false; }
	while IFS= read -r line; do
		[ "$line" = "$pkg" ] || { echo "package-lock version $line != package.json $pkg"; false; }
	done <<EOF
$got
EOF
}

# --- JetBrains IDE plugin (versioned independently of the CLI) --------------
#
# pluginVersion in gradle.properties is the sole source of truth; Gradle patches
# plugin.xml at build time. Stamped by jetbrains-plugin/bump-version.sh.

@test "version: jetbrains-plugin pluginVersion is a bare semver" {
	v="$(sed -nE 's#^pluginVersion = (.*)#\1#p' "$REPO/jetbrains-plugin/gradle.properties")"
	[[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# --- Visual Studio extension (versioned independently of the CLI) -----------
#
# <Version> in GitReview.VS.csproj is stamped by visualstudio-extension/bump-version.sh.

@test "version: visualstudio-extension csproj Version is a bare semver" {
	v="$(sed -nE 's#.*<Version>([0-9]+\.[0-9]+\.[0-9]+)</Version>.*#\1#p' "$REPO/visualstudio-extension/src/GitReview.VS/GitReview.VS.csproj" | head -n1)"
	[[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "version: visualstudio-extension vsixmanifest matches csproj Version" {
	pkg="$(sed -nE 's#.*<Version>([0-9]+\.[0-9]+\.[0-9]+)</Version>.*#\1#p' "$REPO/visualstudio-extension/src/GitReview.VS/GitReview.VS.csproj" | head -n1)"
	# Anchored to <Identity>: the root <PackageManifest Version="2.0.0"> is the
	# schema version and comes first, so an unanchored match never sees ours.
	man="$(sed -nE 's#.*<Identity [^>]*Version="([0-9]+\.[0-9]+\.[0-9]+)".*#\1#p' "$REPO/visualstudio-extension/src/GitReview.VS/source.extension.vsixmanifest" | head -n1)"
	[ "$man" = "$pkg" ]
}
