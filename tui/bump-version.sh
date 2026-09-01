#!/usr/bin/env sh
#
# Stamp the independently released terminal TUI version. The four Homebrew
# checksums are intentionally left untouched: they cannot be known until the
# tagged assets exist, and release-tui.yml pins them afterwards.
#
# usage: ./tui/bump-version.sh X.Y.Z
set -eu

V="${1:-}"
case "$V" in
	[0-9]*.[0-9]*.[0-9]*) ;;
	*)
		echo "usage: $0 X.Y.Z" >&2
		exit 1
		;;
esac

# shellcheck disable=SC1007 # CDPATH= empties CDPATH for this cd
dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck disable=SC1007 # CDPATH= empties CDPATH for this cd
repo="$(CDPATH= cd -- "$dir/.." && pwd)"
version_go="$dir/internal/domain/version.go"
formula="$repo/Formula/git-review-ui.rb"

sed_i() {
	_t="$(mktemp)"
	sed -E "$1" "$2" >"$_t" && mv "$_t" "$2"
}

sed_i "s#^(const TUIVersion = \")[^\"]*(\")#\1${V}\2#" "$version_go"
sed_i "s#^(  version ).*#\1\"${V}\"#" "$formula"
sed_i "s#(releases/download/tui-v)[^/]+(/git-review-ui_)[^_]+(_)#\1${V}\2${V}\3#" "$formula"

cat <<EOF
bumped terminal TUI to $V. Next:

  git diff tui/internal/domain/version.go Formula/git-review-ui.rb
  git commit -am "Release terminal TUI $V"
  git tag "tui-v$V"
  git push origin HEAD --tags
EOF
