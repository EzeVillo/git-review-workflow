#!/usr/bin/env bats
#
# Tests for web-install.sh: the one-line Unix network installer.
# curl is stubbed so the suite runs fully offline.

# The dispatcher is the only command on PATH: every verb (start/status/list/
# preview/next/prev/finish/save/continue/abort/clean/forget) is installed as
# libexec under it, not as a standalone binary.
CMDS="git-review"

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PREFIX="$TMP/bin"
	REPO="$BATS_TEST_DIRNAME/.."

	# Build a tarball whose layout matches a GitHub release archive:
	# git-review-workflow-v0.0.1/bin/git-*
	ARC_DIR="$TMP/arc/git-review-workflow-v0.0.1"
	mkdir -p "$ARC_DIR/bin"
	for f in "$REPO"/bin/git-*; do
		# The private verbs directory ships inside the archive too; copy it whole
		# (a real GitHub tarball mirrors the repo's bin/ layout).
		if [ -d "$f" ]; then
			cp -R "$f" "$ARC_DIR/bin/"
			continue
		fi
		cp "$f" "$ARC_DIR/bin/"
		chmod +x "$ARC_DIR/bin/$(basename "$f")"
	done
	export FAKE_TARBALL="$TMP/release.tar.gz"
	tar -czf "$FAKE_TARBALL" -C "$TMP/arc" git-review-workflow-v0.0.1

	# Build the release-shaped TUI asset and checksum list used by opt-in tests.
	TUI_DIR="$TMP/tui-asset"
	mkdir -p "$TUI_DIR"
	cat > "$TUI_DIR/git-review-ui" << 'TUISTUB'
#!/bin/sh
printf 'tui-probe\n'
TUISTUB
	chmod +x "$TUI_DIR/git-review-ui"
	export FAKE_TUI_ASSET="$TMP/git-review-ui_0.1.0_linux_amd64.tar.gz"
	tar -czf "$FAKE_TUI_ASSET" -C "$TUI_DIR" git-review-ui
	export FAKE_TUI_SUMS="$TMP/SHA256SUMS"
	printf '%s  %s\n' "$(sha256sum "$FAKE_TUI_ASSET" | cut -d' ' -f1)" \
		"git-review-ui_0.1.0_linux_amd64.tar.gz" > "$FAKE_TUI_SUMS"
	export FAKE_CALL_LOG="$TMP/curl-calls.log"

	# Stub curl: serve local content for every URL pattern the installer uses.
	MOCK_BIN="$TMP/mock-bin"
	mkdir -p "$MOCK_BIN"
	export MOCK_BIN
	cat > "$MOCK_BIN/curl" << 'CURLSTUB'
#!/bin/sh
url=""
while [ $# -gt 0 ]; do
	case "$1" in
		-*) shift ;;
		*)  url="$1"; shift ;;
	esac
