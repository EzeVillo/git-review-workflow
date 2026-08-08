# git review workflow — IntelliJ IDEA plugin

Native IntelliJ IDEA tool window for [git-review-workflow](https://github.com/EzeVillo/git-review-workflow).
Full action and situation parity with the VS Code extension; state always comes from the CLI porcelain contract.

## Requirements

- IntelliJ IDEA **2026.1+** (build `261+`)
- JDK **21** for building
- A local `git review` CLI (`npm install -g git-review-workflow` or this monorepo’s `./install.sh`)

Platform pin lives only in [`gradle.properties`](./gradle.properties).

## Build & run

```sh
# From this directory (wrapper lives here, not at the monorepo root):
./gradlew test              # domain unit tests (all OSes)
./gradlew platformTest      # headless platform tests (Linux CI)
./gradlew runIde            # sandbox IDE with the plugin loaded
./gradlew runPanelPreview   # standalone Swing panel preview
./gradlew buildPlugin       # zip under build/distributions/
./gradlew verifyPlugin      # pluginVerifier
```

On Windows PowerShell:

```powershell
cd intellij-plugin
.\gradlew.bat test
.\gradlew.bat runIde
```


Point the setting **git review → path** at this checkout’s `bin/git-review` when the IDE’s `PATH` does not see the CLI.

## Architecture

| Layer | Package | Notes |
|-------|---------|--------|
| domain | `com.ezevillo.gitreview.domain` | Pure JVM; no `com.intellij` imports |
| host | `…host` | Invoke CLI, refresh, mutation lock |
| vcs | `…vcs` | Sole git root via Git4Idea |
| diff | `…diff` | name-status + DiffManager |
| ui | `…ui` | Tool window + Swing panel |
| settings | `…settings` | `path`, `defaultSource` |

Canonical multi-client strings and the action matrix live in
[`../contracts/client-product-surface.yaml`](../contracts/client-product-surface.yaml).

## Smoke matrix (release)

| OS | smoke |
|----|--------|
| Windows | start walk PR with non-ASCII path; open deleted file; finish |
| macOS | same + tool window theme dark/light |
| Linux | same + `platformTest` in CI |

See `specs/009-plugin-intellij/quickstart.md` for the full checklist.
