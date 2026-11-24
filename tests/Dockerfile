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
FROM bats/bats:1.13.0 AS test-base
RUN apk add --no-cache git

# Exercise the minimum supported Git. A current Git forced down the fallback
# path still parses config and performs recursive fetches differently.
FROM test-base AS legacy-git
RUN apk add --no-cache build-base curl zlib-dev \
    && curl -fsSL https://codeload.github.com/git/git/tar.gz/refs/tags/v2.23.0 -o /tmp/git.tar.gz \
    && echo '7d84f5d6f48e95b467a04a8aa1d474e0d21abc7877998af945568d2634fea46a  /tmp/git.tar.gz' | sha256sum -c - \
    && tar -xzf /tmp/git.tar.gz -C /tmp
RUN make -C /tmp/git-2.23.0 -j4 prefix=/opt/legacy-git CFLAGS='-O2 -std=gnu99' \
    NO_CURL=YesPlease NO_EXPAT=YesPlease NO_OPENSSL=YesPlease \
    NO_REGEX=NeedsStartEnd NO_GETTEXT=YesPlease NO_PERL=YesPlease NO_TCLTK=YesPlease install
ENV PATH="/opt/legacy-git/bin:$PATH"

FROM test-base AS current-git
