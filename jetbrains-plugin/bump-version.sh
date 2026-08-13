#!/usr/bin/env sh
#
# bump-version.sh — stamp the JetBrains IDE plugin version everywhere it must
# agree.
#
# The source of truth is gradle.properties (`pluginVersion`). Gradle's
# IntelliJ Platform plugin patches plugin.xml (and the built zip name) from that
# property at build time, so there is no second hand-edited version field —
# still stamp it through this script so the release path matches the CLI and
# the VS Code extension, and so a future second site cannot drift.
#
# CHANGELOG.md headings are written by hand (move Unreleased notes under the
# new ## [X.Y.Z] section before publishing).
#
# usage: ./bump-version.sh X.Y.Z
#        (from this directory, or: ./jetbrains-plugin/bump-version.sh X.Y.Z)
set -eu

V="${1:-}"
case "$V" in
	[0-9]*.[0-9]*.[0-9]*) ;;
	*)
		echo "usage: $0 X.Y.Z" >&2
		exit 1
		;;
esac

# shellcheck disable=SC1007  # CDPATH= empties CDPATH for this cd, not an assignment
dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
props="$dir/gradle.properties"

# Portable in-place sed. GNU and BSD/macOS sed disagree on `-i` (BSD requires a
# backup-suffix argument right after it), so route through a temp file, which
# behaves identically on both.
sed_i() {
	# usage: sed_i EXPR FILE
	_t="$(mktemp)"
	sed -E "$1" "$2" >"$_t" && mv "$_t" "$2"
}

sed_i "s#^(pluginVersion = ).*#\1${V}#" "$props"

cat <<EOF
bumped jetbrains-plugin to $V. Next:

  git diff jetbrains-plugin/gradle.properties
  # fill CHANGELOG.md (move Unreleased notes under ## [$V])
  git commit -am "Release jetbrains-plugin $V"
  git tag jetbrains-v$V && git push origin HEAD --tags

The jetbrains-v* tag is what publishes to the Marketplace
(.github/workflows/release-jetbrains.yml); v* releases the CLI.
EOF
