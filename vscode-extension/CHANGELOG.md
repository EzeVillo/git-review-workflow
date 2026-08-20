# Changelog

Notable changes to the **git review** VS Code extension. The CLI it drives has its
own [releases](https://github.com/EzeVillo/git-review-workflow/releases).

This project follows [semantic versioning](https://semver.org/spec/v2.0.0.html)
and the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

## [Unreleased]

### Changed

- **The draft progress follows the file.** Hand a draft to an agent and the row's count
  moves on its own while it writes -- no Refresh, no reopening the panel. The draft lives
  in the gitdir, so filling it in moves no `HEAD`, touches no index and writes no
  `config`: none of the panel's existing refresh signals could see it. The panel now
  watches the directories the CLI reported the drafts in, and nothing else.

## [0.2.0]

Requires `git review` **0.7.0** or newer.

### Added

- **Reading orders you started, in the panel.** A walkthrough draft you began and have not
  finished now has a place: with no review on this branch, the panel lists every one of them with
  how far along it is (`3/9`, counted by the CLI) and four buttons on its row — *Open* (the file,
  at the path the CLI reported), *Copy for agent* (a one-line instruction naming that file, on the
  clipboard), *Validate and start* (validates it and, when it passes, starts the review on your
  order) and *Discard*. It survives closing the editor, so an order you started on Friday is the
  first thing the panel says on Monday. The rest of the empty state — your other reviews, *Start a
  review*, the settings — stays right below it.
- Copying is copying: no service is contacted, no assistant is invoked, and nothing about the
  draft is written for you.

### Changed

- **The start assistant no longer waits.** Choosing to build a reading order writes the skeleton
  and closes the assistant: no notice left open, nothing to keep alive while you type. Everything
  the notice used to do — validating, asking whether to read the whole order or only the entries
  you marked `> key`, starting the review — is now on the draft's row in the panel, over a state
  that outlives the editor window.
- The two offers say what you get instead of naming an internal term: *Build a reading order
  first* ("nobody wrote one for this PR; otherwise you read the whole diff") and *Finish the
  reading order you started*.
- *Validate and start* invokes the CLI with the **same origin and range flags the draft was
  generated with**, reported by the CLI itself. A draft made with `--delta`, `--local` or
  `--offline` covers a different set of paths than the defaults, so with the defaults that button
  would have failed with a drift error every time, on a perfectly valid draft.

### Fixed

- The extension no longer builds the draft's path out of a gitdir it resolved itself — the CLI
  reports it, and the panel opens what it was given. The old derivation missed the case where the
  folder you opened is below the repository root.

## [0.1.3] — 2026-08-11

Requires `git review` **0.6.0** or newer.

### Added

- **Draft your own reading order.** When a PR ships without a walkthrough, the start assistant now
  offers *Walkthrough — draft one*. It writes a skeleton listing every file in the range, opens it,
  and waits behind a non-blocking notice while you fill in the order and the *why* — *Continue*
  validates it on the CLI and reports exactly what to fix, as many times as you need; *Cancel*
  keeps what you wrote and the next pass offers *Walkthrough — continue draft*. Dismissing the
  notice is not *Cancel*: it comes back, so closing it while you edit does not drop you out of the
  flow. If the editor cannot show the file — a folder opened below the repository root — the notice
  tells you where it is rather than asking you to fill in something you cannot find. The draft is
  yours and local: it lives outside the working tree, so nothing gets committed or staged and
  `git status` never changes. Nothing is written for you and no service is contacted. Reviews
  reading a draft show `(draft)`
  next to the mode.

### Changed

- Minimum required CLI raised from 0.5.0 to **0.6.0**, the release that adds
  `git review walkthrough draft`.

## [0.1.2] — 2026-08-08

Requires `git review` **0.5.0** or newer.

### Added

- **Step mode file list.** While reviewing commit by commit, the panel lists every file the current
  commit touches (from `status --porcelain` `file`
  records), the same selectable inventory whole mode already had for the full range. The commit
  **Diff** control still opens every change at once; each row opens that file's diff against the
  parent. The last file you opened stays marked for the review branch. Requires a CLI that emits
  `file` lines (current
  `git review` on this branch).

### Changed

- Minimum required CLI raised from 0.4.0 to **0.5.0**.

## [0.1.1] — 2026-08-08

Two fixes to actions that could silently do nothing. Still requires
`git review` 0.4.0 or newer.

### Fixed

- **Open changes did nothing for the first seconds of a review.** The action asked the built-in git
  extension for that file's diff, and that extension rescans the repository asynchronously: right
  after a start moves `HEAD` and stages the whole PR at once, its view still describes the previous
  state, so the request resolved against nothing — no error, no editor, nothing to retry. Measured
  on Linux the rescan ran up to ~2.6 s late, and it affected every kind of change, not only added
  files. The diff is now read from git directly — the same read that already backs *Open all
  changes*, which is always current. A file the range modifies opens against the working tree and
  stays editable; one the PR only adds or only deletes opens the single side that exists, read-only.
- **A slow CLI invocation now actually gets cut off.** The timeout never enforced anything: the
  child was signalled but the call kept waiting on pipes its grandchildren held open, so it returned
  only when the command finished on its own (measured on Windows: 8.1 s under a 2 s timeout).
  Invocations now stop at their ceiling, and a cut one is reported as a timeout — in the panel and
  as its own line in **Show CLI Log** — instead of the empty error it used to look like, which said
  the CLI was broken when it was merely slow.

## [0.1.0] — 2026-08-07

First release. Requires `git review` 0.4.0 or newer.

### Added

- **Walkthrough panel.** In walk mode it shows the current entry — the file, its position in the
  author's reading order, its `key` mark and the *why* written for it — with next / previous
  navigation and a quick pick over the whole sequence, including the files the walkthrough does not
  cover.
- **Whole mode.** A review without a walkthrough lists the files the range touches; a row opens that
  file's diff, one control opens every change at once, and the last row you opened stays marked per
  review branch.
- **Step mode.** A commit-by-commit review shows the commit, its subject and author, and which steps
  have banked edits.
- **Inventory.** With no review on the current branch, the panel lists the reviews open elsewhere in
  the repository — active and saved — and offers *Continue* on the saved ones.
- **Lifecycle actions**, each shelling out to the matching verb: start (a wizard offering only the
  layouts the CLI reports as viable), finish, save, cancel, preview, undo finish, resume a finish
  stopped mid-conflict, clean and forget.
- **Author flow**: `walkthrough init` and `build` from the empty state or the Command Palette.
- **Read-only compare** between two revisions, with the panel hiding Finish.
- Settings `gitReview.path` and `gitReview.defaultSource`.
- **git review: Show CLI Log**, listing every invocation the extension made.
