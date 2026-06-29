#!/usr/bin/env bash
#
# Run the bats test suite inside a Linux container.
#
# Why: under Git Bash/MSYS on Windows the suite takes minutes because each test
# spawns many git processes and emulated fork() is slow. The same tests run in
# seconds on a native Linux kernel. The CI still exercises the real Windows
# runner, so this is purely a local convenience and bypasses nothing there.
#
# Usage:
#   tests/run-docker.sh                 # run the whole suite
#   tests/run-docker.sh review.bats     # run a single file
#   tests/run-docker.sh tests/review.bats extras.bats   # any bats args/paths
set -eu

# Repo root = parent of this script's directory, regardless of where it's run.
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

image="git-review-tests"

# Don't let MSYS rewrite the /repo path or the container-side paths.
export MSYS_NO_PATHCONV=1

# Build the image only when it's missing (cheap, layer-cached afterwards).
if ! docker image inspect "$image" >/dev/null 2>&1; then
	echo "Building $image image..." >&2
	docker build -t "$image" -f "$script_dir/Dockerfile" "$script_dir" >&2
fi

# Default to the whole suite; otherwise pass through the caller's arguments.
if [ "$#" -eq 0 ]; then
	set -- tests/
fi

exec docker run --rm \
	-v "$repo_root:/repo:ro" \
	-w /repo \
	"$image" "$@"
