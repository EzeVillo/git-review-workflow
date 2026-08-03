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

### Pointing `git review` at this checkout

On Linux/macOS, `./install.sh` symlinks `bin/git-review` onto your `PATH`, so
edits to this checkout take effect immediately with no reinstall. On
Windows/Git Bash, `ln -s` silently *copies* instead of linking (see the
comment in `install.sh`), so `./install.sh` there leaves a frozen snapshot:
every edit needs a re-run of `./install.sh` to take effect, and it's easy to
forget and debug against a stale binary.

`npm link` avoids that: it makes npm point its global `git-review` package at
this directory via a real directory symlink (something Git Bash's `ln -s`
can't do, but npm's own linking can), so it always runs the checkout as it
sits on disk. From the repo root:

```sh
npm link
```

If you'd already run `./install.sh` on Windows, remove its frozen copy so it
can't shadow the link (whichever one is first on `PATH` wins):

```sh
./uninstall.sh
```

To check which one you're actually running, compare the version to
[`VERSION`](VERSION):

```sh
where git-review        # or: command -v -a git-review
git review --version
```

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
run it again to get the identical starting state back. The toy pull request
(`feature/checkout`) is four commits over five files (one file touched twice, so
`--step` and walk disagree), with a committed walkthrough whose reading order is
not the diff order and two paths carrying a space and a non-ASCII byte. Nothing
in the test suite depends on it; it exists purely to run the real commands
against something realistic.

Around it are the states one well-formed pull request cannot show, one branch
each: `feature/notifications` (walkthrough covering two of four files, so the
rest is uncovered), `feature/telemetry` (no walkthrough — `start` enters whole
mode on its own), and `feature/legacy` (a walkthrough naming paths a rename
removed, so the review degrades to whole with a note). On `develop`, three saved
reviews make up the inventory `git review list` prints: one resumable, one
blocked by an active `review/*` for the same branch, and one with no metadata
behind it. Those three are the only part built by *running* the commands rather
than by writing the repository directly — the branch config under
`review-saved/*` is theirs to write, and a second copy of it here would go stale
in silence. That phase fails soft: if a verb is broken the script warns and the
rest of the sandbox still comes out usable.

> The PowerShell installer tests (`*-ps1.bats`) need `pwsh`, which the container
> does not have, so they do not really run there — rely on CI (or local Windows)
> for those.

## The VS Code extension

[`vscode-extension/`](vscode-extension/) is a separate npm project with its own
checks, which CI runs as a second job. It shells out to the `git review` on
`PATH`, so install this checkout (`./install.sh`) before running or testing it.

```sh
cd vscode-extension
npm install
npm run watch      # esbuild, rebuilds dist/ on save
```

### Running it in a real editor

Open `vscode-extension/` in VS Code and press F5 (the *Run Extension* launch
configuration). That opens a second window — the Extension Development Host —
with the extension loaded from this checkout; changes need a reload of that
window (Developer: Reload Window), not a restart.

The panel only has something to show inside a repository with an active review,
so build one with the [sandbox](#trying-the-commands-by-hand) and open
`<sandbox>/work` in the development host:

```sh
./tests/sandbox.sh                    # from the repo root
git -C <sandbox>/work review start feature/checkout
```

The development host inherits the `PATH` of the VS Code that launched it, not
the one the sandbox's `env.sh` sets up: either install this checkout
(`./install.sh`) or point the `gitReview.path` setting at `bin/git-review`.

### Testing it

```sh
npm test                  # unit + integration, compiling first
npm run test:unit         # pure functions, no editor, milliseconds
npm run test:integration  # downloads a VS Code build on first run and drives it
```

The integration suite loads the extension from `dist/`, and only `npm test`
compiles first (through `pretest`). Running `npm run test:integration` on its own
tests whatever was built last — run `npm run compile` first, or keep
`npm run watch` going, otherwise a green run can be about code you already
changed. On Linux without a display, wrap it in `xvfb-run -a`.

Two of the integration specs open editor tabs and are flaky on Windows for
reasons that have nothing to do with the extension. Before chasing a failure
like *"no se abrió ningún tab"*, re-run the suite on an unmodified checkout to
see whether it was already failing.

### Previewing the panel

The webview's HTML is a pure function with no `vscode` import, so the panel's
states can be rendered in an ordinary browser without launching an editor:

```sh
npm run preview        # writes out/preview/index.html and prints its file:// URL
npm run preview:watch  # regenerates on save; reload the browser
```

It shows every state side by side at sidebar width — walk, step, whole and the
empty ones — with a switch for the dark, light and high-contrast themes. The
sample states in [`preview/fixtures.ts`](vscode-extension/preview/fixtures.ts)
are sample `status --porcelain` output run through the real parser and model, so
the preview follows the source instead of being maintained alongside it.

It is only good for the render: the buttons have no extension behind them, and
the theme variables in `preview/build.ts` approximate VS Code's. A `--vscode-*`
variable the panel starts using must be added there too, or it will look wrong
in the preview and fine in the editor. For behaviour, use F5.

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
