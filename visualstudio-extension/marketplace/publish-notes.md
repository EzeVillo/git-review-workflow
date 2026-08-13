# Visual Studio Marketplace listing checklist

Use this when publishing `com.ezevillo.gitreview.vs` on
[marketplace.visualstudio.com](https://marketplace.visualstudio.com/).

## Package metadata (in-repo)

| Asset | Path | Notes |
|-------|------|--------|
| Display name | `source.extension.vsixmanifest` → DisplayName | `git review workflow` |
| Short description | same → Description | matches VS Code / JetBrains one-liner |
| Icon | `src/GitReview.VS/Resources/Icon.png` | product mark (same geometry as VS Code `media/icon.png`) |
| Preview / gallery mark | `Resources/Icon-256.png` | larger mark for listing chrome |
| License | `LICENSE` (MIT) | referenced from vsixmanifest |
| Overview | `marketplace/overview.md` | paste into Marketplace “Overview” (or ship as GettingStarted) |
| Release notes | `CHANGELOG.md` | |
| Tags | git; review; pull request; … | in vsixmanifest |
| Categories | Source Control / Other (set in Marketplace portal) | portal-side for classic VSIX |

## Screenshots (upload in the portal)

Capture from the fixture gallery so labels stay byte-identical to the other clients:

```powershell
cd visualstudio-extension
dotnet run --project src/GitReview.VS -- --preview
```

Suggested frames (store under `marketplace/screenshots/` before upload — **not** required in the VSIX binary):

1. `01-cli-missing.png` — install hint + Copy + Other install options  
2. `02-no-review-setup.png` — Set the base branch  
3. `03-no-review-ready.png` — inventory + Start a review + Support  
4. `04-review-walk.png` — identity bar, why, File/Diff, prev/next  
5. `05-review-whole.png` — file list + Diff (open all)  
6. `06-finish-pending.png` — Clean / Undo finish banner  

Captions should reuse the same English product strings (no paraphrasing).

## Icon generation

Do **not** hand-draw marketplace icons. Extend / run the shared generator:

```sh
# from monorepo (requires Pillow)
python vscode-extension/media/_build_icon.py
```

That script already emits VS Code + JetBrains marks; it also writes
`visualstudio-extension/media/` and `src/GitReview.VS/Resources/` when present
(see generator footer).

## Publisher

Publisher id **EzeVillo** (same as VS Code Marketplace). Sign in with the
publisher account that owns the VS Code listing when creating the VS gallery
entry so branding stays consistent.
