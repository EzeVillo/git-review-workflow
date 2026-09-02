# Changelog

Notable changes to the **git review** terminal UI. The CLI it drives has its own
[changelog](../CHANGELOG.md) and its own
[releases](https://github.com/EzeVillo/git-review-workflow/releases).

This project follows [semantic versioning](https://semver.org/spec/v2.0.0.html)
and the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

## [0.1.0] — 2026-09-01

First release. Requires `git review` **0.9.0** or newer — the version that
introduces the `ui` verb.

### Added

- **The whole review, in a terminal pane.** `git review ui` (or `git review-ui`)
  opens a panel for the repository you are standing in: start a review, walk it
  with `n`/`p`, open an entry or its diff in your editor, ask why an entry is in
  the reading order, and finish, save or cancel — without leaving the pane. Below
  that sit the same sections the editor clients draw: the reviews in the
  repository, *Walkthrough* with the two authoring guides, the reading orders you
  finished with, the branches of edits a `finish` left behind, *Compare*,
  *Settings* and *Support*.

- **It reads the CLI and nothing else.** Every piece of state comes from
  re-invoking `git review`'s porcelain records; the client never inspects the
  repository on its own. Which means it cannot disagree with the CLI about what
  is going on, and a `git review next` you run in a second terminal shows up here.

- **A key bar that reflects the situation.** `j`/`k` move the focus, `enter`
  activates it, `n`/`p` move the review's cursor and are reserved for that alone,
  `r` refreshes, `:` opens the action list, `g` picks an entry, `m` toggles mouse
  reporting, `q` quits. The bar is drawn from the same table the keys resolve
  from, so a key that exists and is not shown is impossible, and one that no
  longer applies disappears rather than failing quietly.

- **Everything is reachable by keyboard alone, and everything by mouse alone.**
  Mouse reporting starts on and `m` turns it off, which is what gives your
  terminal's own text selection back.

- **It respects the terminal it is in.** `NO_COLOR` (any value) drops colour, and
  a non-UTF-8 locale or console code page switches to an ASCII glyph set — the two
  decided independently, so a terminal that sets `NO_COLOR` does not also lose its
  box glyphs. Both are decided once at startup. Rendering is pinned by golden
  files at 80×24 and 120×40 in both glyph sets.

- **The pane keeps up without polling.** Filesystem events on the gitdir bring a
  refresh forward; there is no timer asking the CLI how things are going. On
  network mounts whose notifications are unreliable, `git config
  reviewui.pollseconds 45` arms a read only when that long has passed with no
  other refresh — every normal refresh resets the floor, so it adds nothing while
  notifications are arriving. `GIT_REVIEW_UI_WATCH=0` turns event acceleration off
  entirely for support, leaving keys, focus, mutations and `r` reading the CLI as
  usual.

- **`-h` and `--version`, and a refusal for anything else.** `git review ui`
  passes every argument through unchanged, so a typo lands on the binary; it says
  so on stderr and exits non-zero rather than coming up as if nothing had been
  asked. All three answer before any terminal state is read, so they work in a
  pipe and with no TTY.

- **A credential prompt cannot hang the pane.** Network invocations run with
  terminal prompts disabled and a timeout; a repository that would ask for
  credentials comes back to the panel with a diagnosis.

- **It says nothing before it has looked.** Until the first situation resolves,
  the panel reads *Reading the review state…* — and reporting a missing CLI takes
  evidence that names it, so a timeout or a spawn failure for some other reason is
  retried rather than published as "not installed".

- **Every wait has a visible, stable surface.** Refreshes and mutations keep the
  last truthful panel in place, disable stale controls immediately, and show
  action-specific progress after a short anti-flicker delay. The Start assistant
  keeps a loading surface between questions; failures and acknowledgements stay
  fixed above the key bar instead of being clipped by a long inventory. Creating
  an authoring guide refreshes the panel and opens its reported path, or names the
  created file when no editor is configured.

- **Confirmation only for what cannot be undone.** Starting a review does not
  confirm; discarding edits, deleting a reading order and the rest do, from
  wherever you reach them — the body, a key or the action list all arrive at the
  same dialog.

### Packaging

Installed with `brew install EzeVillo/git-review-workflow/git-review-ui`, or by
opting into it in either one-line installer (`GIT_REVIEW_WITH_UI=1` on the shell
one, `-WithUi` on the PowerShell one), which verifies the archive's checksum and
leaves the CLI installed if anything about the TUI fails. Seven static binaries
are attached to each `tui-v*` release: macOS and Linux on arm64 and amd64, Linux
armv7, and Windows on amd64 and arm64. There is no package registry.
