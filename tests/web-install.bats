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
case "$url" in
	*/releases/latest)  printf '{"tag_name":"v0.0.1"}\n' ;;
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
