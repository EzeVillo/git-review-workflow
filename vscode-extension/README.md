# git review — VS Code extension

Review a [git-review-workflow](../README.md) pull request from a panel that
shows where you are: the current entry of the walkthrough, its position in the
reading order the author chose, whether they marked it `key`, and the *why*
they wrote for it. The full sequence and the files the walkthrough doesn't cover
are one keystroke away in a quick pick, and commands jump to the file, advance
and go back — all without leaving the editor.

A review without a walkthrough runs in whole mode, and there the panel is the
list of files the range touches: a row opens that file's diff, and one control
above them opens every change at once — the same thing step's *Diff* does for a
commit, applied to the range. The last row you opened stays marked, so a list
you are halfway through still says where you were after closing the editor.

With no review on the current branch the panel lists the ones open elsewhere in
the repository — active and saved, with their mode and position — so a review
you put aside doesn't have to be remembered by name. Saved ones offer
*Continue*; an active one is listed without an action, because going back to it
is a branch checkout and the editor's branch picker already does that.

## Panel actions

Everything below is a command the panel exposes. Lifecycle actions (Finish,
Save, Cancel, and Refresh) are icon buttons on the view title bar; the rest are
buttons inside the webview or the Command Palette. Each one shells out to the
matching `git review` verb — the extension never invents a second way to change
review state.

| Action                       | When it appears                                                                                                                                                                                                 | CLI                                                                                                         |
|------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------|
| **Start a review**           | Empty state (`no-review`): pick branch, origin, range (if a prior tip exists), then how to read it — only layouts the CLI reports as viable for that tip/range (walk when the PR has a walkthrough, keys only when there are keys; no opaque “automatic”). Also Command Palette while `finish-pending` (another source is fine if the tree is clean) | `git review start …`                                                                                        |
| **Cancel review**            | View title icon while an active review (or a mid-conflict finish) is open                                                                                                                                       | `git review abort`                                                                                          |
| **Finish review**            | View title icon while an active review is open (hidden on a read-only **compare**)                                                                                                                              | `git review finish` / `finish --onto-source`                                                                |
| **Save for later**           | View title icon while an active review is open (not during a mid-conflict finish)                                                                                                                               | `git review save`                                                                                           |
| **Undo finish**              | After a completed finish with undo still available (`finish-pending`), or a finish stopped mid-conflict (`finish-conflict`)                                                                                     | `git review finish --abort`                                                                                 |
| **Clean**                    | `finish-pending` panel (the finished source); also Command Palette for any leftover                                                                                                                             | `git review clean --keep-fixes <branch>` from the panel; palette default is full `clean` / `clean <branch>` |
| **Continue** (finish)        | Finish stopped mid-conflict, after you resolve the markers in the tree                                                                                                                                          | `git review finish --resume`                                                                                |
| **Discard** (saved / orphan) | Inventory row: saved review or orphan leftover                                                                                                                                                                  | `git review forget --saved …` / `git review clean …`                                                        |
| **Forget** saved / delta     | Command Palette                                                                                                                                                                                                 | `git review forget --saved` / `--delta` (`--all`, `--stale`)                                                |
| **Preview edits**            | View title (active review) or palette; optional stat                                                                                                                                                            | `git review preview` / `--stat`                                                                             |
| **Compare revisions**        | Empty state (`no-review`): secondary actions under Start; also Command Palette. The resulting review is **read-only**: the panel shows a note and hides Finish (CLI refuses writeback)                          | `git review compare <a> <b>`                                                                                |
| **Walkthrough Init / Build** | Empty state (`no-review`): secondary actions under Start (author flow); also Command Palette                                                                                                                    | `git review walkthrough init` / `build`                                                                     |

Mutations (clean, forget, compare, walkthrough write, and the lifecycle
actions above) ask for a confirmation that names what will happen. Preview is
read-only and does not.

A completed finish that left edits on `review-fixes/<branch>` (or on the PR
branch with `--onto-source`) is **not** the empty state: the review already
finished. The panel names the destination of the staged edits and offers
*Clean* (`git review clean --keep-fixes <src>` — drops the leftover `review/*`
undo point; leaves your staged edits where finish put them — `review-fixes/*`
or the PR branch with `--onto-source` — and leaves `--delta` alone) or *Undo finish*
(`finish --abort`). Commit and push the edits from Source Control as usual. A finish
stopped mid-conflict keeps the review readable (mode, branch, current entry)
but locks navigation until you *Continue* or *Undo finish*.

## The CLI is the only source of truth

The extension never derives review state on its own. Everything it shows comes
from re-invoking `git review status --porcelain` / `--why` / `list --porcelain`
and reading the result — it does not read git config, refs or branches to work
out the mode, the position or the sequence, and it does not write config, move
refs or touch the index to change them.

The rule that follows from that, and the one to remember when adding anything
here: **if the panel needs something the CLI does not report, it gets added to
the CLI.** Never to the extension. A value this side could compute from the
repository is still a second source of truth, and the moment the two disagree
the panel is lying about a review the reviewer is trusting it with.

