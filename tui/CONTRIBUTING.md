# Contributing to the terminal TUI

This covers working *on* the TUI. For what it does and how to use it, see the
[README](../README.md#tui) (once written) and the [project README](../README.md) and
[CONTRIBUTING.md](../CONTRIBUTING.md) at the root; for the design, see
[`../specs/015-cliente-tui/`](../specs/015-cliente-tui/), especially
[`plan.md`](../specs/015-cliente-tui/plan.md) and
[`contracts/tui-surface.md`](../specs/015-cliente-tui/contracts/tui-surface.md).

## The CLI is the only source of truth

Same rule as the other three clients: the TUI never derives review state on its own. Everything it
shows comes from re-invoking `git review status --porcelain` / `--why` / `list --porcelain` /
`config --porcelain` and reading the result. If the panel needs something the CLI does not report,
it gets added to the CLI — never computed here.

The canonical multi-client strings, action matrix and panel layout live in
[`../contracts/client-product-surface.yaml`](../contracts/client-product-surface.yaml);
`tui/internal/domain/layout_contract_test.go` checks this client against it on every `go test`.

> The rest of this document — build, test, how the golden files are regenerated and reviewed, the
> watcher's total-shutoff lever, the `reviewui.*` config keys, and the release runbook — lands
> alongside packaging in a later pass. What follows is the one piece that ships now: the manual smoke
> matrix a release walks through, matching
> [`../specs/015-cliente-tui/quickstart.md`](../specs/015-cliente-tui/quickstart.md) § Matriz smoke.

## Smoke matrix (before a release)

Eight cases, run by hand on Windows, macOS and Linux (a real terminal each time — not this repo's
own `go test`, which runs everything with the watcher off and no real TTY). None of these are
optional: each one is a failure mode that only shows up outside the golden files and the unit suite,
either because it depends on a real terminal, a real network, or an environment this repo's CI
cannot reproduce (an old CLI on `PATH`, a non-ASCII filesystem path, a real SSH credential prompt).

| # | Case | OK if | Covered by an automated test? |
|---|---|---|---|
| 1 | `git review ui` with an old CLI on `PATH` | situation `cli-outdated`, never `cli-missing` | Yes — `tui/internal/domain/situation_test.go` (the version-probe cases) and `tui/internal/host/versionprobe_test.go` cover the derivation; this row is the end-to-end confirmation with a real old binary |
| 2 | an accented, space-containing path inside the reviewed range | lists correctly and opens correctly | Partially — `tui/internal/domain/pathref_test.go` covers the raw/display split; this row is the end-to-end confirmation through a real `$EDITOR`/difftool |
| 3 | `start --offline` from the start assistant | review becomes active | Partially — `tui/internal/domain/intent_test.go` covers the assistant's own argv; this row confirms the CLI actually accepts it end to end |
| 4 | a network verb whose credentials would prompt (no cached credentials, no agent) | fails with a diagnostic, **never hangs the pane** | Yes, at the mechanism level — `tui/internal/host/askpass_test.go` (T041) proves the askpass sentinel exits non-zero and silent, without ever touching the terminal; this row is the one confirmation that a REAL `git fetch` under `GIT_TERMINAL_PROMPT=0` actually takes that path instead of blocking on stdin |
| 5 | a linked worktree | the two guides come from the common gitdir; the draft comes from the worktree's own gitdir | Yes — `tui/internal/host/gitdata_test.go` and the linked-worktree cases in `tui/internal/host/watch_fsnotify_test.go` (T059); this row is the manual confirmation in a real terminal |
| 6 | Windows: `git review ui` after installing the TUI via `web-install.ps1 -WithUi` | starts | No — this is an installer/packaging path with nothing to unit-test under `go test` |
| 7 | a repository with the `reftable` ref backend | starts and refreshes | Yes — `tui/internal/host/watch_fsnotify_test.go`'s `reftable` case (T058); this row is the manual confirmation outside the watcher-focused test |
| 8 | `cwd` outside any git repository | an actionable error situation (the `no_single_root` copy), never a blank screen | Yes — `tui/internal/host/statecycle_test.go`'s `TestReadStateOutsideARepositoryIsError` (T100) |
