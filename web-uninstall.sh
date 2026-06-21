#!/bin/sh
#
# One-line uninstaller for git-review-workflow. Removes the commands that
# web-install.sh (or install.sh) put on your PATH — no git clone needed. Run:
#
#     curl -fsSL https://raw.githubusercontent.com/EzeVillo/git-review-workflow/HEAD/web-uninstall.sh | sh
#
# Override the install dir with PREFIX, matching how you installed:
#
#     curl -fsSL .../web-uninstall.sh | PREFIX=/usr/local/bin sh
#
# This only removes the commands. It never touches any review/* or
# review-fixes/* branches you may have created.
#
set -eu

BIN_DIR="${PREFIX:-$HOME/.local/bin}"

removed=""
for f in git-review git-review-pr git-review-next git-review-prev git-review-status git-review-list git-review-save git-review-continue git-review-abort git-finish-review git-clean-review git-review-forget-delta git-review-forget-saved; do
	if [ -e "$BIN_DIR/$f" ]; then
		rm -f "$BIN_DIR/$f"
		removed="$removed $f"
	fi
done

if [ -n "$removed" ]; then
	echo "Removed git review commands from $BIN_DIR:$removed"
else
	echo "No git review commands found in $BIN_DIR — nothing to remove."
fi
