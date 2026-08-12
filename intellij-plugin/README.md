# git review workflow — JetBrains IDE plugin

Native tool window for [git-review-workflow](https://github.com/EzeVillo/git-review-workflow)
on the IntelliJ Platform. Full action and situation parity with the VS Code
extension; state always comes from the CLI porcelain contract.

## Requirements

- A JetBrains IDE on the IntelliJ Platform **2026.1+** (build `261+`; open-ended
  for later releases): IntelliJ IDEA, WebStorm, PhpStorm, PyCharm, GoLand, CLion,
  RubyMine, RustRover, DataGrip, and any other product that ships the platform
  module plus Git
- **Not** Android Studio or Rider (declared with `<incompatible-with>` in
  `plugin.xml` — the IDE will not offer or load the plugin there)
- JDK **21** for building (platform 2026.1 requirement)
- A local `git review` CLI (`npm install -g git-review-workflow` or this monorepo’s `./install.sh`)

Platform pin lives only in [`gradle.properties`](./gradle.properties). That file
drives `since-build` / `until-build` in the packaged `plugin.xml`. **Which
products** are compatible is not a separate Marketplace enum: it follows from
`<depends>` (`com.intellij.modules.platform` + `Git4Idea`) and the two
`<incompatible-with>` entries. `./gradlew verifyPlugin` checks the claimed set
at the same platform line.

## Build & run

The Gradle wrapper lives **in this directory** (not at the monorepo root).

```sh
# Git Bash / WSL / Linux / macOS (from this directory):
./gradlew test              # domain unit tests (all OSes)
./gradlew platformTest      # headless platform tests (Linux CI)
./gradlew runIde            # sandbox IDE (IntelliJ IDEA host) with the plugin loaded
./gradlew runPanelPreview   # standalone Swing panel preview
./gradlew buildPlugin       # zip under build/distributions/
./gradlew verifyPlugin      # pluginVerifier on the multi-IDE binary set (not AS / Rider)
```

On Windows **PowerShell** / cmd (not Git Bash):

```powershell
cd intellij-plugin
.\gradlew.bat test
.\gradlew.bat runIde
```

In **Git Bash (MINGW64)** use `./gradlew …`, not `.\gradlew.bat` — bash will
not find `.gradlew.bat`.

### Manual smoke (same sandbox as the VS Code extension)

```sh
# monorepo root
./tests/sandbox.sh
git -C <sandbox>/work review start feature/checkout

cd intellij-plugin && ./gradlew runIde
```

In the sandbox IDE: open only `<sandbox>/work`, set
**Settings → Tools → git review → Path to git-review** to this checkout’s
`bin/git-review` if needed, open the **git review** tool window, and use
**Tools → git review** for the full action set. `runIde` boots IntelliJ IDEA as
the development host; install the built zip from disk to smoke WebStorm,
PhpStorm, PyCharm, etc.

Point the setting **git review → path** at this checkout’s `bin/git-review`
when the IDE’s `PATH` does not see the CLI.

### Look & feel

This is a **native Swing** tool window, not a port of the VS Code webview HTML.
**Product parity** (same controls, order, labels, grouping, emphasis, enablement)
is required; pixel-identical layout is not. The panel layout is a pure domain
projection (`panelLayout`) verified against
[`../contracts/client-product-surface.yaml`](../contracts/client-product-surface.yaml)
`panel_layout:`. Compare side-by-side with
`cd vscode-extension && npm run preview` vs `./gradlew runPanelPreview`.

## Panel surface (what each situation offers)

| Situation | Panel body | Title bar |
|-----------|------------|-----------|
| `cli-missing` / `cli-outdated` | Install/update command, **Copy**, **Other install options** | Refresh |
| `no-review` (no base) | **Set the base branch**, Change remote | Refresh |
| `no-review` (ready) | Inventory (Continue / Discard), **Start a review**, collapsible Other actions / Settings / Support | Refresh |
| `finish-pending` | Banner: **Clean** \| **Undo finish** | Refresh |
| `review` walk | Identity bar, notes, entry, why, open in editor, File \| Diff, ◀ \| ▶ | Refresh, Finish, Save, Cancel, Preview edits |
| `review` step | Same without why; Diff only | same |
| `review` whole | File list (one-click Diff per file), Diff-all | same |
| `finish-conflict` | Conflict banner Undo \| Continue; **no** nav row | Refresh, Cancel, Preview edits |
| `out-of-range` / `error` | **How to fix it** + stderr | Refresh |

**Menu only** (not on the panel): Go to Entry, Forget…, Preview Edits (stat),
Show CLI Log — still under **Tools → git review**.

## Architecture

| Layer | Package | Notes |
|-------|---------|--------|
| domain | `com.ezevillo.gitreview.domain` | Pure JVM; includes `PanelLayout` projection |
| host | `…host` | Invoke CLI, refresh, mutation lock |
| vcs | `…vcs` | Sole git root via Git4Idea |
| diff | `…diff` | name-status + DiffManager |
| ui | `…ui` | `PanelRenderer`, `PanelActionDispatcher`, tool window |
| settings | `…settings` | `path`, `defaultSource` |

Canonical multi-client strings, action matrix, and **panel layout** live in
[`../contracts/client-product-surface.yaml`](../contracts/client-product-surface.yaml).
Node checks the VS Code side; `PanelLayoutContractTest` checks IntelliJ.

## Smoke matrix (release)

| OS | smoke |
|----|--------|
| Windows | start walk PR with non-ASCII path; open deleted file; finish |
| macOS | same + tool window theme dark/light |
| Linux | same + `platformTest` in CI |

See `specs/009-plugin-intellij/quickstart.md` for the full checklist.
