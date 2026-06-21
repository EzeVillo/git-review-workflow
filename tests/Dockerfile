# Image for running the bats suite on a native Linux kernel.
# On Windows, running bats under Git Bash/MSYS is extremely slow because every
# git subprocess pays the cost of emulated fork(). Running the same tests in a
# Linux container brings a full suite run from minutes down to seconds.
#
# The repo is bind-mounted read-only; tests create their temp repos under /tmp
# inside the container (native ext4), so the Windows bind mount is never on the
# hot path.
FROM bats/bats:latest
RUN apk add --no-cache git
