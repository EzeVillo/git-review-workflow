# git review workflow — IntelliJ IDEA plugin

Native IntelliJ IDEA tool window for [git-review-workflow](https://github.com/EzeVillo/git-review-workflow).
Full action and situation parity with the VS Code extension; state always comes from the CLI porcelain contract.

## Requirements

- IntelliJ IDEA **2026.1+** (build `261+`)
- JDK **21** for building
- A local `git review` CLI (`npm install -g git-review-workflow` or this monorepo’s `./install.sh`)

Platform pin lives only in [`gradle.properties`](./gradle.properties).

## Build & run

The Gradle wrapper lives **in this directory** (not at the monorepo root).

```sh
# Git Bash / WSL / Linux / macOS (from this directory):
./gradlew test              # domain unit tests (all OSes)
./gradlew platformTest      # headless platform tests (Linux CI)
./gradlew runIde            # sandbox IDE with the plugin loaded (≈ VS Code F5)
./gradlew runPanelPreview   # standalone Swing panel preview
./gradlew buildPlugin       # zip under build/distributions/
./gradlew verifyPlugin      # pluginVerifier
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

In the sandbox IDEA: open only `<sandbox>/work`, set
**Settings → Tools → git review → Path to git-review** to this checkout’s
`bin/git-review` if needed, open the **git review** tool window, and use
**Tools → git review** for the full action set.

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
