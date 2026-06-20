#!/usr/bin/env sh
#
# bump-version.sh — stamp a new version everywhere it must agree.
#
# The version lives in several files on purpose: VERSION and bin/git-review ship
# *inside* the release tarball, so they must carry the right number in the tagged
# commit; the Homebrew formula points *at* the tarball. This script bumps all of
# them from a single argument so they can never drift out of sync.
#
# The formula's sha256 is intentionally NOT touched here — it depends on the
# tarball GitHub builds for the tag, which does not exist yet. The release
# workflow (.github/workflows/release.yml) pins it after the tag is pushed.
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

repo="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
formula="$repo/Formula/git-review-workflow.rb"
url="https://github.com/EzeVillo/git-review-workflow/archive/refs/tags/v${V}.tar.gz"

# Inside the tarball.
printf '%s\n' "$V" >"$repo/VERSION"
sed -i -E "s#^(VERSION=\")[^\"]*(\")#\1${V}\2#" "$repo/bin/git-review"

# Pointing at the tarball (sha256 left for the release workflow).
sed -i -E "s#^(  version ).*#\1\"${V}\"#" "$formula"
sed -i -E "s#^(  url ).*#\1\"${url}\"#" "$formula"

cat <<EOF
bumped to $V. Next:

  git diff                       # review the stamped files
  git commit -am "Release $V"
  git tag "v$V"
  git push origin HEAD --tags    # triggers the release workflow
EOF
