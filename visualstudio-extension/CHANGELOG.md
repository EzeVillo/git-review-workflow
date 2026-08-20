# Changelog

Notable changes to the **git review** Visual Studio extension. The CLI it drives
has its own
[releases](https://github.com/EzeVillo/git-review-workflow/releases).

This project follows [semantic versioning](https://semver.org/spec/v2.0.0.html)
and the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

## [0.1.0]

First release of the Visual Studio client. Requires `git review` **0.7.0** or newer.

These notes cover the whole pre-release cycle in one section: nothing below ever
shipped on its own, so the *Changed* and *Fixed* entries record how this release
reached its shape rather than a difference against a version you could install.

### Added

- Visual Studio client for `git review`: portable domain (C# port of the JetBrains
  `domain/`), CLI host, and a WPF panel driven by the same `PanelLayout` /
  `client-product-surface.yaml` as VS Code and IntelliJ.
- The package is a real `AsyncPackage`: **View → Other Windows → git review** opens the
  tool window, and **Tools → Options → git review** holds the path to the git-review CLI.
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
- **Tools → git review**: all 27 actions, named as in the VS Code palette and the
  JetBrains menu.
- **Refresh**, **Finish**, **Save**, **Cancel** and **Preview edits** are icon buttons on
  the tool window's own toolbar — where VS Code and the JetBrains plugin put them —
  instead of a row of text buttons inside the panel. Which of them is showing comes from
  the same layout the panel body does.
- **Preview edits** opens `git review preview` as a read-only document, the same as in the
  other two clients.
- Opening a file, opening a diff against the review's base, showing the why and running
  the start wizard go through Visual Studio itself; the panel follows the IDE theme.
- Marketplace packaging assets: product icon (shared mark), LICENSE, overview, publish
  checklist, vsixmanifest Icon / PreviewImage / tags.
- `build-vsix.ps1` builds the `.vsix` and can install it, including into the Experimental
  Instance.

### Changed

- **The draft progress follows the file.** Hand a draft to an agent and the row's count
  moves on its own while it writes — no Refresh, no reopening the panel. The draft lives
  in the gitdir, so filling it in moves no `HEAD`, touches no index and writes no
  `config`: none of the panel's existing refresh signals could see it. The panel now
  watches the directories the CLI reported the drafts in, and nothing else.
- **One emphatic button per draft row, and the progress picks which.** While entries
  are missing the row leads with *Copy for agent*; with the order complete, with
  *Validate and start*. The four controls are always there and in the same order, in
  two even columns: the row no longer changes shape with its state, so every row of
  the block lines up with the one beside it. *Validate and start* is switched off
  — with a tooltip saying why — instead of disappearing when the CLI cannot tell how
  the draft was generated, *Open* carries a label of its own, and *Discard*, the one
  irreversible control of the row, loses its fill.
- **The start wizard does not wait.** Choosing to build a reading order writes the
  skeleton and closes the wizard: no dialog left open, nothing to keep alive while you
  type. Everything that dialog used to do — validating, asking whether to read the whole
  order or only the entries you marked `> key`, starting the review — is on the
  draft's row in the panel, over a state that outlives the IDE window.
- The two offers say what you get instead of naming an internal term: *Build a reading
  order first* ("nobody wrote one for this PR; otherwise you read the whole diff") and
  *Finish the reading order you started*.
- *Validate and start* invokes the CLI with the **same origin and range flags the draft
  was generated with**, reported by the CLI itself. A draft made with `--delta`, `--local`
  or `--offline` covers a different set of paths than the defaults, so with the defaults
  that button would have failed with a drift error every time, on a perfectly valid draft.
- **Whole mode offers no button that opens every file at once.** VS Code shows a
  whole range in a single multi-diff editor and IntelliJ in one window with Prev/Next
  between files; Visual Studio's differencing service opens one comparison window per pair
  of files and has no equivalent, so the same button sprayed a window per changed file —
  forty files, forty windows — and capping that would still be an avalanche. The file
  inventory below it opens each diff on demand, which is the same range in the only shape
  this host can give it well. *Open All Changes* is absent from **Tools → git review** for
  the same reason, rather than staying as a second way to trigger it.

### Fixed

- The extension no longer builds the draft's path out of a gitdir it resolved itself — the
  CLI reports it, and the panel opens what it was given. The old derivation missed the
  case where the folder you opened is below the repository root.
- **A draft with no entries yet no longer reads as a finished one.** `0/0` was taken as
  complete, so the row led with *Validate and start* — which in that state is usually
  switched off as well, leaving the one emphatic control of the row unclickable. It
  happens on the ordinary path, not just to a draft you emptied by hand: the panel picks
  the file up the moment an agent starts writing it, before the first entry heading
  lands. The row leads with *Copy for agent* until the file actually declares an entry.
- **The draft progress keeps following the file after the watcher hits an error.** This is
  the one client that drives a raw `FileSystemWatcher` — VS Code and the JetBrains
  platform own that recovery for their panels — and it was not listening on the error
  channel. Two measured outcomes both ended the same way: removing the watched directory
  switches the watcher off for good, and an internal buffer overflow keeps it alive but
  silently drops what did not fit (3000 writes arrived as 3 events). Neither healed on its
  own, because the watchers are only rebuilt when the set of reported directories changes
  — which on an ordinary session is never. So the progress froze for the rest of the
  session, while the agent was still writing and with nothing to show for it. The watcher
  is rebuilt now, and the panel refreshed once alongside it, since the events lost inside
  the error are not redelivered. A directory that keeps failing is given up on rather than
  rebuilt forever.
- **In walk mode the panel shows the why again.** It read the entry's prose with an
  800 ms deadline on the CLI call itself, and on Windows a `status --why` costs a couple
  of seconds — so every entry of every walk came back as "Could not read the why for this
  entry", and *open in editor* opened nothing. The 800 ms is a drawing deadline now, the
  same as in VS Code and the JetBrains plugin: the refresh no longer waits on the why, the
  entry appears with it still loading, and the text fills in when the CLI answers. A why
  that belongs to the entry you just left is dropped rather than drawn under the new one.
- **A cursor that fell out of range says so.** When HEAD moves off a review's base —
  committing on top of the staged diff is the usual way — the CLI explains it on stderr
  and prints no porcelain. The panel parsed it anyway and turned that into "Something
  went wrong reading the review state: porcelain output has no state record", hiding the
  one message that says how to get back (`git reset --soft`, or abort). It is the
  out-of-range situation now, with the CLI's own words, like in the other two clients.
- **The panel no longer claims the CLI is missing while it is still looking.** Opening
  the tool window drew the seed state — a full "git-review was not found" pane, Install
  button and all — for the couple of seconds the first `--version` plus
  `status --porcelain` takes. It now holds on *Reading the review state…* until there is
  an answer, the same way the IntelliJ panel waits and the VS Code webview stays empty.
- **Nor that the workspace is not a git repository while it is still opening.** Visual
  Studio restores a docked tool window before the solution or folder can say where it is,
  and the panel read that silence as an answer: every start began with "Something went
  wrong reading the review state — Need a single git repository root." until the roots
  arrived and a refresh replaced it. It now waits on *Reading the review state…* while the
  shell has named no directory at all — across a solution switch too — and a folder the
  shell *has* named and git does not call a repository is still answered immediately, as
  before.
- **Diffs are built from what git reports, not from the entry's name.** The two
  name-status calls now match the ones the other clients make. `git diff-tree` gets
  `--root`, without which a commit with no parent lists nothing and the panel answered
  "changes no files" for the commit that added the entire tree; and a file's Diff resolves
  its two sides through `git diff --name-status HEAD`, so a file the review adds opens
  against an empty base instead of against a blob looked up under its own name, and an
  entry whose edit was reverted says there is nothing left to compare rather than opening
  a window showing a file against itself.
- **A mutation that is running says so.** Finish, start, abort, save, continue, compare,
  undo, the walkthrough verbs and the housekeeping ones report into the status bar while
  they work — the same lines VS Code puts in its progress notification and IntelliJ in
  its background task. Greyed-out panel buttons were the only sign until now, and they
  are no help to whoever started a finish from **Tools → git review** and looked away.
- **A discarded action is reported wherever it came from.** A second mutation while one
  is running is dropped, not queued; only the panel's own path said so, so the same
  click from the toolbar or the menu — a Next during a finish, say — looked like a button
  that did nothing. The notice belongs to the lock now, which every surface goes through.
- **Start a review actually starts the review you asked for.** Every step of the wizard
  (branch, origin, range, reading order) is a real picker now. It used to print the
  options into a message box and then take the first one regardless — so the wizard was a
  row of dialogs that never let you choose, and the review it started was on whichever
  branch happened to sort first.
- The wizard reaches parity with the other two clients: the origin step starts on your
  **Default start source** setting, the range step only appears when there is a delta
  marker to compare against, *Walkthrough — draft one* opens the draft and validates it
  (saving your unsaved buffer first, which is what `--build` reads), a start that fails on
  the network hands you the exact command to re-run in a terminal, and a start whose
  repository moved while the wizard was open refuses instead of starting something else.
- Seven actions had no way in at all — Compare Revisions, Walkthrough Init/Build, Set the
  Base Branch, Set the Remote, Forget, Go to Entry — and answered with a note pointing at
  a menu that did not exist. *Set the Base Branch* was the one that mattered most: without
  a base, no review can start, and the panel's own button was that same dead end.
- Clean, Forget, Discard, Continue and Finish ask their questions properly: a list of what
  there is to pick from, and the affirmative button carries the action's own words
  ("Start the review", "Cancel Review", "Discard All Saved") instead of a generic OK.
- **Step mode opens the right diff.** The commit "Diff" opens the commit against its
  parent, file by file; a file row opens that file at `sha^` vs `sha`. Both used to look
  for a file named after the commit sha and open an empty comparison against nothing.
- Undo Finish offers the `--force` escalation when the CLI names it, Resume Finish resumes
  onto the side the interrupted finish was aimed at (it always assumed the separate
  branch), and a successful finish says where the edits landed.
- Dialogs follow the IDE theme and open centred on the IDE rather than behind it.
- **A disabled button reads as one.** WPF paints its own disabled and hover colors
  from inside the stock button template, over anything the panel assigns, so a *Continue*
  that cannot be resumed came out as a white block with an unreadable label in a dark
  theme — and a hovered file row flashed Windows blue instead of the IDE's own highlight.
  The panel draws its buttons itself now, in the host's colors, in every state.
- Every CLI action used to end in a "The calling thread cannot access this object"
  dialog. The action had already run; the panel was being redrawn from the thread the
  mutation finished on instead of the UI thread.
