# Changelog

## [Unreleased]

- The extension now loads into Visual Studio. The package is a real `AsyncPackage`:
  **View → Other Windows → git review** opens the tool window, and **Tools → Options →
  git review** holds the path to the git-review CLI.
- Opening a file, opening a diff against the review's base, showing the why and running
  the start wizard now go through Visual Studio itself; the panel follows the IDE theme.
- **Refresh**, **Finish**, **Save**, **Cancel** and **Preview edits** are now icon
  buttons on the tool window's own toolbar — where VS Code and the JetBrains
  plugin put them — instead of a row of text buttons inside the panel. Which of
  them is showing still comes from the same layout the panel body does.
- **Preview edits** does something: `git review preview` opens as a read-only
  document, the same as in the other two clients. It used to answer with a note
  pointing at a menu Visual Studio does not have.
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
