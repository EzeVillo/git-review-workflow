# Changelog

Notable changes to the **git review** IntelliJ IDEA plugin. The CLI it drives
has its own [releases](https://github.com/EzeVillo/git-review-workflow/releases).

This project follows [semantic versioning](https://semver.org/spec/v2.0.0.html)
and the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

## [0.1.1]

Maintenance release: nothing about what the plugin does changes. It clears every
warning the JetBrains Marketplace plugin verifier raised against 0.1.0.

### Changed

- The single-choice pickers (branch, origin, range, layout) are a plugin dialog
  now that the platform deprecated `Messages.showChooseDialog`. Same shape and
  the same prompts — one combo, cancel still cancels.
- Panel buttons that route to a menu action go through the platform's
  `ActionUtil.performAction` instead of calling `actionPerformed` themselves, so
  they fire the IDE's action listeners like any other invocation does.
- Kotlin no longer emits a delegating override for every default method of the
  platform interfaces the plugin implements. The verifier read those compiler
  artifacts as the plugin using deprecated and experimental API — `isApplicable`,
  `isDoNotActivateOnStart`, `getAnchor`, `getIcon`, `manage` — that it neither
  wrote nor calls.

## [0.1.0]

First release. Requires IntelliJ IDEA **2026.1+** (build `261+`; later IDE
releases included via open `until-build`) and a local `git review` **0.6.0** or
newer.

### Added

- **Native tool window.** A Swing panel that always describes what the CLI
  reports — no state is derived in the IDE — with the review's controls in the
  title bar (Refresh, Finish, Save, Cancel, Preview edits) and the full action
  set under **Tools → git review**.
- **Walkthrough panel.** In walk mode it shows the current entry — the file, its
  position in the author's reading order, its `key` mark and the *why* written
  for it — with next / previous navigation and a **Go to Entry** pick over the
  whole sequence, including the files the walkthrough does not cover.
- **Whole mode.** A review without a walkthrough lists the files the range
  touches; a row opens that file's diff, one control opens every change at once,
  and the last row you opened stays marked per review branch.
- **Step mode.** A commit-by-commit review shows the commit, its subject and
  author, which steps have banked edits, and the files the current commit
  touches.
- **Draft your own reading order.** When a PR ships without a walkthrough, the
  start wizard offers *Walkthrough — draft one*. It writes a skeleton listing
  every file in the range, opens it, and waits behind a notice while you fill in
  the order and the *why* — *Continue* validates it on the CLI and reports
  exactly what to fix, as many times as you need; *Cancel* keeps what you wrote
  and the next pass offers to continue the draft. The draft is yours and local:
  it lives outside the working tree, so nothing gets committed or staged and
  `git status` never changes. Reviews reading a draft show `(draft)` next to the
  mode.
- **Inventory.** With no review on the current branch, the panel lists the
  reviews open elsewhere in the repository — active and saved — and offers
  *Continue* / *Discard* on them.
- **Lifecycle actions**, each shelling out to the matching verb: start (a wizard
  offering only the layouts the CLI reports as viable — walkthrough, keys only,
  commit by commit, whole diff), finish, save, cancel, preview edits, undo
  finish, resume a finish stopped mid-conflict, clean and forget.
- **Author flow**: `walkthrough init` and `build` from the empty state or the
  menu.
- **Read-only compare** between two revisions, with the panel hiding Finish.
- **Diff integration.** Multi-file diffs open as a single window with
  Prev / Next file rather than one editor tab per file; a file the range
  modifies opens against the working tree and stays editable, one the PR only
  adds or only deletes opens the single side that exists.
- **Guidance when the CLI is missing or too old**, with the install command in a
  copyable block and a link to the other install methods.
- **Settings** `path` and `defaultSource` under **Settings → Tools → git
  review**, plus **Show CLI Log** listing every invocation the plugin made.
- Product parity with the VS Code extension — the same actions, situations and
  panel layout — pinned by
  [`contracts/client-product-surface.yaml`](../contracts/client-product-surface.yaml)
  and verified on both clients in CI. The plugin carries the same product mark
  as the extension, out of the shared icon generator.
