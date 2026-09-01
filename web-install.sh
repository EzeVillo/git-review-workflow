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
	# The private verbs directory is libexec: copy it whole into a subdirectory
	# of BIN_DIR (NOT onto PATH — git must not discover a verb as `git <verb>`).
	# The dispatcher reaches it (and git-review-lib.sh) beside itself once
	# installed here.
	if [ -d "$f" ]; then
		rm -rf "${BIN_DIR:?}/$name"
		cp -R "$f" "$BIN_DIR/$name"
		for v in "$BIN_DIR/$name"/*; do
			if [ -f "$v" ]; then chmod +x "$v"; fi
		done
		continue
	fi
	cp "$f" "$BIN_DIR/$name"
	chmod +x "$BIN_DIR/$name"
	installed="$installed $name"
done

echo "Installed:$installed"

install_ui() {
	releases="$(curl -fsSL "$api/releases?per_page=100" 2>/dev/null || true)"
	tui_tag="$(printf '%s\n' "$releases" | tr '{' '\n' |
		sed -nE 's/.*"tag_name"[ ]*:[ ]*"([^"]+)".*/\1/p' |
		grep '^tui-v' | head -1 || true)"
	if [ -z "$tui_tag" ]; then
		echo "note: no terminal TUI release is available; the CLI is installed."
		return 0
	fi

	tui_os="$(uname -s)"
	tui_arch="$(uname -m)"
	case "$tui_os:$tui_arch" in
	Darwin:arm64 | Darwin:aarch64) tui_target="darwin_arm64.tar.gz" ;;
	Darwin:x86_64 | Darwin:amd64) tui_target="darwin_amd64.tar.gz" ;;
	Linux:x86_64 | Linux:amd64) tui_target="linux_amd64.tar.gz" ;;
	Linux:aarch64 | Linux:arm64) tui_target="linux_arm64.tar.gz" ;;
	Linux:armv7* | Linux:armv6*) tui_target="linux_armv7.tar.gz" ;;
	MINGW*:x86_64 | MSYS*:x86_64 | CYGWIN*:x86_64) tui_target="windows_amd64.zip" ;;
	MINGW*:aarch64 | MSYS*:aarch64 | CYGWIN*:aarch64) tui_target="windows_arm64.zip" ;;
	*)
		echo "note: no terminal TUI asset is published for this platform; the CLI is installed."
		return 0
		;;
	esac

	tui_version="${tui_tag#tui-v}"
	tui_asset="git-review-ui_${tui_version}_${tui_target}"
	tui_base="https://github.com/$REPO/releases/download/$tui_tag"
	tui_archive="$tmp/$tui_asset"
	tui_sums="$tmp/SHA256SUMS"
	if ! curl -fsSL "$tui_base/SHA256SUMS" >"$tui_sums" 2>/dev/null; then
		echo "note: could not download the terminal TUI checksums; the CLI is installed."
		return 0
	fi
	if ! curl -fsSL "$tui_base/$tui_asset" >"$tui_archive" 2>/dev/null; then
		echo "note: no terminal TUI asset is available for this platform; the CLI is installed."
		return 0
	fi
	want="$(awk -v name="$tui_asset" '$2 == name {print $1}' "$tui_sums")"
	if [ -z "$want" ]; then
		echo "note: the terminal TUI checksum list does not cover this platform; the CLI is installed."
		return 0
	fi
	if command -v sha256sum >/dev/null 2>&1; then
		got="$(sha256sum "$tui_archive" | awk '{print $1}')"
	elif command -v shasum >/dev/null 2>&1; then
		got="$(shasum -a 256 "$tui_archive" | awk '{print $1}')"
	else
		echo "note: no SHA-256 tool is available, so the terminal TUI was not installed."
		return 0
	fi
	if [ "$got" != "$want" ]; then
		echo "note: terminal TUI checksum mismatch; the CLI is installed and the TUI was skipped."
		return 0
	fi

	tui_extract="$tmp/tui"
	mkdir -p "$tui_extract"
	case "$tui_target" in
	*.zip)
		if ! command -v unzip >/dev/null 2>&1; then
			echo "note: unzip is required for the terminal TUI asset; the CLI is installed."
			return 0
		fi
		if ! unzip -q "$tui_archive" -d "$tui_extract"; then
			echo "note: the terminal TUI archive could not be unpacked; the CLI is installed."
			return 0
		fi
		tui_binary="$tui_extract/git-review-ui.exe"
		tui_dest="$BIN_DIR/git-review-ui.exe"
		;;
	*)
		if ! tar -xzf "$tui_archive" -C "$tui_extract"; then
			echo "note: the terminal TUI archive could not be unpacked; the CLI is installed."
			return 0
		fi
		tui_binary="$tui_extract/git-review-ui"
		tui_dest="$BIN_DIR/git-review-ui"
		;;
	esac
	if [ ! -f "$tui_binary" ]; then
		echo "note: the terminal TUI archive has an unexpected layout; the CLI is installed."
		return 0
	fi
	cp "$tui_binary" "$tui_dest"
	chmod +x "$tui_dest"
	echo "Installed terminal TUI ($tui_tag): $(basename "$tui_dest")"
}

if [ "${GIT_REVIEW_WITH_UI:-}" = "1" ]; then
	install_ui
fi

case ":$PATH:" in
*":$BIN_DIR:"*) ;;
*)
	echo "note: $BIN_DIR is not on your PATH. Add this line to your ~/.bashrc or ~/.zshrc:"
	echo "  export PATH=\"$BIN_DIR:\$PATH\""
	;;
esac
