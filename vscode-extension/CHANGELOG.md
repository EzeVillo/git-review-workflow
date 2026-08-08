# Changelog

Notable changes to the **git review** VS Code extension. The CLI it drives has
its own [releases](https://github.com/EzeVillo/git-review-workflow/releases).

This project follows [semantic versioning](https://semver.org/spec/v2.0.0.html)
and the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

## [0.1.0] — unreleased

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
