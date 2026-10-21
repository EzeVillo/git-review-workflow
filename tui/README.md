# git review workflow — terminal UI

> Review a pull request by **editing and running** it, not just reading it. The
> terminal UI keeps the review state, reading order and actions in one pane while
> the whole PR stays available as staged, editable changes in your working tree.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](../LICENSE)
[![Requires git review 0.9.0+](https://img.shields.io/badge/requires-git%20review%200.9.0%2B-blue.svg)](../README.md#installation)

[Project README](../README.md) · [CLI reference](../CLI.md) · [Changelog](CHANGELOG.md)

This is the terminal interface for
[git-review-workflow](https://github.com/EzeVillo/git-review-workflow). It drives
the same CLI as the editor extensions and reads its porcelain records instead of
deriving repository state on its own. Start, follow a reading order, inspect the
change, edit and run it with your usual tools, then finish or save the review
without leaving the terminal pane.

> **The CLI is required.** The terminal UI is a separately released static
> binary, not a replacement for `git review`.

## Getting started

The terminal UI needs the `git review` CLI. Choose **one** installation below:
each one-line installer installs both the CLI and the terminal UI.

### Windows (PowerShell)

Open PowerShell and run:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-install.ps1))) -WithUi
```

Open a new terminal when it finishes.

### macOS, Linux, WSL, or Git Bash

Run:

```sh
curl -fsSL https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-install.sh | GIT_REVIEW_WITH_UI=1 sh
```

### Homebrew (macOS or Linux)

If you already installed the CLI with Homebrew, install only the terminal UI:

```sh
brew tap EzeVillo/git-review-workflow https://github.com/EzeVillo/git-review-workflow
brew install EzeVillo/git-review-workflow/git-review-ui
```

### Download a binary

Static binaries for macOS, Linux and Windows are attached to every
[`tui-v*` release](https://github.com/EzeVillo/git-review-workflow/releases).
This option requires the CLI to be installed separately; see the project
[installation guide](../README.md#installation).

### Start the interface

Open a repository and run:

```sh
cd path/to/repository
git review ui
```

`git review-ui` is an equivalent shortcut. If the repository has no base branch
configured yet, the interface asks you to choose one before starting a review.

## Using the interface

The key bar always shows the controls available in the current situation. These
bindings stay consistent throughout the interface:

| Keys | What they do |
|------|--------------|
| `j` / `↓`, `k` / `↑` | Move focus between rows |
| `enter` | Activate the focused control |
| `n`, `p` | Move to the next or previous entry in the review's reading order |
| `f`, `s`, `a` | Finish, save or abort the active review when available |
| `r` | Refresh the review state |
| `:` | Open the complete action list |
| `g` | Pick an entry from the reading order |
| `m` | Toggle mouse reporting so the terminal can select text again |
| `q` / `ctrl+c` | Quit |

Mouse controls are available too. Files and diffs open through your Git/editor
configuration; the UI never hides or replaces the staged working-tree change.
Long reviews scroll to keep the focused control visible. The mouse wheel also
scrolls the review content; the key bar stays visible while you reach Comments.

## Refresh and terminal compatibility

Filesystem events normally refresh the pane without polling. On a network mount
that loses those events, configure a minimum refresh interval:

```sh
git config reviewui.pollseconds 45
```

Every ordinary refresh resets that floor, so it adds no polling while events are
arriving. `GIT_REVIEW_UI_WATCH=0` disables filesystem-event acceleration for
troubleshooting; keys, focus changes, mutations and `r` still read the CLI.

Set `GIT_REVIEW_UI_ASCII=1` to force ASCII glyphs. Setting `NO_COLOR` to any
value disables colour.

The start assistant remembers no private client state. To preselect its source,
set `reviewui.startsource` to `remote`, `local` or `offline` with `git config`.

## Updating and uninstalling

With Homebrew, use `brew upgrade git-review-ui` or
`brew uninstall git-review-ui`. Re-run either one-line installer to update its
installation. The project uninstaller removes both the CLI and terminal UI it
installed. To remove only the terminal UI installed by the PowerShell installer,
delete `git-review-ui.exe` from `~\.local\bin` (or from the `PREFIX` you chose).

The terminal client and CLI version independently. Check them with
`git-review-ui --version` and `git review --version`.

## Learn more

- [Project README](../README.md) — what the workflow does and every installation
  method.
- [CLI reference](../CLI.md) — commands, flags, recovery paths and advanced
  workflows.
- [Terminal UI changelog](CHANGELOG.md) — changes released under `tui-v*` tags.
- [Contributing to the terminal UI](CONTRIBUTING.md) — building, testing and
  packaging the Go client.
- [Report a bug](https://github.com/EzeVillo/git-review-workflow/issues/new?template=bug_report.yml)

## License

[MIT](../LICENSE)

## Review comments

Open the action list (`:`) and choose **Add comment**. Use Tab to move between
text, destination, optional path/side/line range and Save/Cancel. Every submission
requires a fresh **Local** or **Shared** choice. Enter in the body adds a line;
Ctrl+Enter submits where the terminal supports it. Tab to **Save**, then Enter,
is always available. Esc closes the form; errors keep its text and destination.

Scope defaults to the current file when available. Entering a complete line range
selects those lines; use the Scope control to choose File or General while keeping
your text and coordinates. Saving disables the form; success closes it and errors
keep it open. Only existing documents appear; Delete removes a preparation,
retained Local result or pending Shared preparation after confirmation.

The Comments block keeps Local and Shared separate. Copy path sends the
absolute path of an existing Local document to the terminal clipboard, including
retained results. Open uses your configured editor; Renumber numbers that document's entries. Diff selects a physical entry
and displays its captured changes in the terminal, provided the original Git
objects remain available. It does not depend on the current file still existing.

Local stays in Git's data directory. Shared starts from the branch's document
during a review. Save/Continue keeps its private preparation, including
deletions. After Finish stages it, that editable preparation is removed.
Outside a review, Comments sits between Walkthrough and Compare and reads Shared
from the current branch, taking precedence over saved preparations. Continue
restores the saved preparation. Finish delivers Shared to
`.review/comments.md`; pending delivery offers Prepare with document comparison
and retry. Comparisons retain Local comments automatically when closed.
Finishing does not open an editor automatically.
The comment form labels the text field explicitly. The Diff browser shows a
compact location and a one-line preview, with `…` when the comment is shortened.
The complete comment scrolls below; original revision IDs are folded under
Details, while warnings about unsaved captures stay visible. Press `d` to toggle Details. The diff stays inside the terminal, and Tab
returns to the complete comment. Selected lines are marked on the
recorded version. Local results and pending Shared preparations can be deleted
after Finish; delivered Shared offers reading and historical diffs.
