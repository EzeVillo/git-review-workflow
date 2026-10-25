# git review workflow for Visual Studio

**Review PRs with a guided reading order and context.**

[`git review`](https://github.com/EzeVillo/git-review-workflow) helps you review changes from a coding agent or another developer with a walkthrough: where to start, why each file changed, and what needs attention. Follow the author's reading order or prepare your own, inspect the implementation and leave observations.

The complete PR stays available as **editable changes** in your working tree. Go to a definition, find references, and run tests when useful. If you make corrections, finishing extracts them onto a separate branch. You can also complete a guided review without editing code.

## What you get

- **A reading order, when the PR has one.** The author (often an AI coding agent) can commit a walkthrough beside the change: one file at a time, in the order that makes the change make sense, each with the reason it is there. The ones that carry the point are marked `key`. No walkthrough? Draft your own, or read the whole range.
- **The whole range otherwise** — every file in the PR, one diff at a time or all at once.
- **Your place is kept.** Pause a review and come back to it; switch branches without losing where you were, or what you edited.
- **Corrections when you need them.** Finishing extracts any edits you made onto a separate branch; undo returns to the review if you changed your mind.

## Requirements

| | |
|---|---|
| IDE | Visual Studio **2022** (17.x) or later — **Windows only** |
| CLI | [`git-review-workflow`](https://www.npmjs.com/package/git-review-workflow) **≥ 0.7.0** |
| Git | `git` on `PATH` |

```powershell
npm install -g git-review-workflow
```

Also: Homebrew, a native Windows installer, and a no-Node one-liner — see the [main README](https://github.com/EzeVillo/git-review-workflow#readme).

## Getting started

1. Install the CLI (above).
2. Install this extension from the Visual Studio Marketplace (or load the `.vsix` locally).
3. Open a single-folder git repository.
4. Open the **git review** tool window (View → Other Windows / Tools → git review).
5. **Set the base branch** once, then **Start a review**.

The extension never invents review state: every refresh is `git review status --porcelain` (and related porcelain verbs). Multi-root solutions are not supported — same rule as the CLI `cwd`.

## Privacy

No telemetry. No network calls except the ones you trigger through the CLI (`start` may fetch; `forget --delta --stale` may fetch). Support links open GitHub in your browser or your email application.

## Links

- [Source & docs](https://github.com/EzeVillo/git-review-workflow/tree/main/visualstudio-extension)
- [CLI project](https://github.com/EzeVillo/git-review-workflow)
- [Report a bug](https://github.com/EzeVillo/git-review-workflow/issues/new?template=bug_report.yml)
- [License (MIT)](https://github.com/EzeVillo/git-review-workflow/blob/main/visualstudio-extension/LICENSE)
