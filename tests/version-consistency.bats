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

@test "version: visualstudio-extension Directory.Build.props matches csproj Version" {
	# bump-version.sh stamps all three sites at once; nothing else reads this one,
	# so a partial bump would sit here unnoticed until someone trusted the number.
	pkg="$(sed -nE 's#.*<Version>([0-9]+\.[0-9]+\.[0-9]+)</Version>.*#\1#p' "$REPO/visualstudio-extension/src/GitReview.VS/GitReview.VS.csproj" | head -n1)"
	props="$(sed -nE 's#.*<GitReviewClientVersion>([0-9]+\.[0-9]+\.[0-9]+)</GitReviewClientVersion>.*#\1#p' "$REPO/visualstudio-extension/Directory.Build.props" | head -n1)"
	[ -n "$props" ]
	[ "$props" = "$pkg" ]
}

# --- Terminal TUI (versioned independently of the CLI) ----------------------

tui_version() {
	sed -nE 's#^const TUIVersion = "([^"]*)"#\1#p' "$REPO/tui/internal/domain/version.go"
}

@test "version: tui version.go is a bare semver" {
	v="$(tui_version)"
	[[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
		echo "tui/internal/domain/version.go has no bare-semver TUIVersion: $v"
		false
	}
}

@test "version: tui Homebrew formula matches version.go" {
	tui="$(tui_version)"
	formula="$(sed -nE 's#^  version "([^"]*)"#\1#p' "$REPO/Formula/git-review-ui.rb")"
	[ "$formula" = "$tui" ] || {
		echo "Formula/git-review-ui.rb version $formula != tui/internal/domain/version.go $tui"
		false
	}
}

@test "version: tui has no package.json" {
	packages="$(find "$REPO/tui" -name package.json -type f -print)"
	[ -z "$packages" ] || {
		echo "tui must not gain a package.json: $packages"
		false
	}
}

@test "version: tui bump stamps version.go and formula but preserves checksums" {
	work="$(mktemp -d)"
	mkdir -p "$work/tui/internal/domain" "$work/Formula"
	cp "$REPO/tui/bump-version.sh" "$work/tui/bump-version.sh"
	cp "$REPO/tui/internal/domain/version.go" "$work/tui/internal/domain/version.go"
	cp "$REPO/Formula/git-review-ui.rb" "$work/Formula/git-review-ui.rb"
	before="$(sed -nE 's#^[ ]+sha256 "([^"]*)"#\1#p' "$work/Formula/git-review-ui.rb")"

	run sh "$work/tui/bump-version.sh" 9.8.7
	[ "$status" -eq 0 ]
	[ "$(sed -nE 's#^const TUIVersion = "([^"]*)"#\1#p' "$work/tui/internal/domain/version.go")" = "9.8.7" ]
	[ "$(sed -nE 's#^  version "([^"]*)"#\1#p' "$work/Formula/git-review-ui.rb")" = "9.8.7" ]
	urls="$(sed -nE 's#^[ ]+url "([^"]*)"#\1#p' "$work/Formula/git-review-ui.rb")"
	[ "$(printf '%s\n' "$urls" | grep -c '/tui-v9.8.7/git-review-ui_9.8.7_')" -eq 4 ]
	! printf '%s\n' "$urls" | grep -q '0.1.0'
	after="$(sed -nE 's#^[ ]+sha256 "([^"]*)"#\1#p' "$work/Formula/git-review-ui.rb")"
	[ "$after" = "$before" ]
	rm -rf "$work"
}

# --- Client CHANGELOGs name the version being shipped -----------------------
#
# Each client's CHANGELOG top section is what its store publishes (the JetBrains
# descriptor renders it into <change-notes>). A version bumped without its heading
# publishes the previous cycle's notes, or none, and only the store shows it.

@test "version: each client CHANGELOG has a heading for its own version" {
	vscode="$(sed -nE 's#^  "version": "([^"]*)".*#\1#p' "$REPO/vscode-extension/package.json")"
	jb="$(sed -nE 's#^pluginVersion = (.*)#\1#p' "$REPO/jetbrains-plugin/gradle.properties")"
	vs="$(sed -nE 's#.*<Version>([0-9]+\.[0-9]+\.[0-9]+)</Version>.*#\1#p' "$REPO/visualstudio-extension/src/GitReview.VS/GitReview.VS.csproj" | head -n1)"

	grep -qF "## [$vscode]" "$REPO/vscode-extension/CHANGELOG.md" ||
		{ echo "vscode-extension/CHANGELOG.md has no '## [$vscode]' heading"; false; }
	grep -qF "## [$jb]" "$REPO/jetbrains-plugin/CHANGELOG.md" ||
		{ echo "jetbrains-plugin/CHANGELOG.md has no '## [$jb]' heading"; false; }
	grep -qF "## [$vs]" "$REPO/visualstudio-extension/CHANGELOG.md" ||
		{ echo "visualstudio-extension/CHANGELOG.md has no '## [$vs]' heading"; false; }
}

@test "version: no client CHANGELOG still carries an Unreleased section" {
	# A release cut with notes left under Unreleased publishes an empty section:
	# the JetBrains descriptor looks up the version heading first and only falls
	# back to Unreleased, so the mistake is invisible until the Marketplace shows it.
	for f in \
		"$REPO/vscode-extension/CHANGELOG.md" \
		"$REPO/jetbrains-plugin/CHANGELOG.md" \
		"$REPO/visualstudio-extension/CHANGELOG.md"; do
		! grep -qE '^## \[Unreleased\]' "$f" || { echo "$f still has an Unreleased section"; false; }
	done
}
