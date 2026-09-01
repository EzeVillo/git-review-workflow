# Contributing to the JetBrains IDE plugin

This covers working *on* the plugin. For what it does and how to use it, see the
[README](README.md); for the CLI and the workflow itself, the
[project README](../README.md) and [CONTRIBUTING.md](../CONTRIBUTING.md) at the
root.

## The CLI is the only source of truth

The plugin never derives review state on its own. Everything it shows comes from
re-invoking `git review status --porcelain` / `--why` / `list --porcelain` and
reading the result. If the panel needs something the CLI does not report, it
gets added to the CLI — never computed here.

| Layer | Package | Notes |
|-------|---------|--------|
| domain | `com.ezevillo.gitreview.domain` | Pure JVM, no `com.intellij`; includes the `PanelLayout` projection |
| host | `…host` | Invoke the CLI (`GeneralCommandLine`, UTF-8), refresh, mutation lock |
| vcs | `…vcs` | Sole git root via Git4Idea |
| diff | `…diff` | name-status + DiffManager |
| ui | `…ui` | `PanelRenderer`, `PanelActionDispatcher`, tool window |
| settings | `…settings` | `path`, `defaultSource` |

The canonical multi-client strings, action matrix and **panel layout** live in
[`../contracts/client-product-surface.yaml`](../contracts/client-product-surface.yaml).
`PanelLayoutContractTest` checks this client against it on every `./gradlew test`.

## Developing

The Gradle wrapper lives **in this directory**, not at the monorepo root.

```sh
# Git Bash / WSL / Linux / macOS (from this directory):
./gradlew test              # domain, host and diff unit tests (all OSes)
./gradlew runIde            # sandbox IDE (IntelliJ IDEA host) with the plugin loaded
./gradlew runPanelPreview   # standalone Swing panel preview
./gradlew buildPlugin       # zip under build/distributions/
./gradlew verifyPlugin      # pluginVerifier on the multi-IDE binary set (not AS / Rider)
```

Use the wrapper form that matches your shell:

| Shell                          | Command                                     |
|--------------------------------|---------------------------------------------|
| Git Bash / WSL / Linux / macOS | `./gradlew runIde`                          |
| PowerShell / cmd               | `.\gradlew.bat runIde`                      |

Do **not** run `.\gradlew.bat` from Git Bash (MINGW64) — bash looks for a command
named `.gradlew.bat` and fails with `command not found`.

### Running it in a real IDE

`./gradlew runIde` is this client's equivalent of F5 in VS Code: it downloads the
pinned IDEA (first run is slow) and opens a **sandbox IDE** with this checkout's
plugin loaded. It does not touch the IDEA you code in.

The tool window only has something to show inside a single-root git repo with an
active review, so build one first:

```sh
# monorepo root
./tests/sandbox.sh
git -C <sandbox>/work review start feature/checkout

# or ./tests/sandbox-min.sh for the empty twin: no walkthrough and no configured
# base, which is the only way to reach the panel's setup screen

cd jetbrains-plugin && ./gradlew runIde
```

In the sandbox IDE: **File → Open** `<sandbox>/work` only (one git root), set
**Settings → Tools → git review → Path to git-review** to this checkout's
`bin/git-review` if that IDE's `PATH` does not see the CLI, open the **git
review** tool window, and use **Tools → git review** for the full action set.
Kotlin changes are not hot-reloaded — rebuild and run `runIde` again.

`runIde` boots IntelliJ IDEA as the development host; to smoke WebStorm,
PhpStorm, PyCharm and the rest, install `build/distributions/*.zip` from disk.

### Look and feel

The tool window is **native Swing** on purpose, not a port of the VS Code webview
HTML: theming, accessibility and HiDPI follow the IDE. Layout is a pure domain
projection (`panelLayout` in `domain/PanelLayout.kt`) rendered by a generic
`ui/PanelRenderer.kt`, so a control that is missing, out of order or relabelled is
fixed in the projection or in the canonical `panel_layout:` block — never by
loosening the tests. `./gradlew runPanelPreview` renders every situation the panel
can reach without booting an IDE.

## Testing

