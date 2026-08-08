# Changelog

## Unreleased

- Drop **Open all changes** / bulk multi-diff in whole mode. IntelliJ opens one
  editor tab per file (unlike VS Code's single multi-diff tab), so the bulk
  action flooded the tab bar. Open files one at a time from the list. Step
  commit diffs still open, but as one `DiffRequestChain` window with Prev/Next
  file instead of N tabs.
- Fix step Diff showing an empty pane titled **M**: `diff-tree` lacked
  `--no-commit-id`, so the commit SHA was parsed as a status field and the
  status letter became the "path".

## 0.1.0

- Initial IntelliJ IDEA plugin with full action/situation parity target vs the VS Code extension.
- Domain layer (porcelain parsers, panel model, intent, housekeeping argv) covered by JUnit.
- Native tool window, start wizard, open/diff, finish cycle, housekeeping, CLI log.
- Canonical multi-client surface: `contracts/client-product-surface.yaml`.
