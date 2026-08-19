# Changelog

Notable changes to the **git review** JetBrains IDE plugin (IntelliJ Platform).
The CLI it drives has its own
[releases](https://github.com/EzeVillo/git-review-workflow/releases).

This project follows [semantic versioning](https://semver.org/spec/v2.0.0.html)
and the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

## [0.2.0]

Requires `git review` **0.7.0** or newer.

### Added

- **Reading orders you started, in the panel.** A walkthrough draft you began and have not
  finished now has a place: with no review on this branch, the panel lists every one of
  them with how far along it is (`3/9`, counted by the CLI) and four buttons on its row —
  *Open* (the file, at the path the CLI reported), *Copy for agent* (a one-line
  instruction naming that file, on the clipboard), *Validate and start* (validates it and,
  when it passes, starts the review on your order) and *Discard*. It survives closing the
  IDE, so an order you started on Friday is the first thing the panel says on Monday. The
  rest of the empty state — your other reviews, *Start a review*, the settings — stays
  right below it.
- Copying is copying: no service is contacted, no assistant is invoked, and nothing about
  the draft is written for you.

### Changed

- **The start wizard no longer waits.** Choosing to build a reading order writes the
  skeleton and closes the wizard: no dialog left open, nothing to keep alive while you
  type. Everything that dialog used to do — validating, asking whether to read the whole
  order or only the entries you marked `> key`, starting the review — is now on the
  draft's row in the panel, over a state that outlives the IDE window.
- The two offers say what you get instead of naming an internal term: *Build a reading
  order first* ("nobody wrote one for this PR; otherwise you read the whole diff") and
  *Finish the reading order you started*.
- *Validate and start* invokes the CLI with the **same origin and range flags the draft
  was generated with**, reported by the CLI itself. A draft made with `--delta`, `--local`
  or `--offline` covers a different set of paths than the defaults, so with the defaults
  that button would have failed with a drift error every time, on a perfectly valid draft.

### Fixed

- The plugin no longer builds the draft's path out of a gitdir it resolved itself — the
  CLI reports it, and the panel opens what it was given. The old derivation missed the
  case where the project you opened is below the repository root.

## [0.1.3]

### Added

- **Release notes on the listing.** This file is now what the Marketplace *What's
  New* tab and the IDE's update dialog show: the section for the version being
  published is rendered into the plugin descriptor at build time, the same
  section the GitHub Release body already used. Up to and including 0.1.2 the
  descriptor carried no change notes at all, so every version published looked
  like it changed nothing.

### Changed

- **The Marketplace listing says what the plugin does.** It used to open by
  claiming parity with the other editors' clients and then spend its second
  paragraph listing the JetBrains IDEs it runs on — one fact about how the
  project is built, and one the Marketplace already prints above the
  description. Neither told you what you get. It now describes the thing: the PR
  is staged into your working tree as uncommitted changes, you review it by
  going to definitions and running the tests, and your fixes come out on a
  branch of their own. The required CLI is stated up front instead of being
  discovered after installing.
- **Multi-IDE product matrix.** The same zip targets every JetBrains IDE that
  ships `com.intellij.modules.platform` and Git (`Git4Idea`) — IntelliJ IDEA,
  WebStorm, PhpStorm, PyCharm, GoLand, CLion, RubyMine, RustRover, DataGrip, and
  peers. Android Studio and Rider are excluded with
  `<incompatible-with>` in `plugin.xml` (not a Marketplace checkbox hack).
  `verifyPlugin` checks binary compatibility on the products that publish a
  verifier build for the pinned line (DataGrip is Marketplace-eligible via the
  same depends but is not in that binary index); `PluginCompatibilityTest`
  locks the descriptor contract.

### Fixed

- **The pickers no longer cut their own options.** Every choice dialog (branch,
  origin, range, how to read it, keys only) sized itself to the combo, which
  asks for less than its items are wide: the longer labels showed up truncated
  with an ellipsis. They now open wide enough for their longest option (capped,
  with the full text on hover), stay resizable, and remember the size you give
  them.

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

First release. Requires an IntelliJ Platform IDE **2026.1+** (build `261+`;
later IDE releases included via open `until-build`) and a local `git review`
**0.6.0** or newer.

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
