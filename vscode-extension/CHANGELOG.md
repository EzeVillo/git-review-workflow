# Changelog

Notable changes to the **git review** VS Code extension. The CLI it drives has
its own [releases](https://github.com/EzeVillo/git-review-workflow/releases).

This project follows [semantic versioning](https://semver.org/spec/v2.0.0.html)
and the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

## [0.1.1] — 2026-08-08

Two fixes to actions that could silently do nothing. Still requires
`git review` 0.4.0 or newer.

### Fixed

- **Open changes did nothing for the first seconds of a review.** The action
  asked the built-in git extension for that file's diff, and that extension
  rescans the repository asynchronously: right after a start moves `HEAD` and
  stages the whole PR at once, its view still describes the previous state, so
  the request resolved against nothing — no error, no editor, nothing to retry.
  Measured on Linux the rescan ran up to ~2.6 s late, and it affected every kind
  of change, not only added files. The diff is now read from git directly — the
  same read that already backs *Open all changes*, which is always current. A
  file the range modifies opens against the working tree and stays editable; one
  the PR only adds or only deletes opens the single side that exists, read-only.
- **A slow CLI invocation now actually gets cut off.** The timeout never
  enforced anything: the child was signalled but the call kept waiting on pipes
  its grandchildren held open, so it returned only when the command finished on
  its own (measured on Windows: 8.1 s under a 2 s timeout). Invocations now stop
  at their ceiling, and a cut one is reported as a timeout — in the panel and as
  its own line in **Show CLI Log** — instead of the empty error it used to look
  like, which said the CLI was broken when it was merely slow.

## [0.1.0] — 2026-08-07

First release. Requires `git review` 0.4.0 or newer.

### Added

- **Walkthrough panel.** In walk mode it shows the current entry — the file, its
  position in the author's reading order, its `key` mark and the *why* written
  for it — with next / previous navigation and a quick pick over the whole
  sequence, including the files the walkthrough does not cover.
- **Whole mode.** A review without a walkthrough lists the files the range
  touches; a row opens that file's diff, one control opens every change at once,
  and the last row you opened stays marked per review branch.
- **Step mode.** A commit-by-commit review shows the commit, its subject and
  author, and which steps have banked edits.
- **Inventory.** With no review on the current branch, the panel lists the
  reviews open elsewhere in the repository — active and saved — and offers
  *Continue* on the saved ones.
- **Lifecycle actions**, each shelling out to the matching verb: start (a wizard
  offering only the layouts the CLI reports as viable), finish, save, cancel,
  preview, undo finish, resume a finish stopped mid-conflict, clean and forget.
- **Author flow**: `walkthrough init` and `build` from the empty state or the
  Command Palette.
- **Read-only compare** between two revisions, with the panel hiding Finish.
- Settings `gitReview.path` and `gitReview.defaultSource`.
- **git review: Show CLI Log**, listing every invocation the extension made.
