#!/usr/bin/env sh
#
# Removes the git review command symlinks. Override the target with PREFIX,
# e.g. `PREFIX=/usr/local/bin ./uninstall.sh`. This does not touch any
# review/* or review-fixes/* branches you may have created.
#
set -eu

BIN_DIR="${PREFIX:-$HOME/.local/bin}"

for f in git-review git-review-lib.sh; do
	rm -f "$BIN_DIR/$f"
done
# The copy installers place the libexec verbs directory here; remove it if
# present. rm -rf on a symlink drops just the link.
rm -rf "$BIN_DIR/git-review-verbs"

echo "Removed git review commands from $BIN_DIR"
