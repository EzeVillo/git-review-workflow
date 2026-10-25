# git review workflow — JetBrains IDE plugin

> Review a pull request with a **guided reading order and context**: where to
> start, why each file changed, and what needs attention. Follow a walkthrough
> from the author or a coding agent, or prepare your own for a PR that has none.
> The tool window keeps your place while you inspect the change and leave observations.
>
> The whole PR stays available as staged, editable changes in your IDE. Run
> tests or make corrections when useful; finishing extracts any corrections onto
> a separate branch. You can also complete a guided review without editing code.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](../LICENSE)
[![Requires git review 0.8.0+](https://img.shields.io/badge/requires-git%20review%200.7.0%2B-blue.svg)](https://github.com/EzeVillo/git-review-workflow#installation)

[Project README](../README.md) · [Website](https://ezevillo.com/git-review-workflow/) · [Changelog](./CHANGELOG.md)

**[Watch the 40-second JetBrains demo](https://ezevillo.com/git-review-workflow/#demo-jetbrains)** (in English, with music) — follow the reading order, fix the boundary, run the tests, and extract your correction onto its own branch. Captured in IntelliJ IDEA.

<details>
<summary>See the workflow in action</summary>

**Follow the author's reading order.**

![The JetBrains tool window moves from the policy to the limiter and shows the author's reason for the change.](https://ezevillo.com/git-review-workflow/media/jetbrains-reading-order.gif)

**Edit the code and run the tests.**

![The reviewer corrects the boundary in IntelliJ IDEA and runs the three tests.](https://ezevillo.com/git-review-workflow/media/jetbrains-edit-and-test.gif)

**Take only your fix to a separate branch.**

![Finishing the review stages the correction on review-fixes/rate-limit.](https://ezevillo.com/git-review-workflow/media/jetbrains-finish-review.gif)

</details>

---

This is the IntelliJ Platform surface of
[git-review-workflow](https://github.com/EzeVillo/git-review-workflow). It guides
you through a reading order while the complete PR stays available in your
working tree. Inspect the explanation against the code, leave observations,
and run tests or make corrections when needed. The plugin drives the CLI
and displays its review state.

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
author's walkthrough and the panel marks the mode `(draft)`. Once its review is
over the draft stays on disk but moves to **Reading orders you finished with**,
collapsed at the bottom, where it keeps the two glyphs and loses the pair that
writes the order and starts the review.

**Your other reviews, when this branch has none.** With no review on the current
branch the panel lists the ones open elsewhere in the repository — active and
saved, with their mode and position. Saved ones offer *Continue*; an active one
is listed without an action, because going back to it is a branch checkout the
IDE's branch widget already does.

**The branches your finishes left behind.** Every `finish` leaves a
`review-fixes/<branch>`, and they pile up one per review. The empty state lists
them under **Edits you extracted**, collapsed at the foot, each with what git can
say about dropping it: `empty` (it still sits where `finish` created it, so it
holds none of your work), `merged`, `unmerged`, or `unknown` with no base
configured. Dropping one leaves the review session
standing, including the undo point of a finish you can still abort. **Discard
all** runs the same `clean --fixes-only` with no branch: by `clean`'s own
scoping that only ever enumerates `review-fixes/*` and never touches a live
`review/*` session, unlike a bare `clean`. It is still behind a confirmation,
because what these rows hold is work you wrote by hand.

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
| `no-review` (ready) | Inventory (Continue / Discard), **Start a review**, collapsible Walkthrough (the row for the walkthrough you wrote — named after the branch, with Init or Update, Build and Copy for agent — and the two authoring guides) / Compare / Settings / Support | Refresh |
| `finish-pending` | Banner: **Clean** \| **Undo finish** | Refresh |
| `review` walk | Identity bar, notes, entry, why, open in editor, File \| Diff, ◀ \| ▶ — no footer sections | Refresh, Finish, Save, Cancel, Preview edits |
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
- [Website](https://ezevillo.com/git-review-workflow/)
- [Issues](https://github.com/EzeVillo/git-review-workflow/issues)
- [Contributing to the plugin](CONTRIBUTING.md) — building it, running it in a
  sandbox IDE, the tests and the release flow.

## License

[MIT](../LICENSE) © EzeVillo

## Review comments

Use **Add comment** to write a multiline observation and choose **Local** or
**Shared** for that submission. The next comment starts without a destination.
Use **Save** (or Ctrl+Enter) to submit; Enter adds a line and Cancel discards the
form. The selected code is never saved by this action. Unsaved code is marked
as unversioned; a viewer that cannot identify its original side supports a
general comment instead.

The scope starts with selected lines, the current file, or General, choosing the
most specific available context. You can switch scope without losing your text.
The panel previews the target as you select code; opening the form fixes that
context, including the original side of a diff. While saving, the form is disabled;
success closes it and errors preserve your input.

Only existing documents appear in the Comments block. **Delete** removes a chosen
preparation, retained Local result or pending Shared preparation after confirmation.

The Comments block has separate Local and Shared documents. **Copy path**
copies the absolute path of an existing Local document, including retained results. **Open** edits the
Markdown, **Renumber** numbers its current entries and **Diff** selects an entry
and opens its captured code. Historical views require the original Git objects;
missing objects or unversioned contents have an explicit diagnostic.

Local stays private in Git's data directory. Shared starts from the branch's
document during a review. Save/Continue keeps its private preparation,
including deletions. After Finish stages it, that editable preparation is removed.
Outside a review, Comments sits between Walkthrough and Compare and reads Shared
from the current branch, taking precedence over saved preparations. Continue
restores the saved preparation. Finish delivers Shared to
`.review/comments.md` when the review finishes. A pending delivery offers
**Prepare**, with a document comparison and an explicit retry. Finishing does
not open the documents automatically. Comparisons retain Local comments
automatically when closed.
The comment form labels the text field explicitly. The Diff browser shows a
compact location and a one-line preview, with `…` when the comment is shortened.
The complete comment scrolls below; original revision IDs are folded under
Details, while warnings about unsaved captures stay visible. Diffs open inside
the IDE, with the comment still accessible. Selected lines are marked on the
recorded version. Local results and pending Shared preparations can be deleted
after Finish; delivered Shared offers reading and historical diffs.
