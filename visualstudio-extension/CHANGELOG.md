# Changelog

Notable changes to the **git review** Visual Studio extension. The CLI it drives
has its own
[releases](https://github.com/EzeVillo/git-review-workflow/releases).

This project follows [semantic versioning](https://semver.org/spec/v2.0.0.html)
and the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

## [0.1.0]

First release of the Visual Studio client. Requires `git review` **0.7.0** or newer.

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
- **The tool window.** **View → Other Windows → git review** opens a WPF panel that always
  describes what the CLI reports — no state is derived in the IDE — driven by the same
  layout as the VS Code and JetBrains clients. **Tools → Options → git review** holds the
  path to the git-review CLI.
- **Refresh**, **Finish**, **Save**, **Cancel** and **Preview edits** are icon buttons on
  the tool window's own toolbar, where the other two clients put them. Which of them shows
  comes from the same layout the panel body does. *Preview edits* opens `git review
  preview` as a read-only document.
- **Walk mode.** The current entry — the file, its place in the reading order, its `key`
  mark and the *why* written for it — with next / previous navigation. The entry is drawn
  as soon as it is known and the *why* fills in when the CLI answers, so a slow
  `status --why` never holds the panel up; a *why* that belongs to the entry you just left
  is dropped rather than drawn under the new one.
- **Whole and step modes.** A range without a walkthrough lists the files it touches, each
  row opening that file's diff on demand; a commit-by-commit review shows the commit with
  its own file list, where **Diff** opens the commit against its parent and a row opens
  that file at `sha^` vs `sha`. Both sides of every diff come from what git reports
  (`diff --name-status`, and `diff-tree --root` so the first commit of a repository lists
  its files), so a file the review adds opens against an empty base and one whose edit was
  reverted says there is nothing left to compare.
- **Reading orders you started, in the panel.** A walkthrough draft you began and have not
  finished has a place: with no review on this branch, the panel lists every one of them
  with how far along it is (`3/9`, counted by the CLI) and four controls on its row —
  *Copy for agent* (a one-line instruction naming that file, on the clipboard), *Validate
  and start* (validates it and, when it passes, starts the review on your order), plus two
  glyphs beside the count that open the file at the path the CLI reported and discard it.
  *Validate and start* stays switched off — with a tooltip saying why — while the reading
  order is unfinished or the CLI cannot tell how the draft was generated. It survives
  closing the IDE, so an order you started on Friday is the first thing the panel says on
  Monday. The
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
- *Validate and start* invokes the CLI with the **same origin and range flags the draft was
  generated with**, reported by the CLI itself — a draft made with `--delta`, `--local` or
  `--offline` covers a different set of paths than the defaults would.
- **The pickers.** Every list you choose from has a search box: type to narrow it, arrow
  down to walk what is left, with two options or two hundred. The ones that name a branch
  take only a branch that exists — *Clean*, *Forget* and *Discard* delete branches and
  config, and a name typed by hand does not fail when it is wrong, it points somewhere
  else. `compare` is the exception, because it takes a commit-ish: there the list is still
  offered and filtered, and a tag or a SHA you type is offered as the first row.
- **The start wizard.** Every step — branch, origin, range, reading order — is a real
  picker. The origin step starts on your **Default start source** setting, the range step
  only appears when there is a delta marker to compare against, and *Walkthrough — draft
  one* writes the skeleton, opens it and closes the wizard: everything left to do lives on
  the draft's row in the panel, over a state that outlives the IDE window. A start that
  fails on the network hands you the exact command to re-run in a terminal, and a start
  whose repository moved while the wizard was open refuses rather than starting something
  else.
- **Tools → git review**: all 27 actions, named as in the VS Code palette and the JetBrains
  menu — including Compare Revisions, Walkthrough Init/Build, Set the Base Branch, Set the
  Remote, Forget and Go to Entry.
- Clean, Forget, Discard, Continue and Finish ask their questions with a list of what there
  is to pick from, and the affirmative button carries the action's own words ("Start the
  review", "Cancel Review", "Discard All Saved") instead of a generic OK.
- Undo Finish offers the `--force` escalation when the CLI names it, Resume Finish resumes
  onto the side the interrupted finish was aimed at, and a successful finish says where the
  edits landed.
- **A mutation that is running says so.** Finish, start, abort, save, continue, compare,
  undo, the walkthrough verbs and the housekeeping ones report into the status bar while
  they work — the same lines VS Code puts in its progress notification and IntelliJ in its
  background task — which is what whoever started a finish from **Tools → git review** and
  looked away has to go on. A second mutation while one is running is dropped rather than
  queued, and the notice belongs to the lock, so it is reported wherever the click came
  from.
- **A cursor that fell out of range says so, in the CLI's own words.** When HEAD moves off
  a review's base — committing on top of the staged diff is the usual way — the panel shows
  the one message that says how to get back (`git reset --soft`, or abort) instead of a
  parse failure.
- The panel holds on *Reading the review state…* while the answer is still on its way:
  neither "git-review was not found" during the first `--version`, nor "not a git
  repository" while Visual Studio is still restoring a docked tool window ahead of the
  solution that would say where it is. A folder the shell *has* named and git does not call
  a repository is still answered immediately.
- The panel draws its own buttons in the host's colors, in every state, and dialogs follow
  the IDE theme and open centred on the IDE. WPF paints disabled and hover from inside the
  stock template, over anything assigned to the button, which in a dark theme makes a
  disabled control a white block with an unreadable label.
- Marketplace packaging assets: product icon (shared mark), LICENSE, overview, publish
  checklist, vsixmanifest Icon / PreviewImage / tags.
- `build-vsix.ps1` builds the `.vsix` and can install it, including into the Experimental
  Instance.

### Notes

- **Whole mode has no button that opens every file at once.** VS Code shows a whole range in
  a single multi-diff editor and IntelliJ in one window with Prev/Next between files;
  Visual Studio's differencing service opens one comparison window per pair of files and
  has no equivalent, so the same button would spray a window per changed file — forty
  files, forty windows — and capping that is still an avalanche. The file inventory opens
  each diff on demand, which is the same range in the only shape this host can give it
  well. *Open All Changes* is absent from **Tools → git review** for the same reason,
  rather than staying as a second way to trigger it.
