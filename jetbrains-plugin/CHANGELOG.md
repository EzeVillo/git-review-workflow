# Changelog

Notable changes to the **git review** JetBrains IDE plugin (IntelliJ Platform).
The CLI it drives has its own
[releases](https://github.com/EzeVillo/git-review-workflow/releases).

This project follows [semantic versioning](https://semver.org/spec/v2.0.0.html)
and the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

## [0.3.0] — 2026-08-30

Requires `git review` **0.8.0** or newer.

### Fixed

- **The sections at the foot of the panel open and close where they are.** Opening *Walkthrough*,
  *Edits you extracted*, *Compare*, *Settings* or *Support* grew the section inside a band that
  never made room for it: the sections below it fell off the bottom edge, reachable only through a
  hairline scrollbar, and closing it again left the same band with its contents shuffled around
  inside. Neither settled until the tool window was resized by hand. The footer now takes the height
  the section asked for and gives it back when it closes, still capped at 55% of the panel, and
  scrolls as a single list when what is open no longer fits.

### Changed

- **The panel comes to the front when a block is born that was not there before.** Starting a
  review, starting one from a reading order you had begun, continuing a saved one and finishing one
  all draw something that was not on screen a moment ago — and the wizard that starts them runs
  over the editor, so the panel could be closed or on another tab while the acknowledgement was
  drawn where nobody could see it. Those four now bring the panel forward, and without taking focus:
  your caret stays where it was. Every other mutation keeps refreshing in place, because a panel
  that jumps every time stops meaning that something happened.

- **Notes naming a command this panel already draws as a button no longer arrive.** Several CLI
  notes end by spelling the verb that does the next thing. In a terminal that name is the answer; in
  a panel it is a paragraph about a button already on screen. The panel now turns them off at the
  source, the same way git's own `advice.*` settings work — `git config reviewworkflow.advice false`
  does it for your terminal too. Notes about state still arrive in full: an entry the PR no longer
  changes, a cursor that moved, a branch that differs from your local one.

- **No more notifications repeating what the panel already shows.** Creating a reading order leaves its
  row, *Build* leaves the badge up to date, and a finish that stayed pending leaves its banner:
  none of them says it again in a notification. What the panel cannot answer still gets one —
  copying to the clipboard, the residue of a finish that left no banner, and updating a reading
  order, which now reports what the update actually did (`4 kept, 2 added, 1 no longer in the PR`).

## [0.2.0]

Requires `git review` **0.7.0** or newer.

### Added

- **The branches your finishes left behind, finally named somewhere.** Every `finish` leaves a
  `review-fixes/<branch>` with your extracted edits on it, one per review you have ever closed —
  and until now no surface listed them: `git review list` did not enumerate them, the panel's
  inventory comes from `list`, and the only *Clean* in the panel lives in the post-finish banner.
  They piled up, and throwing one away meant spelling its name in a terminal. The empty state now
  ends with **Edits you extracted**, collapsed at the foot: one row per branch, each with what git
  can say about dropping it — `nothing committed` (it still sits where `finish` created it, so it
  holds none of your work), `in the base`, `not in the base`, or `state unknown` when no base is
  configured — and a discard that runs `git review clean --fixes-only`, leaving the review session
  standing, undo point included. The branch you are standing on is drawn like the rest and its
  control is off, because the CLI skips it. There is deliberately **no button that takes them all
  at once**: a bare `clean` also deletes every `review/*` branch — live sessions of other branches —
  and what these rows hold is work you wrote by hand. The value is in the rows, which turn a blind
  `branch -D` into an informed one.


- **The walkthrough you wrote, and whether it still matches the PR.** A walkthrough is written
  once, when the PR is finished — and then the PR keeps moving: review comments come back, three
  more files change, and nothing anywhere said the reading order had fallen behind. The panel's
  *Walkthrough* section now leads with a row for it, named after the branch it annotates:
  `up to date`, `may be out of date`, `state unknown` or `none`, plus how much of it is written
  (`4/6`), an icon that opens it at the path the CLI reported, and three buttons — *Init* (or
  *Update*, or *Start over*), *Build*, and *Copy for agent*, a one-line instruction naming that
  file, on the clipboard, the same shape the draft rows already had. The two verbs hang off the
  row because their subject is the file it names, the way *Create* hangs off each guide. The badge is deliberately cautious: what
  the CLI checks on every refresh is the cheap half of the question, and the exact answer is
  *Build*'s.
- **The button that creates it also updates it, and says so.** *Init* reads *Update* once a
  walkthrough exists, because that is now what the verb does:
  entries whose file is still in range keep their number, their why and their `> key`, files that
  entered the range arrive as placeholders to fill in, and entries whose file left it are dropped
  and named. Fill in only the new ones, hand them to an agent, or write them yourself.
- **A walkthrough that arrived with a merge gets a new one, not a reconciled one.** Your PR
  merges, the sidecar travels into the base with it, you branch again and touch one of the same
  files — and that entry still carries a why about a change that already shipped. The CLI spots it
  (the tip that wrote the walkthrough is already in the base) and starts a fresh one; the row says
  `from a merged PR` rather than `may be out of date`, and the button reads *Start over*, because
  that is what will happen. The old one is in git either way.
- **Choosing between updating and starting over happens before the verb runs.** With a walkthrough
  already there, *Update* asks which of the two you meant: keep every entry whose file
  is still in range, or replace the file with a blank skeleton (`--force`). It used to be offered
  only when the CLI refused, so once `init` stopped refusing there was no way to reach `--force`
  from the panel at all.
- **Reading orders you started, in the panel.** A walkthrough draft you began and have not
  finished now has a place: with no review on this branch, the panel lists every one of
  them with how far along it is (`3/9`, counted by the CLI) and four controls on its row —
  *Copy for agent* (a one-line instruction naming that file, on the clipboard), *Validate
  and start* (validates it and, when it passes, starts the review on your order), plus two
  glyphs beside the count that open the file at the path the CLI reported and discard it.
  It survives closing the IDE, so an order you started on Friday is the first thing the
  panel says on Monday. The
  rest of the empty state — your other reviews, *Start a review*, the settings — stays
  right below it.
- **A reading order whose review is over stops looking like pending work.** A draft
  outlives the review it was written for — that is the promise, and `clean` still never
  touches prose you wrote by hand — but it kept sitting in *Reading orders you started*
  offering *Copy for agent* over a file that is already complete and *Validate and start*
  over a range that already closed. Once the CLI reports that your last completed review of
  that branch covered the very tip the draft was written against, the row moves to
  **Reading orders you finished with**, collapsed at the bottom, keeping the two glyphs
  that still mean something: open it, or throw it away. Nothing is deleted for you, and
  `git review forget --draft --reviewed` sweeps them all at once.
- **Starting a review on a branch whose reading order you already wrote offers the move
  that actually applies.** The wizard used to say *Finish the reading order you started*
  over every draft, including finished ones, which is not what it says. Now the CLI
  decides — it is the side that knows both what the order was written against and where the
  branch is today — and the row follows: **Update the reading order you wrote** when the PR
  moved on, which keeps every entry whose file is still in range (its number, its why, its
  `> key`), brings the new files in as placeholders and drops the ones that left, naming
  them; *Finish the reading order you started* while it is still half-written; and no draft
  row at all when the order is complete and the PR has not moved, because *Walkthrough*
  already reads it and there is nothing to reconcile. Nothing is asked along the way.
  Starting from a blank skeleton stays where it belongs — the **Discard** glyph on the
  draft row, which confirms first: unlike the author's walkthrough, your reading order is
  not in git, so there is no way back.
- **Choosing a draft path now says what it did.** The wizard runs the verb and reports its
  outcome — `2 kept, 1 added, 0 dropped` — instead of staying silent. The result had always been
  there, on the CLI's stdout, and this path read only stderr: on a branch with nothing to note you
  saw nothing at all, and on one with a note you saw the authoring-guide hint, which had nothing to
  do with what you had just pressed.
- Copying is copying: no service is contacted, no assistant is invoked, and nothing about
  the draft is written for you.

### Changed

- **Branch pickers have a search box.** Every picker in the plugin — the start wizard's
  branch step, the base and remote settings, *Clean*, *Forget*, *Discard*, *Continue* —
  was a drop-down you could only walk with the mouse or the arrow keys. It is now a filter
  box over a list: type to narrow it, arrow down to walk what is left. A repository with
  two hundred branches is reachable without scrolling to it.
- **Those pickers only take a branch that exists.** The "Enter a branch name…" way out into
  a free-text box is gone from *Clean*, *Forget* and *Discard*. These verbs delete branches
  and config, and a name typed there does not fail when it is wrong, it points somewhere
  else. For delta markers that outlived every review branch that would have named them,
  *Forget stale delta markers* is exactly those, and needs no name at all.
- **`compare` picks its bounds from the branches you have.** Both bounds opened an empty
  text box that never showed a candidate. They now open the same filtered list. A tag or a
  SHA is still a valid answer — `compare` takes a commit-ish — so what you type is offered
  as the first row when it matches no branch.
- **The draft progress follows the file.** Hand a draft to an agent and the row's count
  moves on its own while it writes — no Refresh, no reopening the panel. The draft lives
  in the gitdir, so filling it in moves no `HEAD`, touches no index and writes no
  `config`: none of the panel's existing refresh signals could see it. The panel now
  watches the directories the CLI reported the drafts in, and nothing else.
- **One emphatic button per draft row, and the progress picks which.** While entries
  are missing the row leads with *Copy for agent*; with the order complete, with
  *Validate and start*. The four controls are always there and in the same order, so
  the row no longer changes shape with its state and every row of the block lines up
  with the one beside it: the two that move the flow along sit in two even columns
  underneath, and the two that act on the file itself — open it, discard it — ride the
  progress count as glyphs. *Validate and start* is switched off, with a tooltip saying
  which of the two reasons applies: the reading order is still unfinished, or the CLI
  cannot tell how the draft was generated. It is never missing.
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
- **The footer section that holds *Compare revisions* now says what it does, and sits
  below the reading orders.** It was called *Other actions* and came first: a title that
  named nothing, above the two sections that do — *Walkthrough*, and the reading orders
  you finished with. It is now *Compare*, and it goes under them, because it is the only
  one of the three that mounts something outside the review you are about to start: any
  two revisions, no review to begin and no reading order to write.

### Fixed

- **A section at the foot of the panel could not be scrolled.** Open one whose body does not
  fit — the branches your finishes left behind, a long walkthrough block — and the footer took the
  whole tool window: the inventory and *Start a review* above it were pushed out of sight, and the
  footer's own tail was then clipped by the window edge with no scrollbar to reach it. The footer
  now never takes more than its share of the panel and scrolls inside it.

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
