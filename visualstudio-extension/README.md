# git review workflow — Visual Studio

<p align="center">
  <img src="media/icon.png" width="128" height="128" alt="git review workflow icon" />
</p>

**Walk a PR in order, then edit and run it — not just read the diff.**

Native Visual Studio client for
[git-review-workflow](https://github.com/EzeVillo/git-review-workflow). Full
action and situation parity with the
[VS Code extension](../vscode-extension/README.md) and the
[JetBrains plugin](../jetbrains-plugin/README.md); state always comes from the
CLI porcelain contract.

| | |
|---|---|
| **Marketplace id** | `com.ezevillo.gitreview.vs` |
| **Publisher** | EzeVillo |
| **License** | [MIT](./LICENSE) |
| **Icon** | Same product mark as VS Code / JetBrains ([`media/icon.png`](./media/icon.png)) |

> **The CLI is required.** This is a panel over `git review`, not a standalone
> reviewer. See [Requirements](#requirements).

## What the panel shows

**A reading order, when the PR has one.** Walk mode shows the current entry: the
file, its position in the author’s order, `key` badges, and the *why*. Commands
open the file or diff and move with prev/next without leaving Visual Studio.

**The files the range touches, when it doesn’t.** Whole mode lists every changed
file; one control opens all diffs. The last opened row stays marked.

**Or the reading order you write yourself.** Start offers *Walkthrough — draft
one*; the panel marks the mode `(draft)` so it is clear whose order you are on.

**Your other reviews, when this branch has none.** Inventory of active and saved
reviews with Continue / Discard — same labels as the other clients.

## Requirements

- **Windows** (Visual Studio is Windows-only)
- Visual Studio **2022** (17.x) or later
- .NET 8 SDK (to build from source)
- `git` on `PATH`
- `git-review` CLI **≥ 0.6.0**

```powershell
npm install -g git-review-workflow
```

## Marketplace package assets

| Asset | Location |
|-------|----------|
| Listing overview | [`marketplace/overview.md`](./marketplace/overview.md) |
| Publish checklist + screenshot plan | [`marketplace/publish-notes.md`](./marketplace/publish-notes.md) |
| Icon (VSIX) | `src/GitReview.VS/Resources/Icon.png` (+ 90 / 128 / 256) |
| Icon (docs) | `media/icon.png` |
| License | [`LICENSE`](./LICENSE) |
| Changelog | [`CHANGELOG.md`](./CHANGELOG.md) |
| VSIX identity / description / tags | `src/GitReview.VS/source.extension.vsixmanifest` |

Screenshots for the gallery are **not** baked into the VSIX; capture them from
`--preview` and upload in the Marketplace portal (see publish notes).

## Architecture

- **Domain** (`GitReview.Domain`) — pure C#, no Visual Studio APIs. Mechanical
  port of `jetbrains-plugin/.../domain/`.
- **Host** (`GitReview.Host`) — CLI invoker (`shell: false`, UTF-8, timeouts
  15s / 120s / 300s), review state refresh, mutation lock.
- **UI** (`GitReview.VS`) — WPF `PanelView` renders `PanelLayout` in the **same
  order with the same English labels** as JetBrains / VS Code. Only colors
  follow the host theme.

Canonical contract:
[`contracts/client-product-surface.yaml`](../contracts/client-product-surface.yaml).

## Build & test

```powershell
cd visualstudio-extension
dotnet build GitReview.sln
dotnet run --project src/GitReview.VS -- --verify    # layout + constant smoke
dotnet run --project src/GitReview.VS -- --preview   # all situations, ←/→
```

```bash
node ../scripts/check-client-product-surface.mjs   # three client trees
```

### VSIX packaging

Builds the extension itself (net472, the framework devenv loads in-proc) with
MSBuild from your Visual Studio install — no SDK workload required, the VSSDK
comes from NuGet:

```powershell
./build-vsix.ps1                          # src/GitReview.VS/bin/Release/net472/*.vsix
./build-vsix.ps1 -Install -Experimental   # then: devenv /rootsuffix Exp
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for running it inside Visual Studio.

## Visual parity (labels)

| Situation | Controls (canonical English) |
|-----------|------------------------------|
| cli-missing | install title, npm command + **Copy**, **Other install options** |
| no-review setup | **Set the base branch** (primary) |
| no-review ready | inventory, **Start a review**, Other actions / Settings / Support |
| finish-pending | **Clean** / **Undo finish** |
| review walk | **File** / **Diff**, prev/next, **open in editor** |
| review whole | **Diff** (open all) + file rows |
| finish-conflict | **Undo** / **Continue** (no nav) |

Tool window toolbar: **Refresh**, **Finish**, **Save**, **Cancel**, **Preview edits** — the same five title actions, in the same order, as the VS Code view title and the IntelliJ tool-window title bar. Each appears only in the situations the contract gives it.

## Windows latency

`git review status --porcelain` is multi-process on Windows (~960 ms in monorepo
notes). The panel budgets skeleton **120 ms**, why ceiling **800 ms**, CLI probe
every **10 s** on cli-missing/outdated, timeouts 15s / 120s / 300s.

## Version

```sh
./bump-version.sh X.Y.Z
```

Stamps `GitReview.VS.csproj`, `source.extension.vsixmanifest`, and
`Directory.Build.props`. Move Unreleased notes under `## [X.Y.Z]` in
`CHANGELOG.md` before publishing.

## Links

- [Star on GitHub](https://github.com/EzeVillo/git-review-workflow)
- [Report a bug](https://github.com/EzeVillo/git-review-workflow/issues/new?template=bug_report.yml)
- [Main project README](../README.md)
