# Contributing

Thanks for taking the time to contribute! Bug reports, fixes and ideas are all
welcome.

## Development

The commands are POSIX shell scripts under `bin/`. Run the checks locally before
opening a pull request:

```sh
shellcheck $(find bin -type f ! -name '.gitkeep') install.sh uninstall.sh web-install.sh web-uninstall.sh bump-version.sh tests/sandbox.sh
bats tests/
```

CI runs both on every push and pull request (see
[`.github/workflows/ci.yml`](.github/workflows/ci.yml)). Please make sure both
pass before requesting a review.

### Running the tests on Windows

Under Git Bash/MSYS the suite is very slow: every test spawns many `git`
processes and emulated `fork()` is expensive, so a single file can take minutes.
If you have Docker, run the tests on a native Linux kernel instead — the same
suite finishes in seconds:

```sh
./tests/run-docker.sh                 # whole suite
./tests/run-docker.sh review.bats     # a single file
```

The script builds a small image ([`tests/Dockerfile`](tests/Dockerfile): bats +
git) on first use and mounts the repo read-only; tests create their temp repos
inside the container, so the Windows filesystem is never on the hot path. This
is a local convenience only — CI still runs the suite on a real Windows runner.

### Trying the commands by hand

The fixtures for `--step` and walk mode live inside the bats `setup()` functions
and are deleted by `teardown()`, so there is nothing left to experiment with.
[`tests/sandbox.sh`](tests/sandbox.sh) builds the same kind of pull request in a
directory that survives the run:

```sh
./tests/sandbox.sh                    # (re)build, then print how to enter it
./tests/sandbox.sh -d /tmp/box        # somewhere other than the default
```

It rebuilds from scratch on every call — break the sandbox however you like and
run it again to get the identical starting state back. The toy pull request is
four commits over five files (one file touched twice, so `--step` and walk
disagree), with a committed walkthrough whose reading order is not the diff
order and two paths carrying a space and a non-ASCII byte. Nothing in the test
suite depends on it; it exists purely to run the real commands against something
realistic.

> The PowerShell installer tests (`*-ps1.bats`) need `pwsh`, which the container
> does not have, so they do not really run there — rely on CI (or local Windows)
> for those.

## Releasing

> Maintainers only.

Releases are cut by pushing a `v*` tag.

1. Bump the version everywhere it must agree, then tag that commit. The version
   lives in several files on purpose — `VERSION`, `bin/git-review` and
   `package.json` ship *inside* the tarball (npm publishes the version from
   `package.json`), while the Homebrew formula points *at* it — so
   [`bump-version.sh`](bump-version.sh) stamps all of them from one argument
   and they can never drift out of sync:

   ```sh
   ./bump-version.sh X.Y.Z
   git diff                       # review the stamped files
   git commit -am "Release X.Y.Z"
   git tag vX.Y.Z
   git push origin HEAD --tags
   ```

   The script leaves the formula's `sha256` untouched on purpose: it depends on
   the tarball GitHub builds for the tag, which does not exist until the tag is
   pushed.

2. The release workflow
   ([`.github/workflows/release.yml`](.github/workflows/release.yml)) then
   pins that `sha256` (the one thing not known before the tag):

    - creates a GitHub Release for the tag with auto-generated notes,
    - pins the Homebrew formula (`url`, `sha256`, `version`) to the tag on the
      default branch, so `brew install` (without `--HEAD`) installs that version,
      and
    - publishes the tagged version to npm via Trusted Publishing (OIDC). There
      is no `NPM_TOKEN` secret — the repo and `release.yml` workflow are
      registered as a trusted publisher on npmjs.com, and provenance is attached
      automatically.
