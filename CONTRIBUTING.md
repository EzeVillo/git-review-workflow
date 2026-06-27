# Contributing

Thanks for taking the time to contribute! Bug reports, fixes and ideas are all
welcome.

## Development

The commands are POSIX shell scripts under `bin/`. Run the checks locally before
opening a pull request:

```sh
shellcheck $(find bin -type f ! -name '.gitkeep') install.sh uninstall.sh web-install.sh web-uninstall.sh bump-version.sh
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

> The PowerShell installer tests (`*-ps1.bats`) need `pwsh`, which the container
> does not have, so they do not really run there — rely on CI (or local Windows)
> for those.

## Releasing

> Maintainers only.

Releases are cut by pushing a `v*` tag.

1. Bump the version everywhere it must agree, then tag that commit. The version
   lives in several files on purpose — `VERSION` and `bin/git-review` ship
   *inside* the tarball, while the Homebrew formula points *at* it — so
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

    - creates a GitHub Release for the tag with auto-generated notes, and
    - pins the Homebrew formula (`url`, `sha256`, `version`) to the tag on the
      default branch, so `brew install` (without `--HEAD`) installs that version.
