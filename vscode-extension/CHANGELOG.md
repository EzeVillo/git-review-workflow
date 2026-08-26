# Changelog

Notable changes to the **git review** VS Code extension. The CLI it drives has its
own [releases](https://github.com/EzeVillo/git-review-workflow/releases).

This project follows [semantic versioning](https://semver.org/spec/v2.0.0.html)
and the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

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
  finished now has a place: with no review on this branch, the panel lists every one of them with
  how far along it is (`3/9`, counted by the CLI) and four controls on its row — *Copy for agent*
  (a one-line instruction naming that file, on the clipboard), *Validate and start* (validates it
  and, when it passes, starts the review on your order), plus two glyphs beside the count that
  open the file at the path the CLI reported and discard it. It survives closing the editor, so an
  order you started on Friday is the first thing the panel says on Monday. The rest of the empty state — your other reviews, *Start a
  review*, the settings — stays right below it.
- **A reading order whose review is over stops looking like pending work.** A draft outlives the
  review it was written for — that is the promise, and `clean` still never touches prose you wrote
  by hand — but it kept sitting in *Reading orders you started* offering *Copy for agent* over a
  file that is already complete and *Validate and start* over a range that already closed. Once
  the CLI reports that your last completed review of that branch covered the very tip the draft
  was written against, the row moves to **Reading orders you finished with**, collapsed at the
  bottom, keeping the two glyphs that still mean something: open it, or throw it away. Nothing is
  deleted for you, and `git review forget --draft --reviewed` sweeps them all at once.
- **Starting a review on a branch whose reading order you already wrote offers the move that
  actually applies.** The wizard used to say *Finish the reading order you started* over every
  draft, including finished ones, which is not what it says. Now the CLI decides — it is the side
  that knows both what the order was written against and where the branch is today — and the row
  follows: **Update the reading order you wrote** when the PR moved on, which keeps every entry
  whose file is still in range (its number, its why, its `> key`), brings the new files in as
  placeholders and drops the ones that left, naming them; *Finish the reading order you started*
  while it is still half-written; and no draft row at all when the order is complete and the PR
  has not moved, because *Walkthrough* already reads it and there is nothing to reconcile.
  Nothing is asked along the way. Starting from a blank skeleton stays where it belongs — the
  **Discard** glyph on the draft row, which confirms first: unlike the author's walkthrough, your
  reading order is not in git, so there is no way back.
- Copying is copying: no service is contacted, no assistant is invoked, and nothing about the
  draft is written for you.

### Changed

- **Every branch picker filters as you type, and only takes a branch that exists.** The
  pickers that name a branch — *Clean*, *Forget*, *Discard* — no longer offer an "Enter a
  branch name…" way out into a free-text box. `clean` and `forget` delete branches and
  config, and a name typed there does not fail when it is wrong, it points somewhere else.
  The list still narrows as you type, so writing is still how you reach a row; it just
  cannot invent one. For delta markers that outlived every review branch that would have
  named them, *Forget stale delta markers* is exactly those, and needs no name at all.
- **`compare` picks its bounds from the branches you have.** Both bounds now open the list
  of candidates instead of an empty box, filtered as you type. A tag or a SHA is still a
  valid answer there — `compare` takes a commit-ish — so what you type is offered as the
  first row when it matches no branch, in the same box rather than behind a separate
  "Enter commit-ish…" dialog that hid the list.
- **The draft progress follows the file.** Hand a draft to an agent and the row's count moves on
  its own while it writes — no Refresh, no reopening the panel. The draft lives in the gitdir, so
  filling it in moves no `HEAD`, touches no index and writes no `config`: none of the panel's
  existing refresh signals could see it. The panel now watches the directories the CLI reported
  the drafts in, and nothing else.
- **One emphatic button per draft row, and the progress picks which.** While entries are missing
  the row leads with *Copy for agent*; with the order complete, with *Validate and start*. The
  four controls are always there and in the same order, so the row no longer changes shape with
  its state and every row of the block lines up with the one beside it: the two that move the flow
  along sit in two even columns underneath, and the two that act on the file itself — open it,
  discard it — ride the progress count as glyphs. *Validate and start* is switched off, with a
  tooltip saying which of the two reasons applies: the reading order is still unfinished, or the
  CLI cannot tell how the draft was generated. It is never missing.
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
- **The footer section that holds *Compare revisions* now says what it does, and sits below
  the reading orders.** It was called *Other actions* and came first: a title that named
  nothing, above the two sections that do — *Walkthrough*, and the reading orders you
  finished with. It is now *Compare*, and it goes under them, because it is the only one of
  the three that mounts something outside the review you are about to start: any two
  revisions, no review to begin and no reading order to write.

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
