#!/usr/bin/env sh
#
# bump-version.sh — stamp the version shipped in the CLI package.
#
# The version lives in several files on purpose: VERSION, bin/git-review and
# package.json ship *inside* the release tarball (the npm package reads its
# version from package.json), so they must carry the right number in the tagged
# commit. The Homebrew formula stays pinned to the published tarball until
# the release workflow updates its version, URL and checksum together.
#
# usage: ./bump-version.sh X.Y.Z
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
repo="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

# Portable in-place sed. GNU and BSD/macOS sed disagree on `-i` (BSD requires a
# backup-suffix argument right after it), so route through a temp file, which
# behaves identically on both.
sed_i() {
	# usage: sed_i EXPR FILE
	_t="$(mktemp)"
	sed -E "$1" "$2" >"$_t" && mv "$_t" "$2"
}

# Inside the tarball.
printf '%s\n' "$V" >"$repo/VERSION"
sed_i "s#^(VERSION=\")[^\"]*(\")#\1${V}\2#" "$repo/bin/git-review"
chmod +x "$repo/bin/git-review"
sed_i "s#^(  \"version\": \")[^\"]*(\")#\1${V}\2#" "$repo/package.json"

cat <<EOF
bumped to $V. Next:

  git diff                       # review the stamped files
  git commit -am "Release $V"
  git tag "v$V"
  git push origin HEAD --tags    # triggers the release workflow
EOF
