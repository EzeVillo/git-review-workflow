# git review — VS Code extension

Review a [git-review-workflow](../README.md) pull request from a panel that
shows where you are: the current entry of the walkthrough, its position in the
reading order the author chose, whether they marked it `key`, and the *why*
they wrote for it. The full sequence and the files the walkthrough doesn't cover
are one keystroke away in a quick pick, and commands jump to the file, advance
and go back — all without leaving the editor.

The extension never derives review state on its own: everything it shows
comes from re-invoking `git review status --porcelain` / `--why` and reading
the result. See `../specs/002-extension-vscode/` for the full design
(`contracts/cli-invocation.md` is the closed list of what the extension is
allowed to invoke).

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

Then open `<sandbox>/work` in the development host. Note that the host inherits
the `PATH` of the VS Code that launched it, not the one `env.sh` sets up inside
the sandbox: either install this checkout (`../install.sh`) or point the
`gitReview.path` setting at `bin/git-review`.

### Previewing the panel

```sh
npm run preview        # writes out/preview/index.html and prints its file:// URL
npm run preview:watch  # regenerates on save; reload the browser
```

Renders the panel's states side by side in a browser — walk, step, whole and
the empty states — at sidebar width, with a switch for the dark, light and
high-contrast themes. It's the real `panelHtml()` fed by `parsePorcelain()` +
`buildPanelModel()` over sample porcelain output, so it follows the source with
nothing to keep in sync by hand; edit `preview/fixtures.ts` to add a state.

Two things it can't show: the buttons have no extension behind them, and the
theme variables in `preview/build.ts` are an approximation of VS Code's, not
the ones your editor resolves. A `--vscode-*` variable the panel starts using
has to be added there too, or it will look wrong in the preview and fine in the
editor. For anything beyond the render, use F5.

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
