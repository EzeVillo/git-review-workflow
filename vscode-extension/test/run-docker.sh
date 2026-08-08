#!/usr/bin/env bash
#
# Run the extension's integration suite inside a Linux container.
#
# Why: the suite shells out to a real `git review` for every fixture and every
# panel refresh, and each verb costs a dozen processes. Creating a process on
# Windows costs ~50ms against ~1ms on Linux, so the same work runs about 20x
# slower there — the CLI part of one spec measured 15s on Windows and 0.7s on
# Linux. CI still runs the suite on real Windows and macOS runners, so this
# bypasses nothing there.
#
# Usage:
#   vscode-extension/test/run-docker.sh              # the whole suite
#   vscode-extension/test/run-docker.sh open-entry   # specs whose path matches
#   MOCHA_GREP='opens the diff' vscode-extension/test/run-docker.sh
#   vscode-extension/test/run-docker.sh -- sh        # a shell in the container
#
# node_modules, the downloaded VS Code and the npm cache live in named volumes,
# so only the first run pays for them. `docker volume rm` them to start over:
#   docker volume rm grv-vscode-node-modules grv-vscode-test-cache grv-vscode-npm-cache
set -eu

# Repo root = two levels above this script, regardless of where it's run from.
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

image="git-review-vscode-tests"

# Don't let MSYS rewrite /src and the other container-side paths.
export MSYS_NO_PATHCONV=1

# Build the image only when it's missing (cheap, layer-cached afterwards).
if ! docker image inspect "$image" >/dev/null 2>&1; then
	echo "Building $image image (first run downloads Electron's dependencies)..." >&2
	docker build -t "$image" "$script_dir" >&2
fi

# `-- <cmd>` runs <cmd> instead of the suite; a lone argument narrows it to the
# specs whose path contains it (MOCHA_FILE, read by test/integration/index.ts).
mocha_file="${MOCHA_FILE:-}"
if [ "${1:-}" = "--" ]; then
	shift
else
	if [ "$#" -gt 0 ]; then
		mocha_file="$1"
		shift
	fi
	if [ "$#" -gt 0 ]; then
		echo "error: unexpected argument '$1' (one filter, or '--' followed by a command)" >&2
		exit 2
	fi
fi

exec docker run --rm \
	-v "$repo_root:/src:ro" \
	-v grv-vscode-node-modules:/work/vscode-extension/node_modules \
	-v grv-vscode-test-cache:/work/vscode-extension/.vscode-test \
	-v grv-vscode-npm-cache:/home/node/.npm \
	-e MOCHA_FILE="$mocha_file" \
	-e MOCHA_GREP="${MOCHA_GREP:-}" \
	"$image" "$@"
