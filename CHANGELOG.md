# Changelog

Notable changes to the **git review** CLI. The four clients that drive it — the
[VS Code extension](vscode-extension/CHANGELOG.md), the
[JetBrains plugin](jetbrains-plugin/CHANGELOG.md), the
[Visual Studio extension](visualstudio-extension/CHANGELOG.md) and the
[terminal UI](tui/CHANGELOG.md) — version separately and keep their own.

This project follows [semantic versioning](https://semver.org/spec/v2.0.0.html)
and the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

This file starts at 0.2.1. Earlier versions are only in the
[GitHub Releases](https://github.com/EzeVillo/git-review-workflow/releases).

## [0.9.0] — 2026-09-01

### Added

- **`git review ui` opens the terminal interface.** The TUI is a separate static
  binary with its own release; this verb hands the terminal off to it, resolved
  from `$GIT_REVIEW_UI` (a direct path to the program, the same idiom as
  `GIT_EDITOR`/`GIT_PAGER`) or `git-review-ui` on your `PATH`. It `exec`s rather
  than spawning a subshell, so signals and the exit code reach your shell with
  nothing in between. With neither found it refuses, printing the install path
  that fits the platform it is running on — it never installs or prompts on your
  behalf, and it does not need the network to explain why. `git review-ui` is the
  shell-friendly synonym.

## [0.8.0] — 2026-08-30

### Added

- **`reviewworkflow.advice` turns off the notes you already have.** Several
  commands end by naming a command or a flag that does the next thing, or by
  describing something that also travels as a porcelain record. In a terminal
  that is the answer; to a program driving the CLI it is prose about a button it
  already draws. Setting `git config reviewworkflow.advice false` (or exporting
  `GIT_REVIEW_ADVICE=0` for one invocation) drops exactly those. It is **on by
  default**, so a terminal loses nothing, and a note that both offers a command
  and reports state keeps the state and loses the offer. The four clients export
  the variable on every invocation.

- **`walkthrough draft --porcelain` and `walkthrough init --porcelain`** replace
  the human summary line with a `merged` record —
  `merged<TAB>kept<TAB>added<TAB>dropped` — so a caller gets the three numbers
  without parsing a sentence.

## [0.7.0] — 2026-08-27

### Added

- **`git review walkthrough guide [--team] [--delete]`, and there are now two
  authoring guides.** There used to be one, `.review/walkthrough-guide.md`,
  mentioned only inside the skeleton and in one stderr note. There are now two:
  that one (shared, committed) and your own,
  `<git-common-dir>/review-walkthrough-guide.md`, outside the versioned tree.
  **Both apply when both have content, and yours wins a contradiction.** The
  skeleton's bullet no longer hardcodes a path — it names whichever guides are in
  force, and says nothing when there are none.

  The command creates the file **empty** on purpose: there is no `build` that
  rejects a half-filled skeleton, so instructions left behind inside one would be
  read by the next agent as if they were your conventions. `--delete` only ever
  removes your own; the shared one is a tracked file (`git rm` and commit), and
  creating the shared one **inside a review** is refused — `finish` extracts with
  `git add -A`, so the file would leave in someone else's `review-fixes/`. That
  hole is the reason the whole feature exists.

- **`walkthrough init` updates instead of refusing.** A walkthrough gets written
  when the PR is finished, and then the PR keeps moving. Entries whose file is
  still in range keep their number, their *why* and their `> key`; files that
  entered arrive as `## ?.`; entries whose file left are dropped and named on
  stderr. `--force` still means "discard everything and write a blank skeleton".
  Only `init` — the reviewer's draft is written against a tip that `start`
  freezes, and that side has a whole mesh of messages built on "the file is
  there, I refuse".

- **A `> at: <blob>` anchor under each entry, stamped by `build`.** On the next
  `build`, entries whose file changed since then get named. It is the only thing
  that can detect a stale *why*: drift compares the **set of paths**, so a PR that
  keeps touching the files it already annotates passes green. It is a **note,
  never a failure**.

- **`init --stdout` and `build --from <file>|-`** — the author-side agent circuit,
  which only existed on the reviewer's side, the opposite of what the skeleton
  itself says. `build --from` takes no `--force`: build already rewrites the
  sidecar on every run, and the file is tracked.

- **A `walkthrough` record in `config --porcelain`**:
  `walkthrough<TAB><state><TAB><path><TAB><annotated><TAB><total>`, with state
  `in-sync|stale|unknown|absent`. The traffic light is **cheap and approximate**
  on purpose, and it excludes `.review/`, which is what keeps committing the
  walkthrough itself from marking it stale.

- **A draft knows when its review is over.** The `draft` record of
  `config --porcelain` gains an eighth field, `<state>` = `fresh` | `reviewed`.
  `reviewed` means a **completed** review of that branch covered the same tip the
  draft was generated against. It is additive: an older CLI does not emit it and
  every client reads the absence as `fresh`. **Nothing is deleted on its own** —
  neither `clean` nor `finish` touches the file; the state only changes where it
  is drawn.

- **`git review forget --draft --reviewed [--dry-run]`** is the broom for drafts
  whose review is over — the ones you cannot name, because a draft is spelled by
  its branch. It **skips** (and names) one a walk review is currently reading.

- **`git review list` enumerates the `review-fixes/*` branches**, under `fixes`,
  with what git can say about each (`nothing committed on it`, `already in the
  base`, `has commits the base does not have`, `no base set, cannot tell`), and no
  longer stops early with "no reviews in progress" when they are all that is left.
  They were the most frequent leftover — one per PR reviewed, forever — and the
  only state of the repository no surface named. `list --porcelain` gains a
  `fixes<TAB>name<TAB>current<TAB>session<TAB>state` record at a **constant**
  process cost.

- **`git review clean --fixes-only [branch]`** is the symmetry `--keep-fixes` was
  missing: it deletes only `review-fixes/*` and leaves the whole session standing
  — edit refs, the finish undo point, `--delta` markers. Passing both flags is an
  error.

### Fixed

- **`walkthrough draft --delta` no longer destroys prose.** Over an existing
  draft it discarded entries whose file fell outside the delta range **even when
  the PR was still changing that file**, and that prose does not come back — a
  draft lives outside git. The note also claimed something false ("the PR no
  longer changes these files"). Two questions are now separate: the range in force
  says which entries have to be there, the PR's range says which ones may be.

- **`walkthrough draft` updates instead of refusing**, with the same code `init`
  uses.

- **A reading order that is not written all the way through is never `reviewed`**,
  wherever the marker sits. Without that, starting over on a quiet branch landed
  on the same tip as the marker, and the blank skeleton you had just asked for was
  filed away as finished.

## [0.6.0] — 2026-08-11

### Added

- **`git review walkthrough draft` — a reading order for a PR that came without
  one.** The reviewer writes their own in the gitdir, outside the versioned tree,
  and the review reads it as if it were the author's. Three things matter: it
  **never touches your working tree** (`git status` does not change at any point,
  so `finish` cannot carry it into `review-fixes/`), the product does **not** fill
  the draft in or talk to any service, and a draft takes **precedence** over the
  author's walkthrough while it exists.

- **`git review forget --draft (<branch> | --all) [--dry-run]`**, and with it
  `forget` grows to three modes. `clean` used to prune every draft with no live
  `review/<src>` — including the one written in the first step of the documented
  flow (`draft` → fill it in → `--build` → `start`), where there is no review yet.
  `clean` now touches drafts in no namespace at all, and `forget` is what discards
  them: the same division that already governed `--delta` markers and saved
  reviews.

- **An optional authoring guide** that `init` and `draft` point at when it exists.

### Fixed

- **An empty draft no longer covers the author's walkthrough in silence.** "In
  force" and "the file exists" are two different questions, and there is now one
  function for each.
- **`git review continue` refuses** rather than overwriting a draft written while
  the review was paused.
- **Editing your own draft with the review open re-seats the cursor with a note**,
  instead of accusing `HEAD` of having moved.
- **`forget --draft` validates that its argument is a branch name.** Before this,
  `../../x` deleted any `.md` on disk.
- `list` marks `(draft)` on `step` and `whole` rows too, and `forget --saved` says
  it took the draft with it.

## [0.4.0] — 2026-08-07

### Fixed

- **Walk stopped costing a process per entry.** Four functions spawned an `awk`
  plus one or two `grep` for **every entry** of the reading order; each is now a
  single `awk`. The symptom that exposed it was not "the CLI is slow" — it was the
  VS Code panel timing out on every refresh, because `status --porcelain` is what
  it re-invokes and it was going past its 15 s ceiling. On Windows, where `fork()`
  is emulated, a 200-entry reading order went from **28.4 s to 2.4 s** end to end;
  `walkthrough build` went from 16.9 s to 2.2 s. Large PRs and the editor panels
  are what this is for.

## [0.2.1] — 2026-08-02

### Fixed

Four ways a path written in `.review/walkthrough.md` could stop being byte-equal
to the path git reports. Each failed **invisibly**: the entry simply vanished from
the reading order, or `build` reported the same file as both missing and extra. In
every case, `git review walkthrough build` heals an affected sidecar in place.

- **CRLF line endings.** A walkthrough committed with CRLF broke walk mode
  entirely for reviewers on Linux and macOS — `start` degraded to a whole review
  ("none of its entries apply to this review range"). It is invisible from
  Windows, where the bundled `gawk` reads in text mode and eats the CR, so a
  Windows author would ship a broken walkthrough without ever seeing it and every
  Linux/macOS reviewer silently lost the feature. If you hit this and blamed your
  walkthrough, it was the tool.
- **Non-ASCII paths.** git's default `core.quotePath` reported `src/café.js` as
  `"src/caf\303\251.js"`, so `init` wrote that escaped form into the skeleton and a
  literal path drifted against it. This one hides from anyone whose repository is
  ASCII-only, so it hit every Spanish, French and CJK codebase and nobody else.
- **A UTF-8 BOM**, which hid the `# Walkthrough` heading from the preamble reader
  — baking a duplicate heading into the file permanently — or hid the first entry
  outright.
- **Trailing whitespace** after a path in `## N. <path>`: one invisible space
  dropped the entry. `build` now also refuses an entry heading that is not in the
  exact `## N. <path>` form, instead of blaming the PR for drift.

Every surface that *prints* a path now does so unquoted as well — the `--step`
diffstat and both `git review preview` outputs were still showing
`"src/caf\303\251.js"`.

### Changed

- **`walkthrough build` preserves everything above the first entry.** It used to
  discard it; `start` and `compare` now print it as the heads-up. This applies to
  walkthroughs already committed, with no rebuild, because `start` reads the raw
  file from the tip — so free-form prose an author left above the first entry was
  invisible in the tool and becomes the first thing the reviewer sees.
