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

Open this folder in VS Code and press F5 to launch an Extension Development
Host with the extension loaded; open a `git-review-workflow` repository there
to try it against a real review.

## Testing

```sh
npm test            # unit + integration
npm run test:unit    # pure functions, no VS Code host
npm run test:integration  # @vscode/test-electron, builds fixtures with the real CLI
```

Integration tests shell out to the `git review` on `PATH`, so install this
checkout first (`../install.sh`) if you haven't already. On Linux without a
display, run the integration suite under `xvfb-run`.

## Packaging locally

```sh
npx vsce package
```

Produces a `.vsix` you can install with `code --install-extension
git-review-vscode-<version>.vsix`. This isn't a Marketplace listing —
publishing there is out of scope for this feature.
