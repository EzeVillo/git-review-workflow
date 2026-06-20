#!/usr/bin/env sh
#
# Installs the git review commands by symlinking them into a directory on PATH.
# Override the target with PREFIX, e.g. `PREFIX=/usr/local/bin ./install.sh`.
#
set -eu

SRC_DIR="$(dirname -- "$0")"
SRC_DIR="$(cd -- "$SRC_DIR" && pwd)"
BIN_DIR="${PREFIX:-$HOME/.local/bin}"

mkdir -p "$BIN_DIR"
for f in "$SRC_DIR"/bin/git-*; do
	name="$(basename "$f")"
	chmod +x "$f"
	ln -sf "$f" "$BIN_DIR/$name"
done

echo "Installed git review commands to $BIN_DIR"

case ":$PATH:" in
*":$BIN_DIR:"*) ;;
*)
	echo "note: $BIN_DIR is not on your PATH. Add this line to your ~/.bashrc or ~/.zshrc:"
	echo "  export PATH=\"$BIN_DIR:\$PATH\""
	;;
esac

echo "For tab completion, source completions/git-review-workflow.bash from your shell rc"
