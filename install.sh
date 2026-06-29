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

# Some filesystems can't make symlinks — notably Windows/Git Bash, where `ln -s`
# silently *copies* instead. A copied dispatcher can't resolve its own symlink
# back to the repo, so it would never find the private verbs directory. Probe for
# real symlink support and, when it's missing, fall back to copying the whole
# libexec beside the dispatcher.
symlinks_ok=yes
probe="$BIN_DIR/.git-review-symlink-probe"
rm -rf "$probe"
if ln -s "$SRC_DIR/bin/git-review" "$probe" 2>/dev/null && [ -L "$probe" ]; then
	:
else
	symlinks_ok=no
fi
rm -rf "$probe"

for f in "$SRC_DIR"/bin/git-*; do
	name="$(basename "$f")"
	# The private verbs directory and the sourced lib are libexec: with symlinks
	# they stay in the repo's bin/, where the dispatcher reaches them by resolving
	# its own symlink back here. Never put them on PATH — git must not discover a
	# verb as `git <verb>`.
	[ -d "$f" ] && continue
	[ "$name" = "git-review-lib.sh" ] && continue
	chmod +x "$f"
	if [ "$symlinks_ok" = yes ]; then
		ln -sf "$f" "$BIN_DIR/$name"
	else
		cp "$f" "$BIN_DIR/$name"
		chmod +x "$BIN_DIR/$name"
	fi
done

if [ "$symlinks_ok" = no ]; then
	# No symlinks: a copied dispatcher resolves its libexec to BIN_DIR, so place
	# the private verbs directory and the sourced lib there beside it. They sit in
	# a subdir / are not named git-*, so git still can't discover a verb as
	# `git <verb>`. uninstall.sh removes them.
	rm -rf "$BIN_DIR/git-review-verbs"
	cp -R "$SRC_DIR/bin/git-review-verbs" "$BIN_DIR/git-review-verbs"
	for v in "$BIN_DIR"/git-review-verbs/*; do
		[ -f "$v" ] && chmod +x "$v"
	done
	cp "$SRC_DIR/bin/git-review-lib.sh" "$BIN_DIR/git-review-lib.sh"
fi

echo "Installed git review commands to $BIN_DIR"

case ":$PATH:" in
*":$BIN_DIR:"*) ;;
*)
	echo "note: $BIN_DIR is not on your PATH. Add this line to your ~/.bashrc or ~/.zshrc:"
	echo "  export PATH=\"$BIN_DIR:\$PATH\""
	;;
esac

echo "For tab completion, source completions/git-review-workflow.bash from your shell rc"
