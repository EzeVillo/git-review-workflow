# Changelog

## [Unreleased]

- The extension now loads into Visual Studio. The package is a real `AsyncPackage`:
  **View → Other Windows → git review** opens the tool window, and **Tools → Options →
  git review** holds the path to the git-review CLI.
- Opening a file, opening a diff against the review's base, showing the why and running
  the start wizard now go through Visual Studio itself; the panel follows the IDE theme.
- `build-vsix.ps1` builds the `.vsix` and can install it, including into the
  Experimental Instance.
- Fixed: every CLI action ended in a "The calling thread cannot access this object"
  dialog. The action had already run; the panel was being redrawn from the thread the
  mutation finished on instead of the UI thread.

## [0.1.0] — 2026-08-12

- Initial Visual Studio client: portable domain (C# port of JetBrains `domain/`),
  CLI host, WPF panel driven by the same `PanelLayout` / `client-product-surface.yaml`
  as VS Code and IntelliJ.
- Marketplace packaging assets: product icon (shared mark), LICENSE, overview,
  publish checklist, vsixmanifest Icon / PreviewImage / tags.
