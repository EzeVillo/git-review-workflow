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

1. **Install the CLI** (`git review` 0.9.0 or newer):

   ```sh
   npm install -g git-review-workflow
   ```

   Homebrew, native Windows and no-Node alternatives are in the project
   [installation guide](../README.md#installation).

2. **Install the terminal UI.** With Homebrew on macOS or Linux:

   ```sh
   brew tap EzeVillo/git-review-workflow https://github.com/EzeVillo/git-review-workflow
   brew install EzeVillo/git-review-workflow/git-review-ui
   ```

   Or install the CLI and terminal UI together with a one-line installer:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-install.sh | GIT_REVIEW_WITH_UI=1 sh
   ```

   ```powershell
   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-install.ps1))) -WithUi
   ```

   Static binaries for macOS, Linux and Windows are also attached to every
   [`tui-v*` release](https://github.com/EzeVillo/git-review-workflow/releases).

3. **Open a repository and launch the interface:**

   ```sh
   cd path/to/repository
   git review ui
   ```

   `git review-ui` is an equivalent shortcut. If the repository has no base
   branch configured yet, the interface asks you to choose one before starting
   a review.

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
installation; the matching project uninstaller removes both the CLI and the
terminal UI it installed.

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
