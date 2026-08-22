# git review workflow — JetBrains IDE plugin

> Review a pull request by **editing and running** it, not just reading it. The
> whole PR lands in your working tree as one staged diff; your fixes are then
> extracted onto a clean branch automatically. This tool window shows where you
> are in the review and drives every step of it without leaving the IDE.
>
> And when an **AI agent** wrote the change, it can write the **reading order**
> too — a walkthrough committed next to the code saying which file to read first
> and why. The panel picks it up on its own and walks you through the diff in
> that order, instead of alphabetically.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](../LICENSE)
[![Requires git review 0.7.0+](https://img.shields.io/badge/requires-git%20review%200.7.0%2B-blue.svg)](https://github.com/EzeVillo/git-review-workflow#installation)

[Project README](../README.md) · [Website](https://ezevillo.github.io/git-review-workflow/) · [Changelog](./CHANGELOG.md)

---

This is the IntelliJ Platform surface of
[git-review-workflow](https://github.com/EzeVillo/git-review-workflow), a git
subcommand that stages an entire PR in your working tree as **staged,
uncommitted changes** — so you read the diff, edit it inline and run the tests
like ordinary local work, and `git review finish` then extracts *your* edits
onto a separate branch. The plugin does not reimplement any of that: it drives
the same CLI and shows you its state.

> **The CLI is required.** This is a tool window over `git review`, not a
> standalone reviewer. See [Requirements](#requirements).

## What the tool window shows

**A reading order, when the PR has one.** If the author (often an AI coding
agent) committed a walkthrough alongside the change, the review runs in *walk*
mode and the panel shows the current entry: the file, its position in the order
the author chose, whether they marked it `key`, and the *why* they wrote for it.
The whole sequence is one action away (*Go to Entry*), and the file, its diff
and prev/next are on the panel itself.

**The files the range touches, when it doesn't.** A review without a walkthrough
runs in *whole* mode, and there the panel is the list of changed files: a row
opens that file's diff, and one control above them opens every change at once.
The last row you opened stays marked.

**Or the reading order you write yourself.** When the PR ships without one,
*Start a review* offers *Build a reading order first*: it writes a skeleton
listing every file in the range and closes the wizard — nothing waits on you.
The half-written order then shows up in the panel under **Reading orders you
started**, with how far along it is (`3/9`, counted by the CLI) and four
controls on its row: *Copy for agent*, *Validate and start*, and two glyphs
beside the count that open the file at the path the CLI reported and discard it.
The progress follows the file, so handing the draft to an agent moves the count
on its own, with nobody hitting Refresh. The draft is **yours and local**: it
lives outside the working tree, is never committed or staged, and `git status`
does not change at any point. Once it is in, the review reads it exactly like an
author's walkthrough and the panel marks the mode `(draft)`.

**Your other reviews, when this branch has none.** With no review on the current
branch the panel lists the ones open elsewhere in the repository — active and
saved, with their mode and position. Saved ones offer *Continue*; an active one
is listed without an action, because going back to it is a branch checkout the
IDE's branch widget already does.

## Getting started

1. **Install the CLI.** With Node:

   ```sh
   npm install -g git-review-workflow
   ```

   Homebrew, a native Windows (PowerShell) installer and a no-Node one-liner are
   all in the [installation guide](../README.md#installation).

2. **Tell it where PRs are integrated,** once per repository — from the panel
   (**Set the base branch**) or on the command line:

   ```sh
   git config reviewworkflow.base develop
   ```

3. **Open the `git review` tool window** and hit **Start a review**. It asks for
   the branch, where to read it from, the range, and how to read it — offering
   only the layouts the CLI reports as viable for that PR. (Or run
   `git review start feature/login` in a terminal; the panel follows.)

The full action set lives under **Tools → git review**.

## What the panel offers, situation by situation

| Situation | Panel body | Title bar |
|-----------|------------|-----------|
| `cli-missing` / `cli-outdated` | Install/update command, **Copy**, **Other install options** | Refresh |
| `no-review` (no base) | **Set the base branch**, Change remote | Refresh |
| `no-review` (ready) | Inventory (Continue / Discard), **Start a review**, collapsible Other actions / Walkthrough (Init or Update, Build, the row for the walkthrough you wrote, the two authoring guides) / Settings / Support | Refresh |
| `finish-pending` | Banner: **Clean** \| **Undo finish** | Refresh |
| `review` walk | Identity bar, notes, entry, why, open in editor, File \| Diff, ◀ \| ▶, folded Walkthrough (the two authoring guides) | Refresh, Finish, Save, Cancel, Preview edits |
| `review` step | Same without why; Diff only | same |
| `review` whole | File list (one-click Diff per file), Diff-all | same |
| `finish-conflict` | Conflict banner Undo \| Continue; **no** nav row | Refresh, Cancel, Preview edits |
| `out-of-range` / `error` | **How to fix it** + stderr | Refresh |

**Menu only** (not on the panel): Go to Entry, Forget…, Preview Edits (stat),
Show CLI Log — still under **Tools → git review**.

Each action shells out to the matching `git review` verb — the plugin never
invents a second way to change review state. Mutations ask for a confirmation
that names what will happen; preview is read-only and does not.

## Requirements

- A JetBrains IDE on the IntelliJ Platform **2026.1+** (build `261+`; open-ended
  for later releases): IntelliJ IDEA, WebStorm, PhpStorm, PyCharm, GoLand, CLion,
  RubyMine, RustRover, DataGrip, and any other product that ships the platform
  module plus Git
- **Not** Android Studio or Rider (declared with `<incompatible-with>` in
  `plugin.xml` — the IDE will not offer or load the plugin there)
- **[git-review-workflow](https://github.com/EzeVillo/git-review-workflow) 0.7.0
  or newer** (`npm install -g git-review-workflow`), discoverable as a git
  subcommand (`git review -h` works) or pointed at directly with the **path**
  setting
- A **single-root project.** The panel needs exactly one git repository root,
  the same way the CLI has one cwd

## Settings

**Settings → Tools → git review**:

| Setting | Default | What it does |
|---------|---------|--------------|
| **Path to git-review** | *(empty)* | Path to the `git-review` dispatcher, for when `git` does not discover it. Empty means the plugin invokes `git review`. |
| **Default source** | `remote` | Which origin the start wizard preselects: `remote` (fetch and review the remote tip), `local` (no fetch), `offline` (no network at all). |

## Troubleshooting

The panel reports what it found rather than failing silently — a missing CLI, a
version too old, a repository with no base configured — and offers the action
that fixes it. When you need the detail, **Tools → git review → Show CLI Log**
prints every invocation the plugin made and what came back.

## Learn more

- [Project README](../README.md) — the full command surface, the walkthrough
  format, and how the workflow fits together. Also in
  [Spanish](../README.es.md).
- [Website](https://ezevillo.github.io/git-review-workflow/)
- [Issues](https://github.com/EzeVillo/git-review-workflow/issues)
- [Contributing to the plugin](CONTRIBUTING.md) — building it, running it in a
  sandbox IDE, the tests and the release flow.

## License

[MIT](../LICENSE) © EzeVillo
