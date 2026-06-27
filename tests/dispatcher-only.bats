#!/usr/bin/env bats
#
# Contract for the dispatcher layout: `git review <verb>` is the whole public
# surface, so the ONLY git-discoverable executable is the dispatcher itself. git
# finds a subcommand by an executable named `git-<name>` on PATH; here the only
# such name is `git-review`. The verbs are private libexec under
# git-review-verbs/ — never on PATH, never named git-*, so git cannot reach them
# as `git <verb>`. These tests pin that down at the source and after each
# installer runs.

# The verbs that live as private libexec, never on PATH as standalone names.
VERBS="start compare status list preview next prev finish save continue abort clean forget"

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	REPO="$BATS_TEST_DIRNAME/.."
	export PREFIX="$TMP/bin"
}

teardown() {
	rm -rf "$TMP"
}

# ── Source-level: bin/ top level holds only the dispatcher trio ───────────────

@test "dispatcher-only: bin/ top level is only the dispatcher, the sourced lib and the verbs dir" {
	# Anything at the top of bin/ must be exactly one of these three — a stray
	# git-* executable here would be discoverable as `git <name>`.
	bad=""
	for f in "$REPO"/bin/*; do
		name="$(basename "$f")"
		case "$name" in
		git-review | git-review-lib.sh | git-review-verbs) ;;
		*) bad="$bad $name" ;;
		esac
	done
	[ -z "$bad" ] || { echo "unexpected top-level bin/ entries:$bad"; false; }
}

@test "dispatcher-only: the verbs directory is non-empty (guards a vacuous pass)" {
	count=0
	for v in "$REPO"/bin/git-review-verbs/*; do
		[ -f "$v" ] && count=$((count + 1))
	done
	[ "$count" -ge 13 ]
}

# ── install.sh: only the dispatcher reaches PATH ──────────────────────────────

@test "dispatcher-only: install.sh puts only the dispatcher on PATH" {
	chmod +x "$REPO"/bin/git-review 2>/dev/null ||
		skip "repo is read-only; install.sh cannot run here"

	run sh "$REPO/install.sh"
	[ "$status" -eq 0 ]

	# The dispatcher is there...
	[ -x "$PREFIX/git-review" ]
	# ...no verb is a standalone binary on PATH (they are libexec). This holds in
	# both layouts: with symlinks the verbs stay in the repo; on a filesystem
	# without symlink support (Windows/Git Bash) install.sh copies the verbs dir
	# beside the dispatcher as libexec — a subdir, never a git-discoverable name.
	for v in $VERBS; do
		[ ! -e "$PREFIX/$v" ] || { echo "install.sh leaked verb $v onto PATH"; false; }
	done
	# Nothing else slipped in: every top-level entry is the dispatcher or its
	# libexec (the sourced lib / the verbs dir laid down by the copy fallback).
	for f in "$PREFIX"/*; do
		case "$(basename "$f")" in
		git-review | git-review-lib.sh | git-review-verbs) ;;
		*) echo "install.sh left an unexpected entry: $(basename "$f")"; false ;;
		esac
	done
}

# ── web-install.sh: the copy installer is equally clean ───────────────────────

@test "dispatcher-only: web-install.sh puts only the dispatcher trio on PATH" {
	# Build a release-shaped tarball from the repo's bin/ and stub curl so the
	# installer runs offline (mirrors tests/web-install.bats).
	ARC_DIR="$TMP/arc/git-review-workflow-v0.0.1"
	mkdir -p "$ARC_DIR/bin"
	for f in "$REPO"/bin/git-*; do
		if [ -d "$f" ]; then
			cp -R "$f" "$ARC_DIR/bin/"
			continue
		fi
		cp "$f" "$ARC_DIR/bin/"
		chmod +x "$ARC_DIR/bin/$(basename "$f")"
	done
	FAKE_TARBALL="$TMP/release.tar.gz"
	export FAKE_TARBALL
	tar -czf "$FAKE_TARBALL" -C "$TMP/arc" git-review-workflow-v0.0.1

	MOCK_BIN="$TMP/mock-bin"
	mkdir -p "$MOCK_BIN"
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

	run sh "$REPO/web-install.sh"
	[ "$status" -eq 0 ]

	[ -x "$PREFIX/git-review" ]
	# Verbs ship inside PREFIX/git-review-verbs (libexec), never as a
	# git-discoverable binary directly on PATH.
	for v in $VERBS; do
		[ ! -e "$PREFIX/$v" ] || { echo "web-install.sh leaked verb $v onto PATH"; false; }
	done
	# The copy installer lays down exactly the dispatcher trio, nothing else.
	for f in "$PREFIX"/*; do
		case "$(basename "$f")" in
		git-review | git-review-lib.sh | git-review-verbs) ;;
		*) echo "web-install.sh left an unexpected entry: $(basename "$f")"; false ;;
		esac
	done
}
