# Changelog

## Unreleased

- Minimum required CLI raised to **0.5.0** (parity with VS Code extension /
  `contracts/client-product-surface.yaml`).
- Whole and step multi-file Diff use a single `DiffRequestChain` window
  (Prev/Next file) instead of one editor tab per file. Whole keeps its **Diff**
  button for open-all.
- Fix step Diff showing an empty pane titled **M**: `diff-tree` lacked
  `--no-commit-id`, so the commit SHA was parsed as a status field and the
  status letter became the "path".
- Fix tool-window title bar: stop calling `DefaultActionGroup.getChildren(null)`
  (platform throwable on 2024.3+); expand via `getChildren(ActionManager)`.
- Fix the panel opening on a diagnostic nobody could act on: the tool window
  materializes before git4idea has discovered the repositories, and that first
  refresh reported "no single root" and stayed there until **Refresh** was hit
  by hand. The panel now waits for the VCSes instead of drawing an error, and
  re-reads itself when the repository mappings arrive.
- The panel no longer stretches its blocks: the primary button of a pane sits
  right under the text that introduces it, wrapped paragraphs keep their own
  height, and the empty state rules the inventory off from **Start a review**.
- Inventory rows read left to right like the extension's: name and actions on
  the left, badges and the `?` hint on the right edge.
- The primary control of each situation is painted with the IDE's default-button
  style, and links with the theme's link colour.
- The file list reads as a list of paths, not as a stack of buttons: each row is
  borderless, in the editor font, with the diff glyph the extension gives it,
  and takes a fill only under the pointer. The last opened one keeps the
  selection fill plus a bar at the margin. **Diff** / **File** carry their
  glyphs too, and the list heading is a quiet label above its list.

## 0.1.0

- Initial IntelliJ IDEA plugin with full action/situation parity target vs the VS Code extension.
- Domain layer (porcelain parsers, panel model, intent, housekeeping argv) covered by JUnit.
- Native tool window, start wizard, open/diff, finish cycle, housekeeping, CLI log.
- Canonical multi-client surface: `contracts/client-product-surface.yaml`.
