# Image for running the extension's integration suite on a native Linux kernel.
#
# Why: the suite shells out to a real `git review` for every fixture and every
# panel refresh, and each verb is a dozen processes. On Windows a process costs
# ~50ms (CreateProcess + DLLs + Defender) against ~1ms on Linux, so the same
# work takes ~20x longer there — minutes instead of seconds, with nothing to
# learn from the wait. CI still runs the suite on real Windows and macOS
# runners; this bypasses nothing there.
#
# Pinned to bookworm rather than the floating `node:22-slim`: the Electron
# runtime libraries below are Debian package names, and trixie renamed several
# of them for the 64-bit time_t transition (libasound2 -> libasound2t64), so a
# base image bump would break the build with no change here.
FROM node:22-bookworm-slim

# git + the CLI's shell, xvfb for the headless display, and the shared libraries
# the Electron binary of the VS Code test host links against.
RUN apt-get update && apt-get install -y --no-install-recommends \
	ca-certificates \
	git \
	xvfb \
	xauth \
	libasound2 \
	libatk-bridge2.0-0 \
	libatk1.0-0 \
	libcairo2 \
	libcups2 \
	libdbus-1-3 \
	libdrm2 \
	libgbm1 \
	libglib2.0-0 \
	libgtk-3-0 \
	libnspr4 \
	libnss3 \
	libpango-1.0-0 \
	libsecret-1-0 \
	libx11-6 \
	libx11-xcb1 \
	libxcb1 \
	libxcomposite1 \
	libxdamage1 \
	libxext6 \
	libxfixes3 \
	libxkbcommon0 \
	libxrandr2 \
	libxshmfence1 \
	&& rm -rf /var/lib/apt/lists/*

# Without this the extension reports `cli-missing` for every test. On POSIX, VS
# Code resolves the environment of a login shell and replaces its own with it,
# unless it was started by the `code` CLI — which is what VSCODE_CLI marks. The
# PATH that `runTests.ts` prepares (bin/ of the checkout at the front, so the
# extension resolves the CLI being tested) lives in the process environment, and
# that resolution discards it: the login shell of `node` has never heard of
# /work/bin. Setting it keeps the inherited environment, which is the same thing
# the GitHub runners end up with.
ENV VSCODE_CLI=1

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
