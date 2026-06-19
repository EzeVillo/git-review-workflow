#!/usr/bin/env sh
#
# Removes the git review command symlinks. Override the target with PREFIX,
# e.g. `PREFIX=/usr/local/bin ./uninstall.sh`. This does not touch any
# review/* or review-fixes/* branches you may have created.
#
set -eu

BIN_DIR="${PREFIX:-$HOME/.local/bin}"

for f in git-review-pr git-review-next git-review-prev git-review-status git-review-list git-review-abort git-finish-review git-clean-review; do
	rm -f "$BIN_DIR/$f"
done

echo "Removed git review commands from $BIN_DIR"
