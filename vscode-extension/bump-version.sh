#!/usr/bin/env sh
#
# bump-version.sh — stamp the VS Code extension version everywhere it must agree.
#
# The version lives in several files on purpose: package.json is what vsce
# publishes to the Marketplace, and package-lock.json repeats the package's own
# version at the root and under packages[""]. This script bumps both from a
# single argument so they can never drift out of sync.
#
# CHANGELOG.md headings are written by hand (move Unreleased notes under the
# new ## [X.Y.Z] section before tagging).
#
# usage: ./bump-version.sh X.Y.Z
#        (from this directory, or: ./vscode-extension/bump-version.sh X.Y.Z)
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
pkg="$dir/package.json"
lock="$dir/package-lock.json"

# Portable in-place sed. GNU and BSD/macOS sed disagree on `-i` (BSD requires a
# backup-suffix argument right after it), so route through a temp file, which
# behaves identically on both.
sed_i() {
	# usage: sed_i EXPR FILE
	_t="$(mktemp)"
	sed -E "$1" "$2" >"$_t" && mv "$_t" "$2"
}

# package.json top-level version only (two-space indent; matches root package.json
# stamp in the CLI's bump-version.sh).
sed_i "s#^(  \"version\": \")[^\"]*(\")#\1${V}\2#" "$pkg"

# package-lock.json: the package's own version appears twice — once at the root
# and once under packages[""] — each on the line after "name": "git-review-workflow".
# Stamp only those (never dependency versions: the same X.Y.Z could collide).
_t="$(mktemp)"
awk -v v="$V" '
	/"name": "git-review-workflow"/ { stamp = 1 }
	stamp && /"version":/ {
		sub(/"version": "[^"]*"/, "\"version\": \"" v "\"")
		stamp = 0
	}
	{ print }
' "$lock" >"$_t" && mv "$_t" "$lock"

cat <<EOF
bumped vscode-extension to $V. Next:

  git diff vscode-extension/
  # fill CHANGELOG.md (move Unreleased notes under ## [$V])
  git commit -am "Release vscode-extension $V"
EOF
