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
for f in git-review git-review-pr git-review-next git-review-prev git-review-status git-review-list git-review-abort git-finish-review git-clean-review; do
	chmod +x "$SRC_DIR/bin/$f"
	ln -sf "$SRC_DIR/bin/$f" "$BIN_DIR/$f"
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
