# Contributing to the VS Code extension

This covers working *on* the extension. For what it does and how to use it, see
the [README](README.md); for the CLI and the workflow itself, the
[project README](../README.md) and [CONTRIBUTING.md](../CONTRIBUTING.md) at the
root.

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
npm run test:unit      # pure functions, no VS Code host
test/run-docker.sh     # integration, in a Linux container
```

Unit tests are pure functions and run anywhere in milliseconds. **The
integration suite runs in the container** — like the CLI's bats suite, and for
the same reason. It shells out to a real `git review` for every fixture and
every panel refresh, each verb costs a dozen processes, and a process costs
about 50ms on Windows against 1ms on Linux (`CreateProcess`, the DLL loads and
the antivirus scan). The whole suite takes 38 seconds in the container against
16 minutes natively on Windows — the same 66 tests, passing either way. CI still
runs it on real Ubuntu, macOS and Windows runners, so this skips no coverage.

```sh
test/run-docker.sh                     # the whole suite
test/run-docker.sh open-entry          # specs whose path matches
MOCHA_GREP='opens the diff' test/run-docker.sh
test/run-docker.sh -- sh               # a shell inside the container
```

The first run builds the image ([`test/Dockerfile`](test/Dockerfile): node, git,
xvfb and Electron's shared libraries) and downloads a VS Code. After that,
`node_modules`, that download and the npm cache live in named volumes, so a run
is only the suite. To start from scratch:

```sh
docker volume rm grv-vscode-node-modules grv-vscode-test-cache grv-vscode-npm-cache
```

`npm run test:integration` still runs the suite directly, which is what CI
invokes and what the container runs internally. Reach for it when you need the
editor on your own machine — a screenshot, a debugger, a platform-specific
failure — knowing it will be slow on Windows. It needs **Node 22 or newer**:
`@vscode/test-electron` 3.x asks for it, and 3.x is the first release that
locates the macOS binary through the app bundle's `Info.plist` instead of the
historical `Contents/MacOS/Electron` — a name VS Code renamed to `Code` in 1.110
and stopped shipping a symlink for, which fails on macOS alone with
`spawn .../Contents/MacOS/Electron ENOENT`. On Linux without a display, run it
under `xvfb-run -a`.

Whichever way you run them, the tests resolve the `git review` in this checkout:
`runTests.ts` puts `../bin` at the front of the `PATH` it hands to the test
host, so both the fixtures and the extension under test find it there — no
`../install.sh` needed, and a CLI installed elsewhere on your `PATH` cannot
shadow the tree you are testing. The container has to defend that: it sets
`VSCODE_CLI=1`, because otherwise VS Code resolves a login shell's environment
and replaces its own with it, dropping that `PATH` and leaving every test
failing as `cli-missing`.

They also load the extension from `dist/`, which they rebuild first
(`pretest:integration`) whether you run them on their own or through `npm test`,
so a green run is always about the code you have now.

Two of the specs open editor tabs and are flaky on Windows for reasons that have
nothing to do with the extension — the container takes them out of the picture,
but the Windows runner still hits them. Before chasing a *"no se abrió ningún
tab"* there, re-run the suite on an unmodified checkout to see whether it was
already failing.

## Packaging

```sh
npm run package     # esbuild --production, then vsce package
```

Produces a `.vsix` you can install with
`code --install-extension git-review-workflow-<version>.vsix`.

Two things travel into that package and are therefore user-facing: the
[README](README.md), which the Marketplace renders as the extension's *Details*
tab, and the [CHANGELOG](CHANGELOG.md), which it renders as *Changelog*. Keep
their links **absolute** — a relative one is rewritten against the repository
root, not against this directory, and ends up broken on the Marketplace.
