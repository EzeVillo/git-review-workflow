#!/usr/bin/env bash
#
# Container side of test/run-docker.sh. Starts as root to fix up ownership of
# the copy and the cache volumes, then drops to the unprivileged `node` user
# before launching anything.
#
# Dropping is not cosmetic: Electron refuses to start as root unless it is given
# --no-sandbox, and the test host's launch arguments come from runTests.ts. A
# non-root user keeps the container matching the GitHub runner instead of
# needing a Docker-only flag in the test code.
set -euo pipefail

SRC=/src
WORK=/work
EXT="$WORK/vscode-extension"

# The repo is mounted read-only, and `npm install` writes; copy it out. The
# excluded paths are either huge, host-specific, or mounted as cache volumes by
# run-docker.sh, and none of them are inputs: the build regenerates out/ and
# dist/, and the fixtures create their own git repos under /tmp rather than
# using .git.
mkdir -p "$WORK"
tar -C "$SRC" -cf - \
	--exclude=./.git \
	--exclude=./node_modules \
	--exclude=./vscode-extension/node_modules \
	--exclude=./vscode-extension/out \
	--exclude=./vscode-extension/dist \
	--exclude=./vscode-extension/.vscode-test \
	. | tar -C "$WORK" -xf -

# The bind mount can flatten the executable bit (notably from a Windows host).
# Without it the dispatcher is never discovered as `git review` and every
# fixture fails with a confusing "is not a git command".
chmod +x "$WORK"/bin/git-review "$WORK"/bin/git-review-verbs/*

# Named volumes are created root-owned; `node` has to own them to write.
chown -R node:node "$WORK" /home/node/.npm

# No arguments: the suite, the same three steps the CI job runs. With
# arguments: run them instead (a shell, a single npm script) in the same
# environment. `xvfb-run -a` picks a free display, so runs don't collide.
if [ "$#" -eq 0 ]; then
	command='npm install && npm run pretest && xvfb-run -a npm run test:integration'
else
	# `su -c` takes one string, so the arguments have to survive being flattened
	# into it and re-parsed on the other side: %q quotes each one for exactly
	# that. Plain "$*" would drop the quoting and turn `sh -c 'a && b'` into
	# `sh -c a` with the rest evaluated out here.
	command="$(printf '%q ' "$@")"
fi

# `su` without `-` keeps the environment (PATH to node, MOCHA_FILE/MOCHA_GREP
# from `docker run -e`), so HOME is the only thing to correct: left at /root,
# npm would write its cache outside the volume mounted for it.
exec su node -c "export HOME=/home/node; cd '$EXT' && $command"
