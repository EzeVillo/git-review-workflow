# git review workflow — VS Code extension

> Review a pull request by **editing and running** it, not just reading it. The
> whole PR lands in your working tree as one staged diff; your fixes are then
> extracted onto a clean branch automatically. This panel shows where you are in
> the review and drives every step of it without leaving the editor.
>
> And when an **AI agent** wrote the change, it can write the **reading order**
> too — a walkthrough committed next to the code saying which file to read first
> and why. The panel picks it up on its own and walks you through the diff in
> that order, instead of alphabetically.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/EzeVillo/git-review-workflow/blob/main/LICENSE)
[![Requires git review 0.7.0+](https://img.shields.io/badge/requires-git%20review%200.7.0%2B-blue.svg)](https://github.com/EzeVillo/git-review-workflow#installation)

[Project README](https://github.com/EzeVillo/git-review-workflow#readme) · [Website](https://ezevillo.github.io/git-review-workflow/) · [Changelog](https://github.com/EzeVillo/git-review-workflow/blob/main/vscode-extension/CHANGELOG.md)

---

This is the editor surface of
[git-review-workflow](https://github.com/EzeVillo/git-review-workflow), a git
subcommand that stages an entire PR in your working tree as **staged,
uncommitted changes** — so you read the diff, edit it inline and run the tests
like ordinary local work, and `git review finish` then extracts *your* edits
onto a separate branch. The extension does not reimplement any of that: it
drives the same CLI and shows you its state.

> **The CLI is required.** The extension is a panel over `git review`, not a
> standalone reviewer. See [Requirements](#requirements).

## What the panel shows

**A reading order, when the PR has one.** If the author (often an AI coding
agent) committed a walkthrough alongside the change, the review runs in *walk*
mode and the panel shows the current entry: the file, its position in the order
the author chose, whether they marked it `key`, and the *why* they wrote for it.
The full sequence — and the files the walkthrough doesn't cover — is one
keystroke away in a quick pick, and commands jump to the file, advance and go
back without leaving the editor.

**The files the range touches, when it doesn't.** A review without a walkthrough
runs in *whole* mode, and there the panel is the list of changed files: a row
opens that file's diff, and one control above them opens every change at once.
The last row you opened stays marked, so a list you are halfway through still
says where you were after closing the editor.

**Or the reading order you write yourself.** When the PR ships without one, the
start assistant offers *Build a reading order first*: it writes a skeleton
listing every file in the range, and the assistant closes. Nothing waits on you.

The half-written order shows up in the panel, under **Reading orders you
started**, with how far along it is (`3/9`, counted by the CLI) and four
controls on its row — two buttons underneath and two glyphs beside the count:

- **Copy for agent** — puts a one-line instruction naming that file on the
  clipboard, for whatever you want to hand it to. Copying is copying: no
  service is contacted and no assistant is invoked.
- **Validate and start** — validates it (on the CLI, so a rejection tells you
  exactly what to fix, in the CLI's own words) and, when it passes, starts the
  review on your order. It stays switched off, with a tooltip saying why, while
  the order is unfinished or the CLI cannot tell how the draft was generated.
- Beside the count, **open the reading order** — the file, at the path the CLI
  reported — and **discard** it, after a confirmation that names the command.

The count is one unit per entry plus the `## Heads-up` section, which is what
`--build` demands too: it reaches `N/N` exactly when no placeholder is left.
Deleting the whole heads-up section is a legal way to finish it, and the total
drops when you do. The progress follows the file: hand the draft to an agent
and the count moves on its own as it writes, with nobody hitting Refresh.

It survives closing the editor, so a reading order you started on Friday is the
first thing the panel says on Monday. The draft is **yours and local**: it lives
outside the working tree, never gets committed or staged, and `git status` does
not change at any point. Nothing about it is written for you; it is a file you
fill in. Once it is in, the review reads it exactly like an author's
walkthrough, and the panel marks the mode `(draft)` so it is clear whose reading
order you are on.

**Your other reviews, when this branch has none.** With no review on the current
branch the panel lists the ones open elsewhere in the repository — active and
saved, with their mode and position — so a review you put aside doesn't have to
be remembered by name. Saved ones offer *Continue*; an active one is listed
without an action, because going back to it is a branch checkout and the
editor's branch picker already does that.

## Getting started

1. **Install the CLI.** With Node:

   ```sh
   npm install -g git-review-workflow
   ```

   Homebrew, a native Windows (PowerShell) installer and a no-Node one-liner are
   all in the
   [installation guide](https://github.com/EzeVillo/git-review-workflow#installation).

2. **Tell it where PRs are integrated,** once per repository — from the panel
   (*git review: Set the Base Branch*) or on the command line:

   ```sh
   git config reviewworkflow.base develop
   ```

3. **Open the git review panel** in the activity bar and hit *Start a review*.
   It asks for the branch, where to read it from, the range, and how to read it
   — offering only the layouts the CLI reports as viable for that PR. (Or run
   `git review start feature/login` in a terminal; the panel follows.)

## Panel actions

Everything below is a command the panel exposes. Lifecycle actions (Finish,
Save, Cancel, Preview and Refresh) are icon buttons on the view title bar; the
rest are buttons inside the panel or entries in the Command Palette, all under
the **git review** category.

Each one shells out to the matching `git review` verb — the extension never
invents a second way to change review state.

| Action                       | When it appears                                                                              | CLI                                                          |
|------------------------------|----------------------------------------------------------------------------------------------|--------------------------------------------------------------|
| **Start a review**           | Empty state; also the palette after a finished review, if the tree is clean                  | `git review start …`                                         |
| **Next / Previous entry**    | While a walk or step review is open                                                          | `git review next` / `prev`                                   |
| **Go to entry**              | While a review is open — the quick pick with the whole sequence                              | *(navigation only)*                                          |
| **Open entry / Open changes**| While a review is open — opens the file or its diff                                          | *(opens the editor's diff view)*                             |
| **Finish review**            | Title bar, while an active review is open (hidden on a read-only compare)                    | `git review finish` / `--onto-source`                        |
| **Save for later**           | Title bar, while an active review is open                                                    | `git review save`                                            |
| **Cancel review**            | Title bar, while an active review (or a mid-conflict finish) is open                         | `git review abort`                                           |
| **Preview edits**            | Title bar or palette, while a review is open; optional diffstat                              | `git review preview` / `--stat`                              |
| **Undo finish**              | After a finish, while undo is still available — including one stopped mid-conflict           | `git review finish --abort`                                  |
| **Continue** (finish)        | A finish stopped mid-conflict, once you resolve the markers in the tree                      | `git review finish --resume`                                 |
| **Clean**                    | After a finished review; also the palette for any leftover                                   | `git review clean [--keep-fixes] [<branch>]`                 |
| **Continue** (saved review)  | Inventory row for a review paused with *Save for later*                                      | `git review continue <branch>`                               |
| **Discard / Forget**         | Inventory row, or the palette for saved reviews and `--delta` markers                        | `git review forget --saved` / `--delta`, `git review clean`  |
| **Compare revisions**        | Empty state, under Start; also the palette. The result is **read-only** — no writeback       | `git review compare <a> <b>`                                 |
| **Walkthrough: Init / Build**| Empty state, under Start (this is the *author* flow); also the palette                       | `git review walkthrough init` / `build`                      |
| **Build a reading order first** | Inside *Start a review*, at the reading-order step, when the PR has none (the *reviewer* flow) | `git review walkthrough draft`                            |
| **Copy for agent / Validate and start / open / discard** | A row of *Reading orders you started*, in the empty state | `git review walkthrough draft --build`, `git review start`, `git review forget --draft` |

Mutations (the lifecycle actions, clean, forget, compare and writing a
walkthrough) ask for a confirmation that names what will happen. Preview is
read-only and does not.

A finished review is **not** the empty state: the panel names where your staged
edits landed — `review-fixes/<branch>`, or the PR branch itself with
`--onto-source` — and offers *Clean* (drop the leftover undo point, keep the
edits) or *Undo finish*. Commit and push those edits from Source Control as
usual. A finish stopped mid-conflict keeps the review readable (mode, branch,
current entry) but locks navigation until you *Continue* or *Undo finish*.

## Requirements

- **VS Code 1.75** or newer.
- **[git-review-workflow](https://github.com/EzeVillo/git-review-workflow) 0.7.0
  or newer**, discoverable as a git subcommand (`git review -h` works), or
  pointed at directly with the `gitReview.path` setting.
- A **single-folder workspace.** Multi-root workspaces are not supported: the
  panel needs exactly one git repository root, the same way the CLI has one cwd.
  Open the repository folder on its own, or pick one root and open that.
- On Windows the CLI itself runs under **Git Bash**, which
  [Git for Windows](https://gitforwindows.org) provides.

## Settings

| Setting                    | Default    | What it does                                                                                                                                |
|----------------------------|------------|---------------------------------------------------------------------------------------------------------------------------------------------|
| `gitReview.path`           | *(empty)*  | Path to the `git-review` dispatcher, for when `git` does not discover it. Empty means the extension invokes `git review`.                    |
| `gitReview.defaultSource`  | `remote`   | Which origin the start wizard preselects: `remote` (fetch and review the remote tip), `local` (no fetch), `offline` (no network at all).     |

### `gitReview.path` on Windows

On Windows, a bare POSIX path such as `…/bin/git-review` — no `.cmd`, `.bat` or
`.exe` extension — is spawned through `sh`, which only works if Git Bash's `sh`
is on your `PATH`. Prefer one of:

- leave `gitReview.path` empty and install the CLI so that `git review` works as
  a subcommand (npm or the PowerShell installer both set that up), or
- point `gitReview.path` at a **Windows-native** shim — the `.cmd` an npm global
  install leaves behind, for example.

If spawning fails with `ENOENT` while `gitReview.path` points at an
extensionless file, the cause is the missing `sh`, not a missing CLI.

## Troubleshooting

The panel reports what it found rather than failing silently — a missing CLI, a
version too old, a repository with no base configured — and offers the action
that fixes it. When you need the detail, **git review: Show CLI Log** prints
every invocation the extension made and what came back.

## Learn more

- [Project README](https://github.com/EzeVillo/git-review-workflow#readme) — the
  full command surface, the walkthrough format, and how the workflow fits
  together. Also in
  [Spanish](https://github.com/EzeVillo/git-review-workflow/blob/main/README.es.md).
- [Website](https://ezevillo.github.io/git-review-workflow/)
- [Issues](https://github.com/EzeVillo/git-review-workflow/issues)
- [Contributing to the extension](https://github.com/EzeVillo/git-review-workflow/blob/main/vscode-extension/CONTRIBUTING.md)
  — running it from source, tests, and the panel preview.

## License

[MIT](https://github.com/EzeVillo/git-review-workflow/blob/main/LICENSE) ©
EzeVillo