```sh
./gradlew test              # domain + host + PanelLayoutContractTest, every OS in CI
./gradlew verifyPlugin -PverifierIdes=idea                       # what CI runs
./gradlew verifyPluginProjectConfiguration verifyPluginStructure # descriptor and configuration
```

```sh
# from the monorepo root — all three client trees at once
node scripts/check-client-product-surface.mjs
```

**What `test` reaches, and what it does not.** Everything that *receives* what it
uses is covered without an IDE: `PanelRenderer` takes a `PanelChrome` and
`ReviewStateManager` takes a `CliRunner`, so both run against a fake in plain
JUnit. Everything that *reaches for* what it uses is not covered at all —
anything holding a `Project` or calling a static `getInstance()`:
`MutationActions`, `GitReviewService`, `StartWizard`, `PanelActionDispatcher`,
`OpenEntryActions` and every `AnAction` under `ui/actions/`. Constructing those
needs a live IDE application, which means the platform test framework, and it
has never been wired (the one commented line in
[`build.gradle.kts`](build.gradle.kts) is where that is recorded). There used to
be a `platformTest` task and a CI step by that name; the task only re-ran
`test`, so a step promising platform coverage delivered a second run of these
unit tests. It is gone — the way to cover that code is another seam or the
harness, not a green step.

**All three verifications run on every push, and none of their *warnings* fails
the build:** a `since-build` below the platform being compiled against, a name the
Marketplace will object to, a deprecated / internal / experimental API the plugin
reached for. They exit zero and the finding scrolls past in the log, which is how
a version gets published with one nobody read. CI tees the output and
[`verification-report.sh`](verification-report.sh) turns it into GitHub
annotations plus a job summary — run it locally the same way, over a
`./gradlew … 2>&1 | tee verification.log`. Real incompatibilities still fail their
own step.

**In CI the verifier runs against IDEA alone** (`-PverifierIdes=idea`); the eight
products go in the release only. Each entry in `pluginVerification.ides` is an IDE
Gradle downloads as a dependency, and the full set does not fit in the repo's
10 GB of Actions cache — it would fill it and evict the platform the release
restores. What CI is after there is the API usage, which comes out the same
against any of the eight; per-product binary compatibility is still verified in
full before anything is published.

### Release smoke matrix

| OS | smoke |
|----|--------|
| Windows | start walk PR with non-ASCII path; open deleted file; finish |
| macOS | same + tool window theme dark/light |
| Linux | same |

Full checklist: [`specs/009-plugin-intellij/quickstart.md`](../specs/009-plugin-intellij/quickstart.md).

## Packaging

`pluginVersion` in [`gradle.properties`](gradle.properties) is the sole source of
truth — Gradle patches `plugin.xml` and the zip name from it at build time. Stamp
it with one argument, no hand edits:

```sh
./bump-version.sh X.Y.Z   # from this directory
# or from the monorepo root: ./jetbrains-plugin/bump-version.sh X.Y.Z
# then move Unreleased notes under ## [X.Y.Z] in CHANGELOG.md
./gradlew buildPlugin
```

That CHANGELOG step is not bookkeeping: the `## [X.Y.Z]` section is rendered into
`<change-notes>` in the packaged descriptor, which is the Marketplace *What's New*
tab and the release notes the IDE shows before updating. Build without it and the
listing falls back to a link to the file.

The **platform pin** lives only in [`gradle.properties`](gradle.properties), which
drives `since-build` / `until-build` in the packaged `plugin.xml`. **Which
products** are compatible is not a separate Marketplace enum: it follows from
`<depends>` (`com.intellij.modules.platform` + `Git4Idea`) and the two
`<incompatible-with>` entries.

The [`<description>`](src/main/resources/META-INF/plugin.xml) in `plugin.xml` is
the Marketplace listing body and the only copy of it — `build.gradle.kts`
deliberately does not set `pluginConfiguration.description`, which would overwrite
it at package time. Its first sentence is the shared product tagline, checked by
`node ../scripts/check-client-product-surface.mjs`; change it in
[`../contracts/client-product-surface.yaml`](../contracts/client-product-surface.yaml),
never in one client alone.

Releases go out on their own tag namespace (`jetbrains-v*`, while `v*` cuts a CLI
release) — see *Releasing → JetBrains IDE plugin* in the
[root CONTRIBUTING.md](../CONTRIBUTING.md).
