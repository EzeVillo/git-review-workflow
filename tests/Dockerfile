# Image for running the bats suite on a native Linux kernel.
# On Windows, running bats under Git Bash/MSYS is extremely slow because every
# git subprocess pays the cost of emulated fork(). Running the same tests in a
# Linux container brings a full suite run from minutes down to seconds.
#
# The repo is bind-mounted read-only; tests create their temp repos under /tmp
# inside the container (native ext4), so the Windows bind mount is never on the
# hot path.
#
# The bats version is pinned to the one CI installs (see the `test` job in
# .github/workflows/ci.yml) so a local run and a CI run cannot disagree about
# which flags exist. Bump both together.
FROM bats/bats:1.13.0
RUN apk add --no-cache git
