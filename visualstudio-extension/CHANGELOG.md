# Changelog

## [Unreleased]

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
- **Tools → git review**: all 27 actions, named as in the VS Code palette and the
  JetBrains menu. Seven of them had no way in at all — Compare Revisions, Walkthrough
  Init/Build, Set the Base Branch, Set the Remote, Forget, Go to Entry — and answered with
  a note pointing at a menu that did not exist. *Set the Base Branch* was the one that
  mattered most: without a base, no review can start, and the panel's own button was that
  same dead end.
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
- **A disabled button now reads as one.** WPF paints its own disabled and hover colors
  from inside the stock button template, over anything the panel assigns, so a *Continue*
  that cannot be resumed came out as a white block with an unreadable label in a dark
  theme — and a hovered file row flashed Windows blue instead of the IDE's own highlight.
  The panel draws its buttons itself now, in the host's colors, in every state.

- The extension now loads into Visual Studio. The package is a real `AsyncPackage`:
  **View → Other Windows → git review** opens the tool window, and **Tools → Options →
  git review** holds the path to the git-review CLI.
- Opening a file, opening a diff against the review's base, showing the why and running
  the start wizard now go through Visual Studio itself; the panel follows the IDE theme.
- **Refresh**, **Finish**, **Save**, **Cancel** and **Preview edits** are now icon
  buttons on the tool window's own toolbar — where VS Code and the JetBrains
  plugin put them — instead of a row of text buttons inside the panel. Which of
  them is showing still comes from the same layout the panel body does.
- **Preview edits** does something: `git review preview` opens as a read-only
  document, the same as in the other two clients. It used to answer with a note
  pointing at a menu Visual Studio does not have.
- `build-vsix.ps1` builds the `.vsix` and can install it, including into the
  Experimental Instance.
- Fixed: every CLI action ended in a "The calling thread cannot access this object"
  dialog. The action had already run; the panel was being redrawn from the thread the
  mutation finished on instead of the UI thread.

## [0.1.0] — 2026-08-12

- Initial Visual Studio client: portable domain (C# port of JetBrains `domain/`),
  CLI host, WPF panel driven by the same `PanelLayout` / `client-product-surface.yaml`
  as VS Code and IntelliJ.
- Marketplace packaging assets: product icon (shared mark), LICENSE, overview,
  publish checklist, vsixmanifest Icon / PreviewImage / tags.
