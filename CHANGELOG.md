# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.1] - 2026-06-19

First tagged release.

### Added

- `git review-pr <branch> [base] [--delta | --from <commit>] [--step]` — fetch
  `origin` and stage a pull request diff on a `review/<branch>` branch for inline
  review.
- `git review-next` / `git review-prev` — walk a `--step` review forward and
  backward, banking and restoring edits per commit.
- `git review-status` — show the state of the review on the current branch.
- `git finish-review [--onto-source] [--push] [--resume]` — extract review edits
  onto `review-fixes/<branch>` or the PR branch itself.
- `git review-abort` — cancel the current review and return to where you started.
- `git clean-review [branch] [--forget]` — delete the `review/*` and
  `review-fixes/*` branches.
- `-V` / `--version` flag on every command, reporting `0.0.1`.
- `install.sh` / `uninstall.sh` and a bash completion script.
- CI (shellcheck + bats) on every push and pull request.

[0.0.1]: https://github.com/ezevillo/git-review-workflow/releases/tag/v0.0.1
