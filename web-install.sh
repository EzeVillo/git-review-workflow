#!/bin/sh
#
# One-line installer for git-review-workflow. Downloads the commands and copies
# them into a directory on your PATH — no git clone needed. Run it with:
#
#     curl -fsSL https://raw.githubusercontent.com/EzeVillo/git-review-workflow/HEAD/web-install.sh | sh
#
# Override the install dir with PREFIX, or the version/branch with REF:
#
#     curl -fsSL .../web-install.sh | PREFIX=/usr/local/bin REF=v0.0.1 sh
#
# With no REF it installs the latest release, falling back to the default branch.
#
set -eu

REPO="EzeVillo/git-review-workflow"
BIN_DIR="${PREFIX:-$HOME/.local/bin}"
api="https://api.github.com/repos/$REPO"

# Resolve which ref to install: explicit REF, else latest release, else default branch.
ref="${REF:-}"
if [ -z "$ref" ]; then
	ref="$(curl -fsSL "$api/releases/latest" 2>/dev/null |
		grep '"tag_name"' | head -1 |
		sed -E 's/.*"tag_name"[ ]*:[ ]*"([^"]+)".*/\1/' || true)"
fi
if [ -z "$ref" ]; then
	ref="$(curl -fsSL "$api" 2>/dev/null |
		grep '"default_branch"' | head -1 |
		sed -E 's/.*"default_branch"[ ]*:[ ]*"([^"]+)".*/\1/' || true)"
fi
[ -n "$ref" ] || {
	echo "error: could not determine a ref to install" >&2
	exit 1
}

echo "Installing git-review-workflow ($ref) into $BIN_DIR"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "https://github.com/$REPO/archive/$ref.tar.gz" | tar -xzf - -C "$tmp"
src="$(find "$tmp" -maxdepth 1 -type d -name 'git-review-workflow-*' | head -1)"
[ -n "$src" ] || {
	echo "error: unexpected archive layout" >&2
	exit 1
}

mkdir -p "$BIN_DIR"
installed=""
for f in "$src"/bin/git-*; do
	name="$(basename "$f")"
	cp "$f" "$BIN_DIR/$name"
	chmod +x "$BIN_DIR/$name"
	installed="$installed $name"
done

echo "Installed:$installed"

case ":$PATH:" in
*":$BIN_DIR:"*) ;;
*)
	echo "note: $BIN_DIR is not on your PATH. Add this line to your ~/.bashrc or ~/.zshrc:"
	echo "  export PATH=\"$BIN_DIR:\$PATH\""
	;;
esac
