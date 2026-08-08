# Changelog

## Unreleased

- Whole and step multi-file Diff use a single `DiffRequestChain` window
  (Prev/Next file) instead of one editor tab per file. Whole keeps its **Diff**
  button for open-all.
- Fix step Diff showing an empty pane titled **M**: `diff-tree` lacked
  `--no-commit-id`, so the commit SHA was parsed as a status field and the
  status letter became the "path".
- Fix tool-window title bar: stop calling `DefaultActionGroup.getChildren(null)`
  (platform throwable on 2024.3+); expand via `getChildren(ActionManager)`.

## 0.1.0

- Initial IntelliJ IDEA plugin with full action/situation parity target vs the VS Code extension.
- Domain layer (porcelain parsers, panel model, intent, housekeeping argv) covered by JUnit.
- Native tool window, start wizard, open/diff, finish cycle, housekeeping, CLI log.
- Canonical multi-client surface: `contracts/client-product-surface.yaml`.
