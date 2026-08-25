#!/usr/bin/env bash
#
# Run shellcheck inside a container, over the same files CI checks.
#
# Why: shellcheck is not part of any of the three toolchains this project needs
# (git, node, docker), so `shellcheck ...` from CONTRIBUTING.md only works if you
# happened to install it. The image is the upstream one, the file list is the one
# in .github/workflows/ci.yml, so a green run here is the green of CI's lint job.
#
# Usage:
#   ./lint-docker.sh              # the same files as CI
#   ./lint-docker.sh some.sh      # a specific file, while iterating
#
# CI installs shellcheck from three different sources (apt/brew/choco) and gets
# three different versions, so it targets the lowest common denominator. This
# pins the upstream `stable` tag: newer than at least one of those, so a warning
# it raises may not fail CI, but never the other way round.
set -eu

# Repo root = this script's directory, regardless of where it's run from.
repo_root="$(cd "$(dirname "$0")" && pwd)"

image="koalaman/shellcheck:stable"

# Don't let MSYS rewrite /mnt or the file paths passed to the container.
export MSYS_NO_PATHCONV=1

cd "$repo_root"

# Same list as the `lint` job: find walks bin/ (including the private
# git-review-verbs/ subdirectory, which the bin/* glob no longer reaches) and
# skips the .gitkeep.
if [ "$#" -eq 0 ]; then
	# shellcheck disable=SC2046 # deliberate word splitting: one argument per file
	set -- $(find bin -type f ! -name '.gitkeep') \
		install.sh uninstall.sh web-install.sh web-uninstall.sh bump-version.sh \
		vscode-extension/bump-version.sh jetbrains-plugin/bump-version.sh \
		visualstudio-extension/bump-version.sh \
		jetbrains-plugin/verification-report.sh \
		tests/sandbox.sh tests/sandbox-min.sh
fi

exec docker run --rm -v "$repo_root:/mnt:ro" -w /mnt "$image" "$@"
