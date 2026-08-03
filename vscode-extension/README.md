# git review — VS Code extension

Review a [git-review-workflow](../README.md) pull request from a panel that
shows where you are: the current entry of the walkthrough, its position in the
reading order the author chose, whether they marked it `key`, and the *why*
they wrote for it. The full sequence and the files the walkthrough doesn't cover
are one keystroke away in a quick pick, and commands jump to the file, advance
and go back — all without leaving the editor.

With no review on the current branch the panel lists the ones open elsewhere in
the repository — active and saved, with their mode and position — so a review
you put aside doesn't have to be remembered by name. Saved ones offer
*Continue*; an active one is listed without an action, because going back to it
is a branch checkout and the editor's branch picker already does that.

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

`../specs/002-extension-vscode/` has the full design;
`contracts/cli-invocation.md` is the closed list of what the extension may
invoke, and the explicit list of what it may never do.

One thing that list does not yet settle: the panel shells out to git plumbing
directly to build the file list for a commit's diff (`readCommitChanges` in
`src/commands/openEntry.ts`). It derives nothing about the review — the commit
id comes from the CLI, and git is only asked which files that commit touches —
but it is a direct git call in a codebase whose whole point is not making them,
and no spec covers it either way. Left as is on purpose, to be decided.

## Requirements

- VS Code ^1.75.0.
- `git review` ≥ 0.3.0 discoverable as a git subcommand (or point the
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
`feature/legacy` for the degraded note — and
leaves three saved reviews on `develop`, which is the empty state's inventory:
one row offering `Continue`, and two that explain why they cannot. The script
prints the whole map when it finishes.

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

They also load the extension from `dist/`, and only `npm test` compiles first
(through `pretest`). Running `npm run test:integration` on its own tests
whatever was built last — run `npm run compile` first, or keep `npm run watch`
going, or a green run may be about code you already changed.

## Packaging locally

```sh
npx vsce package
```

Produces a `.vsix` you can install with `code --install-extension
git-review-vscode-<version>.vsix`. This isn't a Marketplace listing —
publishing there is out of scope for this feature.
