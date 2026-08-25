# git review workflow — Visual Studio extension

<p align="center">
  <img src="media/icon.png" width="128" height="128" alt="git review workflow icon" />
</p>

> Review a pull request by **editing and running** it, not just reading it. The
> whole PR lands in your working tree as one staged diff; your fixes are then
> extracted onto a clean branch automatically. This tool window shows where you
> are in the review and drives every step of it without leaving Visual Studio.
>
> And when an **AI agent** wrote the change, it can write the **reading order**
> too — a walkthrough committed next to the code saying which file to read first
> and why. The panel picks it up on its own and walks you through the diff in
> that order, instead of alphabetically.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Requires git review 0.7.0+](https://img.shields.io/badge/requires-git%20review%200.7.0%2B-blue.svg)](https://github.com/EzeVillo/git-review-workflow#installation)

[Project README](../README.md) · [Website](https://ezevillo.github.io/git-review-workflow/) · [Changelog](./CHANGELOG.md)

---

This is the Visual Studio surface of
[git-review-workflow](https://github.com/EzeVillo/git-review-workflow), a git
subcommand that stages an entire PR in your working tree as **staged,
uncommitted changes** — so you read the diff, edit it inline and run the tests
like ordinary local work, and `git review finish` then extracts *your* edits
onto a separate branch. The extension does not reimplement any of that: it
drives the same CLI and shows you its state.

> **The CLI is required.** This is a panel over `git review`, not a standalone
> reviewer. See [Requirements](#requirements).

## What the panel shows

**A reading order, when the PR has one.** If the author (often an AI coding
agent) committed a walkthrough alongside the change, the review runs in *walk*
mode and the panel shows the current entry: the file, its position in the order
the author chose, whether they marked it `key`, and the *why* they wrote for it.
Commands open the file or its diff and move with prev/next without leaving
Visual Studio.

**The files the range touches, when it doesn't.** A review without a walkthrough
runs in *whole* mode, and there the panel is the list of changed files: a row
opens that file's diff. The last row you opened stays marked.

**Or the reading order you write yourself.** When the PR ships without one,
*Start a review* offers to draft one: it writes a skeleton listing every file in
the range, the panel lists it under **Reading orders you started** with how far
along it is (`3/9`, counted by the CLI), and *Validate and start* runs the review
on your order once it is complete. The draft is **yours and local** — it lives
outside the working tree, is never committed or staged, and `git status` does not
change at any point. The panel marks the mode `(draft)` so it is clear whose
order you are on. Once its review is over the draft stays on disk but moves to
**Reading orders you finished with**, collapsed at the bottom, where it can still
be opened or thrown away.

**Your other reviews, when this branch has none.** With no review on the current
branch the panel lists the ones open elsewhere in the repository — active and
saved, with their mode and position. Saved ones offer *Continue*; an active one
is listed without an action, because going back to it is a branch checkout.

## Getting started

1. **Install the CLI:**

   ```powershell
   npm install -g git-review-workflow
   ```

   Homebrew, a native Windows (PowerShell) installer and a no-Node one-liner are
   all in the [installation guide](../README.md#installation).

2. **Tell it where PRs are integrated,** once per repository — from the panel
   (**Set the base branch**) or on the command line:

   ```powershell
   git config reviewworkflow.base develop
   ```

3. **Open the `git review` tool window** (View → Other Windows, or Tools → git
   review) and hit **Start a review**. It asks for the branch, where to read it
   from, the range, and how to read it — offering only the layouts the CLI
   reports as viable for that PR.

## Commands

**Tools → git review** holds the full action set: the review lifecycle (Start,
Continue, Finish, Save, Cancel, Undo/Resume Finish), reading it (Next/Previous
Entry, Go to Entry, Open Entry, Open Changes, Show Why) and everything around it
(Set the Base Branch, Set the Remote, Clean, Forget, Discard, Preview Edits and
*(stat)*, Compare Revisions, Walkthrough Init/Build, How to Install the CLI, Show
CLI Log). Four of them — Go to Entry, Forget, Preview Edits (stat), Show CLI
Log — are menu-only; the rest also appear on the panel where they apply.

A menu entry and the panel button of the same name run the same code, so they ask
the same questions. Anything that needs a decision asks for it in a picker: which
branch, which origin, which reading order, where the finish should land, which
saved review to continue. Cancelling a picker cancels the action — nothing is
chosen on your behalf.

Each action shells out to the matching `git review` verb — the extension never
invents a second way to change review state. Mutations ask for a confirmation
that names what will happen; preview is read-only and does not.

## What the panel offers, situation by situation

| Situation | Controls |
|-----------|----------|
| cli-missing | install title, npm command + **Copy**, **Other install options** |
| no-review setup | **Set the base branch** (primary) |
| no-review ready | inventory, **Start a review**, Walkthrough (the row for the walkthrough you wrote — named after the branch, with Init or Update, Build and Copy for agent — and the two authoring guides) / Compare / Settings / Support |
| finish-pending | **Clean** / **Undo finish** |
| review walk | **File** / **Diff**, prev/next, **open in editor**, folded Walkthrough (the two authoring guides) |
| review whole | file rows, one **Diff** each |
| finish-conflict | **Undo** / **Continue** (no nav) |

The tool window toolbar carries **Refresh**, **Finish**, **Save**, **Cancel** and
**Preview edits**; each appears only in the situations it applies to.

## Requirements

- **Windows** (Visual Studio is Windows-only)
- Visual Studio **2022** (17.x) or later
- `git` on `PATH`
- **[git-review-workflow](https://github.com/EzeVillo/git-review-workflow) 0.7.0
  or newer**
- A **single-folder repository.** Multi-root solutions are not supported: the
  panel needs exactly one git repository root, the same way the CLI has one cwd

## Settings

**Tools → Options → git review**:

| Setting | Default | What it does |
|---------|---------|--------------|
| **Path to git-review** | *(empty)* | Path to the `git-review` dispatcher, for when `git` does not discover it. Empty means the extension invokes `git review`. |
| **Default source** | `remote` | Which origin the start wizard preselects: `remote` (fetch and review the remote tip), `local` (no fetch), `offline` (no network at all). |

## Troubleshooting

The panel reports what it found rather than failing silently — a missing CLI, a
version too old, a repository with no base configured — and offers the action
that fixes it. When you need the detail, **Tools → git review → Show CLI Log**
prints every invocation the extension made and what came back.

Reading review state is several `git` processes, and process creation is far more
expensive on Windows than elsewhere — around a second for a full refresh on a
large repository. The panel draws a skeleton while it waits rather than blocking,
so a slow refresh looks like a refresh, not a hang.

## Privacy

No telemetry. No network calls except the ones you trigger through the CLI
(`start` may fetch; `forget --delta --stale` may fetch). Support links open
GitHub in your browser.

## Learn more

- [Project README](../README.md) — the full command surface, the walkthrough
  format, and how the workflow fits together. Also in
  [Spanish](../README.es.md).
- [Website](https://ezevillo.github.io/git-review-workflow/)
- [Report a bug](https://github.com/EzeVillo/git-review-workflow/issues/new?template=bug_report.yml)
- [Contributing to the extension](CONTRIBUTING.md) — building it, running it in
  Visual Studio, the tests and the VSIX.

## License

[MIT](./LICENSE) © EzeVillo
