#!/usr/bin/env sh
#
# Stamp the independently released terminal TUI version. The Homebrew
# formula stays pinned until release-tui.yml publishes the new assets.
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
version_go="$dir/internal/domain/version.go"

sed_i() {
	_t="$(mktemp)"
	sed -E "$1" "$2" >"$_t" && mv "$_t" "$2"
}

sed_i "s#^(const TUIVersion = \")[^\"]*(\")#\1${V}\2#" "$version_go"

cat <<EOF
bumped terminal TUI to $V. Next:

  git diff tui/internal/domain/version.go
  git commit -am "Release terminal TUI $V"
  git tag "tui-v$V"
  git push origin HEAD --tags
EOF
