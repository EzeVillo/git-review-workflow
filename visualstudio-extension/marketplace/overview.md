# git review workflow for Visual Studio

**Walk a PR in order, then edit and run it — not just read the diff.**

Native Visual Studio client for [git-review-workflow](https://github.com/EzeVillo/git-review-workflow). Same product surface as the [VS Code extension](https://github.com/EzeVillo/git-review-workflow/tree/main/vscode-extension) and the [JetBrains plugin](https://github.com/EzeVillo/git-review-workflow/tree/main/jetbrains-plugin): start, walk / step / whole, finish, save, abort, and housekeeping — all driven by the `git review` CLI porcelain contract.

## What you get

- **Tool-window panel** with the same English labels and button order as the other clients (theme colors only differ).
- **Reading order** when the PR ships a walkthrough (or when you draft one): file, position, `key` badges, and the author's *why*.
- **Whole-range file list** when there is no walkthrough: open one diff or every change at once.
- **Inventory** of other reviews in the repo when this branch has none: continue saved reviews, discard orphans.
- **Finish / undo / clean** flows with the same confirmations as VS Code and JetBrains.

## Requirements

| | |
|---|---|
| IDE | Visual Studio **2022** (17.x) or later — **Windows only** |
| CLI | [`git-review-workflow`](https://www.npmjs.com/package/git-review-workflow) **≥ 0.6.0** |
| Git | `git` on `PATH` |

```powershell
npm install -g git-review-workflow
```

Also: Homebrew, a native Windows installer, and a no-Node one-liner — see the [main README](https://github.com/EzeVillo/git-review-workflow#readme).

## Getting started

1. Install the CLI (above).
2. Install this extension from the Visual Studio Marketplace (or load the `.vsix` locally).
3. Open a single-folder git repository.
4. Open the **git review** tool window (View → Other Windows / Tools → git review).
5. **Set the base branch** once, then **Start a review**.

The extension never invents review state: every refresh is `git review status --porcelain` (and related porcelain verbs). Multi-root solutions are not supported — same rule as the CLI `cwd`.

## Privacy

No telemetry. No network calls except the ones you trigger through the CLI (`start` may fetch; `forget --delta --stale` may fetch). Support links open GitHub in your browser.

## Links

- [Source & docs](https://github.com/EzeVillo/git-review-workflow/tree/main/visualstudio-extension)
- [CLI project](https://github.com/EzeVillo/git-review-workflow)
- [Report a bug](https://github.com/EzeVillo/git-review-workflow/issues/new?template=bug_report.yml)
- [License (MIT)](https://github.com/EzeVillo/git-review-workflow/blob/main/visualstudio-extension/LICENSE)
