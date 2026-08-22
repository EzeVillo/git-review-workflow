# Contributing

Thanks for taking the time to contribute! Bug reports, fixes and ideas are all welcome.

## Development

The commands are POSIX shell scripts under `bin/`. Run the checks locally before opening a pull
request:

```sh
./lint-docker.sh    # shellcheck, over the same files CI checks
./tests/run-docker.sh
```

Both run in a container, which is the recommended way and the only requirement beyond git:
shellcheck isn't part of any toolchain this project already needs, and the test suite is slow enough
on Windows to be worth avoiding (see
[Running the tests](#running-the-tests) below). The tools themselves work the same if you have them
installed:

```sh
shellcheck $(find bin -type f ! -name '.gitkeep') install.sh uninstall.sh web-install.sh web-uninstall.sh bump-version.sh vscode-extension/bump-version.sh jetbrains-plugin/bump-version.sh visualstudio-extension/bump-version.sh tests/sandbox.sh
bats tests/
```

CI runs both on every push and pull request (see
[`.github/workflows/ci.yml`](.github/workflows/ci.yml)). Please make sure both pass before
requesting a review. The extension has its own suite and its own container — see
[`vscode-extension/CONTRIBUTING.md`](vscode-extension/CONTRIBUTING.md).

### Pointing `git review` at this checkout

On Linux/macOS, `./install.sh` symlinks `bin/git-review` onto your `PATH`, so edits to this checkout
take effect immediately with no reinstall. On Windows/Git Bash, `ln -s` silently *copies* instead of
linking (see the comment in `install.sh`), so `./install.sh` there leaves a frozen snapshot:
every edit needs a re-run of `./install.sh` to take effect, and it's easy to forget and debug
against a stale binary.

`npm link` avoids that: it makes npm point its global `git-review` package at this directory via a
real directory symlink (something Git Bash's `ln -s`
can't do, but npm's own linking can), so it always runs the checkout as it sits on disk. From the
repo root:

```sh
npm link
```

If you'd already run `./install.sh` on Windows, remove its frozen copy so it can't shadow the link
(whichever one is first on `PATH` wins):

```sh
./uninstall.sh
```

To check which one you're actually running, compare the version to
[`VERSION`](VERSION):

```sh
where git-review        # or: command -v -a git-review
git review --version
```

### Running the tests

```sh
./tests/run-docker.sh                 # whole suite
./tests/run-docker.sh review.bats     # a single file
```

The script builds a small image ([`tests/Dockerfile`](tests/Dockerfile): bats + git) on first use
and mounts the repo read-only; tests create their temp repos inside the container, so the host
filesystem is never on the hot path.

On Windows this is not just a convenience. Every test spawns many `git`
processes, and creating a process costs about 50ms there against 1ms on Linux —
`CreateProcess`, the DLL loads and the antivirus scan, all of which Linux's
`fork()` does not do — so a single file can take minutes for the same work the container does in
seconds. Nothing is skipped by running it this way: CI still runs the suite on real Ubuntu, macOS
and Windows runners.

### Trying the commands by hand

The fixtures for `--step` and walk mode live inside the bats `setup()` functions and are deleted by
`teardown()`, so there is nothing left to experiment with.
[`tests/sandbox.sh`](tests/sandbox.sh) builds the same kind of pull request in a directory that
survives the run:

```sh
./tests/sandbox.sh                    # (re)build, then print how to enter it
./tests/sandbox.sh -d /tmp/box        # somewhere other than the default
```

It rebuilds from scratch on every call — break the sandbox however you like and run it again to get
the identical starting state back. The toy pull request (`feature/checkout`) is four commits over
five files (one file touched twice, so
`--step` and walk disagree), with a committed walkthrough whose reading order is not the diff order
and two paths carrying a space and a non-ASCII byte. Nothing in the test suite depends on it; it
exists purely to run the real commands against something realistic.

Around it are the states one well-formed pull request cannot show, one branch each:
`feature/notifications` (a walkthrough annotating two of its four files, so the other two land
unannotated at the end of the reading order),
`feature/telemetry` (no walkthrough — `start` enters whole mode on its own), and
`feature/legacy` (a walkthrough naming paths a rename removed, so the review degrades to whole with
a note). On `develop`, three saved reviews make up the inventory `git review list` prints: one
resumable, one blocked by an active `review/*` for the same branch, and one with no metadata behind
it. Those three are the only part built by *running* the commands rather than by writing the
repository directly — the branch config under
`review-saved/*` is theirs to write, and a second copy of it here would go stale in silence. That
phase fails soft: if a verb is broken the script warns and the rest of the sandbox still comes out
usable.

> The PowerShell installer tests (`*-ps1.bats`) need `pwsh`, which the container
> does not have, so they do not really run there — rely on CI (or local Windows)
> for those.

## The VS Code extension

[`vscode-extension/`](vscode-extension/) is a separate npm project with its own checks, which CI
runs as a second job. It shells out to the `git review` on
`PATH`, so install this checkout (`./install.sh`) before running it in an editor. The tests need no
install: they put this checkout's `bin/` at the front of the `PATH` they hand the test host.

```sh
cd vscode-extension
npm install
npm run watch      # esbuild, rebuilds dist/ on save
```

### Running it in a real editor

Open `vscode-extension/` in VS Code and press F5 (the *Run Extension* launch configuration). That
opens a second window — the Extension Development Host — with the extension loaded from this
checkout; changes need a reload of that window (Developer: Reload Window), not a restart.

The panel only has something to show inside a repository with an active review, so build one with
the [sandbox](#trying-the-commands-by-hand) and open
`<sandbox>/work` in the development host:

```sh
./tests/sandbox.sh                    # from the repo root
git -C <sandbox>/work review start feature/checkout
```

The development host inherits the `PATH` of the VS Code that launched it, not the one the sandbox's
`env.sh` sets up: either install this checkout (`./install.sh`) or point the `gitReview.path`
setting at `bin/git-review`.

### Testing it

```sh
npm run test:unit                        # pure functions, no editor, milliseconds
./vscode-extension/test/run-docker.sh    # integration, in a container
```

The integration suite drives a real editor and a real `git review`, so it runs in a container for
the same reason the bats suite does — 38 seconds there against 16 minutes natively on Windows, for
the same 66 tests. The first run builds the image and downloads a VS Code; after that both live in
named volumes. It loads the extension from `dist/` and rebuilds it first (`pretest:integration`), so
a green run is always about the code you have now.

`npm run test:integration` runs the same suite directly, which is what CI does and what the
container runs inside. Use it when you need the editor on your own machine, and expect it to be slow
on Windows.
[`vscode-extension/CONTRIBUTING.md`](vscode-extension/CONTRIBUTING.md) has the detail, including the
two specs that open editor tabs and are flaky on Windows for reasons that have nothing to do with
the extension.

### Previewing the panel

The webview's HTML is a pure function with no `vscode` import, so the panel's states can be rendered
in an ordinary browser without launching an editor:

```sh
npm run preview        # writes out/preview/index.html and prints its file:// URL
npm run preview:watch  # regenerates on save; reload the browser
```

It shows every state side by side at sidebar width — walk, step, whole and the empty ones — with a
switch for the dark, light and high-contrast themes. The sample states in [
`preview/fixtures.ts`](vscode-extension/preview/fixtures.ts)
are sample `status --porcelain` output run through the real parser and model, so the preview follows
the source instead of being maintained alongside it.

It is only good for the render: the buttons have no extension behind them, and the theme variables
in `preview/build.ts` approximate VS Code's. A `--vscode-*`
variable the panel starts using must be added there too, or it will look wrong in the preview and
fine in the editor. For behaviour, use F5.

## The JetBrains IDE plugin

[`jetbrains-plugin/`](jetbrains-plugin/) is a separate Gradle module (Kotlin + IntelliJ Platform
Plugin). Same rule as the VS Code extension: the CLI is the source of truth; the plugin only invokes
porcelain/argv and paints a
`PanelModel`. Platform pin and versions live only in
[`jetbrains-plugin/gradle.properties`](jetbrains-plugin/gradle.properties). See
[`jetbrains-plugin/CONTRIBUTING.md`](jetbrains-plugin/CONTRIBUTING.md) for the full guide —
building, the sandbox IDE, the tests and the zip.

One zip, many IDEs: compatibility is declared in `plugin.xml` with
`com.intellij.modules.platform` + `Git4Idea`, and Android Studio / Rider are excluded via
`<incompatible-with>`. That is what Marketplace uses — not a product checkbox in Gradle. `runIde`
still boots IntelliJ IDEA as the development host; smoke other products by installing
`build/distributions/*.zip` from disk.

```sh
cd jetbrains-plugin
./gradlew test              # domain unit tests (no IDE)
./gradlew runPanelPreview   # Swing fixtures, no full IDE
./gradlew runIde            # sandbox IDEA host with the plugin loaded
./gradlew verifyPlugin      # pluginVerifier on the claimed multi-IDE set
./gradlew verifyPlugin -PverifierIdes=idea                       # IDEA alone, what CI runs
./gradlew verifyPluginProjectConfiguration verifyPluginStructure # descriptor and configuration
```

All three run on every push and none of their *warnings* fail the build: a since-build below the
target platform, a name the Marketplace will object to, a deprecated or internal API the plugin
reached for. They exit zero and the finding scrolls past in the log, which is how a version gets
published with one nobody read. CI tees the output and `./verification-report.sh <log>` turns it
into GitHub annotations plus a job summary — run it the same way locally over a
`./gradlew ... 2>&1 | tee verification.log`. Real problems still fail their own step.

### Shell: which wrapper?

The Gradle wrapper lives **inside** `jetbrains-plugin/` (not at the monorepo root). Use the form
that matches your shell:

| Shell                          | Command                                           |
|--------------------------------|---------------------------------------------------|
| Git Bash / WSL / Linux / macOS | `cd jetbrains-plugin && ./gradlew runIde`         |
| PowerShell / cmd               | `cd jetbrains-plugin` then `.\gradlew.bat runIde` |

Do **not** run `.\gradlew.bat` from Git Bash (MINGW64) — bash looks for a command named
`.gradlew.bat` and fails with `command not found`. Use
`./gradlew` there.

### Running it in a real IDE (like VS Code F5)

`./gradlew runIde` is the IntelliJ equivalent of opening `vscode-extension/`
and pressing F5: it downloads the pinned IDEA (first run is slow), then opens a **sandbox IDE** with
this checkout’s plugin loaded. It does **not** inject the plugin into the IDEA you already use for
coding.

The tool window only has something useful to show inside a single-root git repo with an active
review, so use the same [sandbox](#trying-the-commands-by-hand)
as for VS Code:

```sh
# from the monorepo root (Git Bash / WSL / Linux / macOS)
./tests/sandbox.sh
git -C <sandbox>/work review start feature/checkout
```

Then in the sandbox IDEA:

1. **File → Open** → `<sandbox>/work` only (one git root; multi-root is not supported).
2. **Settings → Tools → git review → Path to git-review** → absolute path to this checkout’s
   `bin/git-review` if that IDEA’s `PATH` does not see the CLI (same caveat as the VS Code Extension
   Development Host).
3. Open the **git review** tool window (tool window bar / View → Tool Windows).
4. Drive the flow from the panel where buttons exist, and from **Tools → git review** for the full
   action set (Next, Finish, Open, …).

Kotlin changes are not hot-reloaded like `npm run watch` + Reload Window:
rebuild and run `runIde` again (or restart the sandbox IDE after a rebuild).

Product surface (27 actions, situations, critical strings, **and panel layout**)
is checked by:

```sh
# from the monorepo root
node scripts/check-client-product-surface.mjs
# IntelliJ structural layout parity (all OSes in CI):
cd jetbrains-plugin && ./gradlew test
```

### Side-by-side parity check (feature 010)

To validate that the plugin panel offers the same controls, order, labels, and grouping as the VS
Code panel (product parity, not pixels):

```sh
# Terminal A — VS Code panel preview (real panelHtml)
cd vscode-extension && npm run preview

# Terminal B — IntelliJ panel preview (real PanelRenderer)
cd jetbrains-plugin && ./gradlew runPanelPreview
```

Walk the same situations in both windows. Any missing control, wrong order, or relabelled button is
a bug — fix `domain/PanelLayout.kt` or the canonical
`panel_layout:` block, never by loosening the tests.

More validation detail:
[`specs/010-panel-intellij-acciones/quickstart.md`](specs/010-panel-intellij-acciones/quickstart.md)
and [`jetbrains-plugin/CONTRIBUTING.md`](jetbrains-plugin/CONTRIBUTING.md).

### UX vs the VS Code panel

**Parity is product, not pixels.** Both clients share the same CLI contract, the same
action/situation matrix, and the same `panel_layout:` disposition ([
`contracts/client-product-surface.yaml`](contracts/client-product-surface.yaml)). The IntelliJ panel
is **native Swing** on purpose (not a CEF/HTML clone of
`panelHtml.ts`): theming, accessibility, and HiDPI follow the IDE. Layout is a pure domain
projection (`panelLayout`) rendered by a generic Swing
`PanelRenderer`.

So it will *look* different from the VS Code sidebar even when every action exists. Actions that are
“in the panel” in VS Code may appear as tool-window controls **and/or** as `Tools → git review` /
keymap actions in IDEA — that is allowed by the surface contract (`surface: panel | action | both`).
If a control is missing from both the panel and the menu for a situation the YAML enables, that is a
product gap to fix, not a platform limitation.

## The Visual Studio extension

[`visualstudio-extension/`](visualstudio-extension/) is a separate .NET 8 solution with its own
checks. It shells out to the `git review` on `PATH`, same rule as the other two clients — see
[`visualstudio-extension/CONTRIBUTING.md`](visualstudio-extension/CONTRIBUTING.md) for building,
running it in a real Visual Studio, and testing it.

CI runs it on `windows-latest` alone: the VSIX targets net472 and is built by the MSBuild of a
Visual Studio installation, which no other runner has. That last step is the gate — net472 is off
by default (`GitReviewPackVsix`), so a break that only happens there survives every `dotnet build`
and `dotnet test`.

## Releasing

> Maintainers only.

Releases are cut by pushing a `v*` tag.

1. Bump the version everywhere it must agree, then tag that commit. The version lives in several
   files on purpose — `VERSION`, `bin/git-review` and
   `package.json` ship *inside* the tarball (npm publishes the version from
   `package.json`), while the Homebrew formula points *at* it — so
   [`bump-version.sh`](bump-version.sh) stamps all of them from one argument and they can never
   drift out of sync:

   ```sh
   ./bump-version.sh X.Y.Z
   git diff                       # review the stamped files
   git commit -am "Release X.Y.Z"
   git tag vX.Y.Z
   git push origin HEAD --tags
   ```

   The script leaves the formula's `sha256` untouched on purpose: it depends on the tarball GitHub
   builds for the tag, which does not exist until the tag is pushed.

2. The release workflow ([`.github/workflows/release.yml`](.github/workflows/release.yml)) then pins
   that `sha256` (the one thing not known before the tag):

    - creates a GitHub Release for the tag with auto-generated notes,
    - pins the Homebrew formula (`url`, `sha256`, `version`) to the tag on the default branch, so
      `brew install` (without `--HEAD`) installs that version, and
    - publishes the tagged version to npm via Trusted Publishing (OIDC). There is no `NPM_TOKEN`
      secret — the repo and `release.yml` workflow are registered as a trusted publisher on
      npmjs.com, and provenance is attached automatically.

### VS Code extension

Versioned independently of the CLI. Stamp every place that must agree with
[`vscode-extension/bump-version.sh`](vscode-extension/bump-version.sh)
(`package.json` + the package's own entries in `package-lock.json`), then fill the CHANGELOG heading
by hand and package/publish:

```sh
./vscode-extension/bump-version.sh X.Y.Z
git diff vscode-extension/
# move Unreleased notes under ## [X.Y.Z] in vscode-extension/CHANGELOG.md
cd vscode-extension && npm run package   # then publish the .vsix as usual
```

### JetBrains IDE plugin

Versioned independently of the CLI, and released by its own tag namespace:
`v*` cuts a CLI release, `jetbrains-v*` publishes the plugin. The sole source of truth for the
number is `pluginVersion` in
[`jetbrains-plugin/gradle.properties`](jetbrains-plugin/gradle.properties)
(Gradle patches `plugin.xml` and the zip name from it at build time). Stamp it with [
`jetbrains-plugin/bump-version.sh`](jetbrains-plugin/bump-version.sh), fill the CHANGELOG heading by
hand, then tag:

```sh
./jetbrains-plugin/bump-version.sh X.Y.Z
git diff jetbrains-plugin/gradle.properties
# move Unreleased notes under ## [X.Y.Z] in jetbrains-plugin/CHANGELOG.md
git commit -am "Release jetbrains-plugin X.Y.Z"
git tag jetbrains-vX.Y.Z
git push origin HEAD --tags
```

[`.github/workflows/release-jetbrains.yml`](.github/workflows/release-jetbrains.yml)
takes it from there: it refuses to run if the tag disagrees with
`pluginVersion`, runs the tests and the same verifier the Marketplace runs, publishes with
`publishPlugin`, and creates a GitHub Release for the tag with the zip attached and the CHANGELOG
section as notes.

Two things worth knowing about that workflow:

- It needs a `JETBRAINS_MARKETPLACE_TOKEN` repository secret — a permanent token from
  plugins.jetbrains.com (*Profile → My Tokens*) with rights over this plugin. The **first** upload
  of a listing goes through JetBrains review and has to be done by hand; every version after that
  goes over the API.
- The Marketplace rejects a version it already has, which is why the trigger is a tag and not a
  push: "the plugin changed" is only publishable when
  `pluginVersion` changed.

#### What the listing shows, and where it comes from

Everything below travels **inside the zip** — publishing is the only way to change it:

| Listing field | Source |
|---|---|
| Name | `pluginName` in `gradle.properties` |
| Overview body | `<description>` in `plugin.xml` — the **only** copy; `build.gradle.kts` deliberately does not set `pluginConfiguration.description`, which would overwrite it |
| *What's New* / update dialog | the section for this version in `jetbrains-plugin/CHANGELOG.md`, rendered to HTML by the `org.jetbrains.changelog` plugin |
| Icon | `META-INF/pluginIcon.svg` (+ `_dark`), generated — see *Logo assets* |
| Vendor | `<vendor>` in `plugin.xml` |
| Compatible products / builds | `<depends>` + `<incompatible-with>`, and `pluginSinceBuild` |

The **tagline** — the first sentence of that description — is shared with the VS Code and Visual
Studio listings and checked by `scripts/check-client-product-surface.mjs` (`listing.tagline`);
change it in `contracts/client-product-surface.yaml` and all three at once, never in one place.

Everything else on the listing page — **screenshots**, category/tags, source-code and
documentation links, license, pricing — is portal-side: edit it on plugins.jetbrains.com, no
release needed.

To build the zip locally without releasing anything:

```sh
cd jetbrains-plugin && ./gradlew buildPlugin
```
