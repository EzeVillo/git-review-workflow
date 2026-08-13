#!/usr/bin/env sh
#
# bump-version.sh — stamp the Visual Studio extension version.
#
# Source of truth sites:
#   - src/GitReview.VS/GitReview.VS.csproj  <Version>
#   - src/GitReview.VS/source.extension.vsixmanifest  Identity Version=
#   - Directory.Build.props  GitReviewClientVersion
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

dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

sed_i() {
	_t="$(mktemp)"
	sed -E "$1" "$2" >"$_t" && mv "$_t" "$2"
}

sed_i "s#(<Version>)[0-9]+\.[0-9]+\.[0-9]+(</Version>)#\1${V}\2#" \
	"$dir/src/GitReview.VS/GitReview.VS.csproj"
sed_i "s#(Identity Id=\"com.ezevillo.gitreview.vs\" Version=\")[0-9]+\.[0-9]+\.[0-9]+(\")#\1${V}\2#" \
	"$dir/src/GitReview.VS/source.extension.vsixmanifest"
sed_i "s#(<GitReviewClientVersion>)[0-9]+\.[0-9]+\.[0-9]+(</GitReviewClientVersion>)#\1${V}\2#" \
	"$dir/Directory.Build.props"

cat <<EOF
bumped visualstudio-extension to $V. Next:

  git diff visualstudio-extension/
  # fill CHANGELOG.md (move Unreleased notes under ## [$V])
  git commit -am "Release visualstudio-extension $V"
EOF