`../specs/002-extension-vscode/` has the original design;
`../specs/005-ciclo-review-panel/` adds the lifecycle; and
`../specs/006-superficie-panel-completa/contracts/cli-invocation.md` is the
current closed list of what the extension may invoke (including housekeeping,
preview, compare, and walkthrough).

One thing that list does not yet settle: the panel shells out to git directly to
build the file list behind a multi-file diff — `readCommitChanges` for a commit
in step, `readRangeChanges` for the range in whole, both in
`src/commands/openEntry.ts`. Neither derives anything about the review: the
commit id comes from the CLI, `HEAD` on a review branch is the merge-base by
construction, and git is only asked which files are on each side so the diff
knows what to open. But they are direct git calls in a codebase whose whole
point is not making them, and no spec covers them either way. Left as is on
purpose, to be decided.

The one thing the extension does keep between sessions is which file you last
opened from whole's list, per review branch, in the host's `workspaceState`
(`LAST_OPENED_KEY` in `src/extension.ts`). That is not review state and does not
compete with the CLI for it: whole has no cursor and there is no verb to ask,
so where you had got to is only ever known by the editor that opened the diff.
It is stored by path, and the model drops it when that path is no longer in the
range — the mark can only ever point at a row the CLI just reported.

## Requirements

- VS Code ^1.75.0.
- `git review` ≥ 0.4.0 discoverable as a git subcommand (or point the
  `gitReview.path` setting at the dispatcher directly).

## Developing

```sh
npm install
npm run watch      # esbuild in watch mode
```

### Running it in a real editor

Open this folder in VS Code and press F5 (the *Run Extension* launch
configuration) to launch an Extension Development Host — a second window with
the extension loaded from this checkout. Changes need a reload of that window
(*Developer: Reload Window*), not a restart.

The panel only has something to show inside a repository with an active review.
The sandbox builds a throwaway pull request to open there:

```sh
../tests/sandbox.sh                 # prints where it built the repo
git -C <sandbox>/work review start feature/checkout
```

It also builds one branch per state the panel can reach but a single well-formed
pull request never shows — start `feature/notifications` for the unannotated
entries that close a reading order, `feature/telemetry` for whole mode,
`feature/legacy` for the degraded note — plus a completed finish with undo
still available (`feature/shipping` → `review-fixes/…`, panel
`finish-pending`) and a finish stopped mid-conflict (`feature/conflict`,
panel `finish-conflict`), and leaves three saved reviews on `develop`, which
is the empty state's inventory: one row offering `Continue`, and two that
explain why they cannot. On `develop` the panel also shows a finish-pending
screen for `feature/shipping` (*Clean* / *Undo finish*; Start lives on the
Command Palette if you need another PR). The mid-conflict branch appears as
an active leftover with a `?` hover — switch to `review/feature/conflict`
for the conflict banner. The script prints the whole map when it finishes.

Then open `<sandbox>/work` in the development host. Note that the host inherits
the `PATH` of the VS Code that launched it, not the one `env.sh` sets up inside
the sandbox: either install this checkout (`../install.sh`) or point the
`gitReview.path` setting at `bin/git-review`.

### Previewing the panel

```sh
npm run preview        # writes out/preview/index.html and prints its file:// URL
npm run preview:watch  # regenerates on save; reload the browser
```

Renders the panel's states side by side in a browser — walk, step, whole,
loading and the empty states — at sidebar width, with a switch for the dark,
light and high-contrast themes. It's the real `panelHtml()` fed by
`parsePorcelain()` + `buildPanelModel()` over sample porcelain output, so it
follows the source with nothing to keep in sync by hand; edit
`preview/fixtures.ts` to add a state.

Three things it can't show: the buttons have no extension behind them; the
theme variables in `preview/build.ts` are an approximation of VS Code's, not
the ones your editor resolves (a `--vscode-*` variable the panel starts using
has to be added there too, or it will look wrong in the preview and fine in the
editor); and the `loading` pane is that state held still — the timing around it
(the delay before the skeleton appears, the cap on a slow `--why`) only happens
while navigating. For anything beyond the render, use F5.

## Testing

```sh
npm test                  # unit + integration, compiling first
npm run test:unit         # pure functions, no VS Code host
npm run test:integration  # @vscode/test-electron, builds fixtures with the real CLI
```

Integration tests shell out to the `git review` on `PATH`, so install this
checkout first (`../install.sh`) if you haven't already. On Linux without a
display, run the integration suite under `xvfb-run -a`.

They also load the extension from `dist/`, which they rebuild first
(`pretest:integration`) whether you run them on their own or through `npm test`,
so a green run is always about the code you have now.

## Packaging locally

```sh
npx vsce package
```

Produces a `.vsix` you can install with `code --install-extension
git-review-vscode-<version>.vsix`. This isn't a Marketplace listing —
publishing there is out of scope for this feature.
