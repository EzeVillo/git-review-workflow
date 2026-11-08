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

## [0.10.7] — 2026-11-08

### Changed

- Add opt-in `save --porcelain` with the final panel inventory and configuration. Share report renderers and fresh metadata within the reply; preserve human output without the flag and successful saves if only reporting fails.

## [0.10.6] — 2026-11-07

### Changed

- Transfer comments custody in Save/Continue without rebuilding the complete
  comments reading state. Publish one sibling manifest candidate after fresh
  custody and revision checks.

### Fixed

- Recheck both transfer endpoints after preparing the manifest, reject a
  changed session, and preserve the original manifest and recovery candidate
  when concurrent metadata, document bytes or publication prevent transfer.

## [0.10.5] — 2026-11-07

### Changed

- Batch metadata reads during Save and Cancel, validating the displayed context
  inside the operation. Reload custody metadata after locking and before
  transferring or discarding comments, preserving concurrent ownership checks.

## [0.10.4] — 2026-11-07

### Changed

- Include the current walk entry's explanation in porcelain navigation replies,
  using the same walkthrough scan as the entry inventory. Older clients can
  ignore these optional records; ordinary status output is unchanged.

## [0.10.3] — 2026-11-07

### Added

- Return the complete updated review status from `next --porcelain` and
  `prev --porcelain`, including the context guard and typed boundary notices.
  Advertise support through `capability navigation-state` in active status.

### Fixed

- Restore compatibility with macOS's Bash 3.2 POSIX parser in context guards.
- Validate guarded navigation using the operation's own metadata snapshot and
  reuse its sequence when producing the reply.

## [0.10.2] — 2026-11-06

### Added

- Publish an opaque context guard in active review status reports and accept
  `--expect-state <token>` before a command. Reject changed review contexts
  before executing the command, without requiring a full status preflight.

## [0.10.1] — 2026-11-04

### Changed

- Reduce Git process creation during review status, inventory, comments queries
  and cursor navigation, especially on Windows. Read branch metadata once per
  query and reuse the normalized walkthrough and range within each command.

## [0.10.0] — 2026-10-18

### Fixed

- Preserve CRLF and mixed line endings when renumbering, deleting, or rebinding
  comments on Windows, and keep the shared library readable by macOS Bash 3.2.
- Require the existing context choice when a known portable discussion appears
  under a different branch with incompatible history. Choosing a new discussion
  preserves incoming Shared prose while separating private Local notes.
- Accept Git-enabled LF/CRLF checkout conversion when checking the incoming
  Shared delivery baseline, preserving exact prose and final-newline checks
  without executing content filters.
- Report repository Shared with unresolved Git merge entries as unreadable;
  refuse entry and historical-diff queries until the conflict is resolved.
- Pin the Shared destination revision before baseline comparison so an editor
  write during that comparison cannot become the overwrite guard.
- Stage the exact prepared Shared blob and verify delivery before releasing its
  private preparation. Concurrent editor or index changes remain recoverable.
- Keep saved Local visible beside repository Shared when their contexts match,
  without falling back to an older retained Local result or changing custody.
- Read Shared from the checked-out branch outside reviews, including fresh
  clones; repository Shared takes precedence over saved preparations. Prepare
  new reviews from branch prose and exclude inherited contexts. Release the
  editable private Shared after successful delivery; preserve deletions across
  Save/Continue, Finish/Undo/Finish and Finish/Undo/Cancel.
- Restrict compare comment capture to Local and expose allowed destinations
  per operation through `comments status --porcelain`. Preserve comparison
  notes automatically when closing or cleaning the session.
- Clean CRLF checkouts keep reproducible comment locations and range validation.
- Shared delivery is staged with the code edits, including comment-only Finish
  and Prepare retries; concurrent index entries are preserved.
- Ambiguous comment contexts include review dates, document counts and the
  last reviewed subject so separate reviews of one branch can be distinguished.
- Comments use Start's resolved full base, preserving it throughout the session.
  A stale local base no longer makes a remote review of a new branch adopt the
  merged PR's comments context.
- Finishing after deliberately accepting incoming Shared clears the resolved
  source conflict, including when no new Shared delivery is needed.

### Added

- `comments delete --entry <ordinal>` removes one entry with revision guards,
  preserving the other entries and their numbers, metadata and exact bytes.
- Exact comment selections with optional `--start-column` / `--end-column`,
  UTF-16 endpoints and column records in entries and historical diff recipes.
- Full comment bodies and explicit scopes in `comments entries --porcelain`, with
  byte revision checks before returning the selector snapshot.
- Delete individual retained documents after Finish without removing delivered
  `.review/comments.md`; deleted pending Shared delivery is dismissed.


- **Portable review comments.** `git review comments` captures observations in
  independent Local and Shared Markdown documents. Choose the document for each
  capture; use text, stdin or your Git editor, with an optional file, side and
  line range. Local stays in Git's private storage. A changed Shared document is
  prepared as `.review/comments.md` after finish, without staging, committing or
  pushing it. Whole, walk and step reviews preserve both documents through
  navigation, pause, continuation and finish undo.
- **Editing, saved results and historical code.** `status`, `init`, `add`,
  `renumber`, `entries`, `diff`, `save` and `prepare` provide guarded porcelain
  interfaces as well as terminal output. Renumber changes only entry digits and
  preserves Markdown bytes. Compare can checkpoint both documents without
  extracting code. Historical diffs use the captured objects and literal paths;
  missing objects produce a diagnostic without fetching or substituting HEAD.
- **Recoverable Shared delivery.** Concurrent destination changes and I/O errors
  retain the prepared document and report a partial result after code extraction.
  Inspect baseline, prepared and destination with `prepare --check`, resolve
  the prose and retry without repeating the code extraction.

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

- Restrict compare comment capture to Local and expose allowed destinations
  per operation through `comments status --porcelain`. Preserve comparison
  notes automatically when closing or cleaning the session.
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

- Restrict compare comment capture to Local and expose allowed destinations
  per operation through `comments status --porcelain`. Preserve comparison
  notes automatically when closing or cleaning the session.
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

- Restrict compare comment capture to Local and expose allowed destinations
  per operation through `comments status --porcelain`. Preserve comparison
  notes automatically when closing or cleaning the session.
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

- Restrict compare comment capture to Local and expose allowed destinations
  per operation through `comments status --porcelain`. Preserve comparison
  notes automatically when closing or cleaning the session.
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
