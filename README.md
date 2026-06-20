# git-review-workflow

> Review a pull request branch locally as a single, staged diff — make fixes
> inline, then split your changes onto a clean branch (or straight onto the PR
> branch) ready to push.

[![CI](https://github.com/EzeVillo/git-review-workflow/actions/workflows/ci.yml/badge.svg)](https://github.com/EzeVillo/git-review-workflow/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/tag/EzeVillo/git-review-workflow?label=release&sort=semver)](https://github.com/EzeVillo/git-review-workflow/releases)

**English** · [Español](README.es.md)

---

When you review a PR you usually want to see **all** of its changes at once and
poke at them. `git review-pr` creates a `review/<branch>` branch whose working
tree holds the PR tip, but whose `HEAD` sits at the merge-base with your base
branch. The result: the entire PR shows up as **staged, uncommitted changes**.
Because it is just your working tree, you open the whole PR in your favourite
IDE — read the diff, edit inline, run it — and when you are done,
`git finish-review` extracts your edits onto a separate `review-fixes/<branch>`
branch (or onto the PR branch itself).

## Quick start

```sh
# 1. Install (Linux, macOS, WSL, and Windows via Git Bash)
curl -fsSL https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-install.sh | sh

# 2. Tell it where PRs are integrated, once per repo
git config reviewworkflow.base develop

# 3. Stage a PR branch as a single diff, then open the repo in your IDE
git review-pr feature/login
# ...read and edit the staged diff in your editor, run tests...
git finish-review               # extract your edits onto review-fixes/feature/login
```

Prefer Homebrew or a native Windows (PowerShell) installer? See
[Installation](#installation). For the full flow — re-reviewing updates, walking
a PR commit by commit, cleanup — see [Typical workflow](#typical-workflow).

## Installation

These commands plug into `git` — you run them as `git review-pr`,
`git finish-review`, and so on. Pick whichever method matches your setup. The
package-manager options are the easiest and **set up your `PATH` for you**.

### Homebrew (macOS / Linux)

```sh
brew tap EzeVillo/git-review-workflow https://github.com/EzeVillo/git-review-workflow
brew install EzeVillo/git-review-workflow/git-review-workflow
```

Tab completion is configured automatically. To update to the latest release:
`brew upgrade git-review-workflow`.

### Windows (PowerShell)

You still need [Git for Windows](https://gitforwindows.org), which provides the
shell these commands run in. Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-install.ps1 | iex
```

This installs the commands into `~\.local\bin` and adds that folder to your user
`PATH` automatically. Open a new terminal after it finishes. Re-run to update; to
uninstall:

```powershell
irm https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-uninstall.ps1 | iex
```

### One-line install (Linux, macOS, WSL, Git Bash)

No package manager? This downloads the commands and installs them into
`~/.local/bin` — you don't need to clone the project first:

```sh
curl -fsSL https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-install.sh | sh
```

Re-run to update (always installs the latest release). To uninstall (pass the
same `PREFIX` if you overrode it):

```sh
curl -fsSL https://raw.githubusercontent.com/EzeVillo/git-review-workflow/main/web-uninstall.sh | sh
```

<details>
<summary>From a downloaded copy</summary>

If you cloned or downloaded the project, open its folder in a terminal and run:

```sh
./install.sh
```

This installs all nine commands into `~/.local/bin` (change the location with
`PREFIX=/usr/local/bin ./install.sh`). Undo it any time with `./uninstall.sh`.
To update, just `git pull` inside the repo — the symlinks pick up changes
automatically.
</details>

<details>
<summary>"command not found" — adding <code>~/.local/bin</code> to your PATH</summary>

Your `PATH` is the list of folders your terminal searches when you type a
command. Homebrew and the PowerShell installer add their folder for you. The
one-line and manual installs use `~/.local/bin`, which is already on the `PATH`
on most systems. If it isn't, the installer prints a note — add it **once** by
pasting one line into your shell's config file:

| If your terminal uses…            | Add this line to the file…       | The line to add                        |
|-----------------------------------|----------------------------------|----------------------------------------|
| **bash**                          | `~/.bashrc`                      | `export PATH="$HOME/.local/bin:$PATH"` |
| **zsh** (default on recent macOS) | `~/.zshrc`                       | `export PATH="$HOME/.local/bin:$PATH"` |
| **fish**                          | *(no file — just run this once)* | `fish_add_path ~/.local/bin`           |

Not sure which one you use? Run `echo $0`. After editing the file, **open a new
terminal** (or `source` the file). Run `git review-pr --help` to confirm.
</details>

<details>
<summary>Tab completion (manual installs)</summary>

Homebrew sets this up for you. Otherwise, tell your shell to load the matching
file on start. Replace `/path/to/git-review-workflow` with where you downloaded
the project.

```sh
# bash — in ~/.bashrc
source /path/to/git-review-workflow/completions/git-review-workflow.bash

# zsh — in ~/.zshrc
source /path/to/git-review-workflow/completions/git-review-workflow.zsh

# fish — copy into fish's completions folder (no config line needed)
cp /path/to/git-review-workflow/completions/git-review-workflow.fish \
    ~/.config/fish/completions/
```

Then open a new terminal. Typing `git review-pr ` and pressing **Tab** now
offers your branch names.
</details>

<details>
<summary>Git Bash on Windows — SSL error during install?</summary>

If you see `schannel: next InitializeSecurityContext failed` or a
`revocation check` message, your Git for Windows is using the Windows SSL
backend. Fix it once, then re-run the installer:

```sh
git config --global http.sslBackend openssl
```

</details>

## Commands

> **How to read the syntax:** `<x>` is **required**, `[x]` is **optional**, and
> `a | b` means **pick one, not both**.

| Command                                                                | What it does                                                                                  |
|------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| `git review [--help \| --version]`                                     | List all commands or print the installed version.                                             |
| `git review-pr <branch> [base \| --delta \| --from <commit>] [--step]` | Fetch `origin`, then stage the PR diff on a new `review/<branch>` branch.                     |
| `git review-next` / `git review-prev`                                  | Move a `--step` review to the next / previous commit.                                         |
| `git review-status`                                                    | Show the state of the review on the current branch.                                           |
| `git review-list`                                                      | List every `review/*` branch in progress (current one marked `*`).                            |
| `git finish-review [--onto-source] [--push] [--resume]`                | From a `review/*` branch, extract your edits onto `review-fixes/<branch>` (or the PR branch). |
| `git review-abort`                                                     | Cancel the current review and return to where you started.                                    |
| `git clean-review [branch]`                                            | Delete the `review/*` and `review-fixes/*` branches for `<branch>`, or all of them.           |
| `git review-forget (<branch> \| --all \| --stale [--dry-run])`         | Discard the `--delta` marker for one branch, all of them, or only stale ones.                 |

### `git review-pr`

Has two independent axes — **range** (where the review starts) and **layout**
(`--step` or not), which compose freely.

- `base` — branch to diff against, taken from `reviewworkflow.base` (see below);
  a positional argument overrides it. **Required for a full review** — there is
  no built-in default, so a full review with no base set fails and asks you to
  configure one. Not used with `--delta` or `--from`, which carry their own
  starting point — passing an explicit base alongside them is an error (a base
  from config is simply ignored).
- `--delta` — review only the commits added **since your last review** of this
  branch, instead of the whole PR. Perfect for re-reviewing an updated PR. The
  recorded tip survives `clean-review`, so this works even after you deleted the
  review branches; discard it explicitly with `git review-forget`.
- `--from <commit>` — review only the commits **after `<commit>`**. Handy when
  there is no recorded review to delta from, or to pick an exact starting point.
  Mutually exclusive with `--delta`.
- `--step` — review the range **one commit at a time** (combine with `--delta`
  or `--from` to walk just those commits). You start on the first commit after
  the merge-base; the command prints its author message. Edit files, then run
  `git review-next` to bank your edits and move to the next commit with a clean
  tree. When the commits run out, run `git finish-review` and all your banked
  edits are replayed onto the PR tip — exactly as in a whole-PR review.
- Always updates from `origin` first and **fails** if it cannot. The review is
  built from `origin/<branch>`, never a stale local copy.
- Refuses to run if you have local changes — start from a clean branch.
- **Merges of the base branch are excluded.** If the author merged the base
  (e.g. `develop`) into the PR, that merged-in content is left out of the review
  in every mode, so you only see the author's own changes.

### `git review-next` / `git review-prev`

Move a `--step` review forward or backward. Each move banks the current commit's
edits and restores any edits you had banked on the commit you move to, so you can
walk back and forth without losing work.

### `git review-status`

Shows the current review: source PR, mode, and — in `--step` mode — which commit
you are on (`[k/N]`) and which steps have banked edits.

### `git review-list`

Shows *every* `review/*` branch in progress at once (with its source PR, mode and
step position). The branch you are currently on is marked with a `*`.

### `git finish-review`

- Default — create `review-fixes/<branch>` on top of the PR tip with your edits
  staged, so you can review and commit them yourself.
- `--onto-source` — add your edits as a commit on the PR branch itself.
- `--push` — push the resulting branch to `origin`. With `--onto-source` it
  refuses to push if `origin/<branch>` moved since your review.
- `--resume` — in `--step` mode, if banked edits overlap the PR tip, the replay
  leaves conflict markers and stops. Resolve them in the working tree, then run
  `git finish-review --resume` (with the same flags) to continue.

### `git review-abort`

Cancels the current review in one step: it returns you to the branch you started
from, then deletes the `review/<branch>` branch and its banked edits. Because the
review was cancelled (not completed), it rolls the `--delta` marker back to your
last actual review, so a later `--delta` does not skip commits you never
reviewed.

### `git clean-review`

- With no `<branch>`, deletes every `review/*` and `review-fixes/*` branch.
- Never deletes the branch you are currently on.
- Also drops any banked commit-by-commit edit refs, even when no review branches
  remain.
- Leaves the `--delta` marker untouched — discard it with `git review-forget`.

### `git review-forget`

Discards the recorded last-reviewed tip that `--delta` relies on. The marker is
kept deliberately so `--delta` survives `clean-review`; this is how you clear it.

- `<branch>` — forget the marker for one source branch.
- `--all` — forget every recorded marker (leaves `reviewworkflow.base` alone).
- `--stale` — fetch and prune `origin`, then forget only the markers whose
  `origin/<branch>` no longer exists (e.g. PRs that were merged and deleted).
  Aborts without removing anything if the fetch fails.
- `--dry-run` — with `--stale`, list what would be forgotten without doing it.
  Rejected with the other modes, where the target is already explicit.

## Configuring the base branch

The base branch is where PRs are integrated (`develop`, `main`, `master`, …) and
varies per team, so there is no default — set it once per repository:

```sh
git config reviewworkflow.base develop
```

Resolution order: positional `base` argument → `reviewworkflow.base`. If neither
is set, a full review fails and asks you to configure one.

## Typical workflow

```sh
git config reviewworkflow.base develop      # once per repo

git review-pr feature/login                 # stage the whole PR
# ...open the repo in your IDE, read the staged diff, edit inline, run tests...
git finish-review                            # extract fixes to review-fixes/feature/login
git diff --cached && git commit -m "address review comments"
git clean-review feature/login              # tidy up

# Re-review after the author pushes more commits:
git review-pr feature/login --delta          # only the new commits
git review-pr feature/login --delta --step   # ...and walk them one by one

# Or walk the PR commit by commit from the start:
git review-pr feature/login --step           # start on the first commit
# ...edit, then...
git review-next                              # bank edits, move to the next commit
git review-next                              # ...until "no more commits"
git finish-review                            # replay all your edits onto the tip

# Pick an explicit starting commit:
git review-pr feature/login --from a1b2c3d
```

## Requirements

- Git 2.23+ (uses `git switch`). Git 2.38+ is recommended: excluding base
  content that was merged into the PR uses `git merge-tree --write-tree`, and on
  older git that one step is skipped (the merged base content would then show in
  `--delta`/`--from`).
- A remote named `origin`.
- A POSIX shell. On Linux and macOS this is the default. On Windows the commands
  run under Git Bash or WSL, not in `cmd.exe` or PowerShell.

## Contributing

Bug reports, fixes and ideas are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md)
for how to run the tests and the release process.

## License

[MIT](LICENSE) © EzeVillo