done
printf '%s\n' "$url" >> "$FAKE_CALL_LOG"
case "$url" in
	*/releases/latest)  printf '{"tag_name":"v0.0.1"}\n' ;;
	*/releases\?per_page=100) printf '[{"tag_name":"tui-v0.1.0"},{"tag_name":"v0.0.1"}]\n' ;;
	*/releases/download/tui-v0.1.0/SHA256SUMS) cat "$FAKE_TUI_SUMS" ;;
	*/releases/download/tui-v0.1.0/git-review-ui_0.1.0_linux_amd64.tar.gz) cat "$FAKE_TUI_ASSET" ;;
	*api.github.com/*)  printf '{"default_branch":"main"}\n' ;;
	*.tar.gz)           cat "$FAKE_TARBALL" ;;
	*)                  printf 'stub-curl: unhandled %s\n' "$url" >&2; exit 1 ;;
esac
CURLSTUB
	chmod +x "$MOCK_BIN/curl"
	export PATH="$MOCK_BIN:$PATH"
}

teardown() {
	rm -rf "$TMP"
}

@test "web-install.sh installs all commands into PREFIX" {
	run sh "$REPO/web-install.sh"
	[ "$status" -eq 0 ]
	for cmd in $CMDS; do
		[ -x "$PREFIX/$cmd" ]
	done
}

@test "web-install.sh: REF env var skips the releases/latest API call" {
	export FAKE_CALL_LOG="$TMP/curl-calls.log"
	cat > "$MOCK_BIN/curl" << 'CURLSTUB'
#!/bin/sh
url=""
while [ $# -gt 0 ]; do
	case "$1" in -*) shift ;; *) url="$1"; shift ;; esac
done
printf '%s\n' "$url" >> "$FAKE_CALL_LOG"
case "$url" in
	*.tar.gz) cat "$FAKE_TARBALL" ;;
	*)        printf '{}' ;;
esac
CURLSTUB
	chmod +x "$MOCK_BIN/curl"
	run env REF=v0.0.1 sh "$REPO/web-install.sh"
	[ "$status" -eq 0 ]
	! grep -q "releases/latest" "$FAKE_CALL_LOG"
}

@test "web-install.sh falls back to default branch when no release exists" {
	cat > "$MOCK_BIN/curl" << 'CURLSTUB'
#!/bin/sh
url=""
while [ $# -gt 0 ]; do
	case "$1" in -*) shift ;; *) url="$1"; shift ;; esac
done
case "$url" in
	*/releases/latest)  exit 1 ;;
	*api.github.com/*)  printf '{"default_branch":"main"}\n' ;;
	*.tar.gz)           cat "$FAKE_TARBALL" ;;
	*)                  exit 1 ;;
esac
CURLSTUB
	chmod +x "$MOCK_BIN/curl"
	run sh "$REPO/web-install.sh"
	[ "$status" -eq 0 ]
	[ -x "$PREFIX/git-review" ]
}

@test "web-install.sh: an installed command runs from PREFIX" {
	sh "$REPO/web-install.sh"
	# The copy install lays the verbs dir beside the dispatcher; routing must work.
	run "$PREFIX/git-review" start -h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review start"* ]]
}

@test "web-install.sh default does not request or install the TUI" {
	run sh "$REPO/web-install.sh"
	[ "$status" -eq 0 ]
	[ ! -e "$PREFIX/git-review-ui" ]
	! grep -q '/releases?per_page=100\|/releases/download/tui-v' "$FAKE_CALL_LOG"
}

@test "web-install.sh opt-in installs verified TUI beside dispatcher" {
	run env GIT_REVIEW_WITH_UI=1 sh "$REPO/web-install.sh"
	[ "$status" -eq 0 ]
	[ -x "$PREFIX/git-review-ui" ]

	# Own allowlist: the default dispatcher-only contract remains unchanged.
	got="$(for f in "$PREFIX"/*; do basename "$f"; done | sort)"
	want="$(printf '%s\n' git-review git-review-lib.sh git-review-ui git-review-verbs | sort)"
	[ "$got" = "$want" ]

	run env PATH="$PREFIX:$PATH" git review-ui --probe
	[ "$status" -eq 0 ]
	[ "$output" = "tui-probe" ]
	grep -q '/releases/latest' "$FAKE_CALL_LOG"
	grep -q '/releases?per_page=100' "$FAKE_CALL_LOG"
}

@test "web-install.sh checksum mismatch leaves CLI installed and skips TUI" {
	printf '%064d  %s\n' 0 "git-review-ui_0.1.0_linux_amd64.tar.gz" > "$FAKE_TUI_SUMS"
	run env GIT_REVIEW_WITH_UI=1 sh "$REPO/web-install.sh"
	[ "$status" -eq 0 ]
	[ -x "$PREFIX/git-review" ]
	[ ! -e "$PREFIX/git-review-ui" ]
	[[ "$output" == *"note:"* ]]
	[[ "$output" == *"checksum"* ]]
}

@test "web-install.sh unsupported platform leaves CLI installed and notes skip" {
	cat > "$MOCK_BIN/uname" << 'UNAMESTUB'
#!/bin/sh
printf 'Plan9\n'
UNAMESTUB
	chmod +x "$MOCK_BIN/uname"
	run env GIT_REVIEW_WITH_UI=1 sh "$REPO/web-install.sh"
	[ "$status" -eq 0 ]
	[ -x "$PREFIX/git-review" ]
	[ ! -e "$PREFIX/git-review-ui" ]
	[[ "$output" == *"note:"* ]]
	[[ "$output" == *"platform"* ]]
}
