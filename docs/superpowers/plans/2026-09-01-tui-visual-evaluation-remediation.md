# TUI Visual Evaluation Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every P1/P2 finding from the 2026-08-31 Linux visual evaluation without replacing the TUI's existing state renderers.

**Architecture:** Preserve the current per-situation render functions and add a narrow presentation layer for control state and clipped regions. The panel footer and action palette each own one visible range; keyboard focus, mouse hover/clicks, and the rendered HitMap derive from that exact range. The host recognises a pending finish from either porcelain record shape emitted by the CLI.

**Tech Stack:** Go 1.25, Bubble Tea, Lipgloss, the real `git review` dispatcher, golden-frame tests.

## Global Constraints

- Keep `internal/domain` pure: no Bubble Tea or process imports.
- Preserve the CLI as the source of truth; `ReadState` only derives from porcelain responses.
- Keep `j`/`k` and arrows as the only panel focus keys; `n`/`p` remain review-cursor-only.
- Match the other three clients' start-branch ordering: current candidate first, then ordinal branch name.
- Keep the existing state-specific renderer functions; do not introduce a general layout engine.
- Every behavior change starts with a failing Go test and is formatted with `gofmt`.

---

### Task 1: Derive real finish-pending from CLI output

**Files:**
- Modify: `tui/internal/host/statecycle.go`
- Modify: `tui/internal/host/statecycle_test.go`

**Interfaces:**
- Consumes: `domain.ParseListPorcelain` and `domain.ParseListFixes` results from `git review list --porcelain`.
- Produces: `ReadResult{Situation: domain.SituationFinishPending}` whenever any `review/*` porcelain branch has `finish.state == pending`; this is repository state, not a property of HEAD.

- [x] **Step 1: Write the failing integration test**

Add a test that creates `sandboxWithOrigin`, starts a review, edits a tracked file, runs `git review finish`, and calls `ReadState` from the resulting `review-fixes/feature/x` branch. Assert `SituationFinishPending`, `HasList`, and a projected `PanelModel` whose destination is `review-fixes/feature/x`.

- [x] **Step 2: Run the test to verify it fails**

Run: `cd tui; go test ./internal/host -run TestReadStateRecognizesPendingFinishFromCurrentFixesRecord -count=1`

Expected: FAIL because `ReadState` only inspects current `branch` records.

- [x] **Step 3: Implement the minimal host derivation**

Add `domain.PendingFinish`, which finds the `finish.state == pending` record directly from `list --porcelain`. Use it only in the existing exit-2 list branch and in `domain.Project`.

- [x] **Step 4: Run the host package tests**

Run: `cd tui; go test ./internal/host -count=1`

Expected: PASS.

### Task 2: Make panel focus and footer visibility agree

**Files:**
- Modify: `tui/internal/ui/program.go`
- Modify: `tui/internal/ui/render.go`
- Modify: `tui/internal/ui/controls.go`
- Modify: `tui/internal/ui/reachability_keyboard_test.go`
- Modify: `tui/internal/ui/reachability_mouse_test.go`
- Modify: `tui/internal/ui/render_test.go`

**Interfaces:**
- Consumes: `Model.FocusIndex`, an optional hover control, `ControlsFor`, and the full footer render interval.
- Produces: a focus-aware `ViewModel`/render call with a footer offset; every visible control appears in the HitMap at its displayed coordinate.

- [x] **Step 1: Write failing focus and viewport tests**

Add tests that (a) render a no-review panel, move focus with `j`, and require a different visible frame with the focused control marked; (b) move focus through a 80x24 footer until the final Support control is visible and activatable; and (c) use a real mouse wheel event and require the same footer range to move and expose a newly clickable control.

- [x] **Step 2: Run the focused UI tests to verify they fail**

Run: `cd tui; go test ./internal/ui -run 'Test(FocusMovementChangesRenderedControl|FooterFocusScrollsIntoView|FooterMouseWheelScrollsSharedViewport)$' -count=1`

Expected: FAIL because the frame ignores `FocusIndex`, `capFooter` drops the tail, and wheel events are inert.

- [x] **Step 3: Implement the narrow presentation state**

Add footer offset and hover state to `Model`. Pass a small render-state value into the panel renderer; the existing situation renderer functions remain unchanged. Replace `capFooter` with a single visible footer window that retains the head and key bar, projects HitMap rows into the visible window, and marks the focused or hovered control. On focus moves, calculate the focused control's row and move only this footer offset enough to reveal it; on mouse wheel, clamp and move that same offset. A mouse press still activates through the existing control path.

- [x] **Step 4: Run the UI package tests**

Run: `cd tui; go test ./internal/ui -count=1`

Expected: PASS.

### Task 3: Keep the action-palette help visible

**Files:**
- Modify: `tui/internal/ui/palette.go`
- Modify: `tui/internal/ui/palette_test.go`

**Interfaces:**
- Consumes: `ActionList.Cursor`, filtered palette items, viewport dimensions.
- Produces: a palette list window whose selected item is visible while the title, filter, and key help remain visible.

- [x] **Step 1: Write a failing small-viewport test**

Create a 80x24 palette with all no-review actions, move its cursor to the last action, and assert that the rendered frame contains both that action and `up/down:move`, while the first action is no longer required to be present.

- [x] **Step 2: Run the test to verify it fails**

Run: `cd tui; go test ./internal/ui -run TestActionPaletteScrollKeepsHelpVisibleAt80x24 -count=1`

Expected: FAIL because `capOverlay` cuts off the help row.

- [x] **Step 3: Implement the list-only window**

Compute the available list rows after the palette header and help, clamp an item offset around `Cursor`, and render only that slice. Do not change filtering, key dispatch, or activation semantics.

- [x] **Step 4: Run palette tests**

Run: `cd tui; go test ./internal/ui -run 'TestActionList|TestActionPalette' -count=1`

Expected: PASS.

### Task 4: Align branch selection with the three desktop clients

**Files:**
- Modify: `tui/internal/domain/porcelain.go`
- Modify: `tui/internal/domain/porcelain_test.go`

**Interfaces:**
- Consumes: `[]CandidateBranch` from config porcelain.
- Produces: one candidate per name, preferring `Current`, sorted by `Current` descending and `Name` ordinal ascending.

- [x] **Step 1: Write a failing parity test**

Use unsorted current and non-current candidate rows, including duplicate local/remote names. Assert the result is one current candidate first, followed by non-current names in ordinal order, matching `branchPickerItems` / `BranchPickerItems` in VS Code, JetBrains, and Visual Studio.

- [x] **Step 2: Run the test to verify it fails**

Run: `cd tui; go test ./internal/domain -run TestBranchPickerItemsOrdersCurrentThenName -count=1`

Expected: FAIL because TUI preserves porcelain arrival order.

- [x] **Step 3: Implement the deterministic ordering**

Keep duplicate collapse and current-record preference, then sort the result with current first and `Name` ascending.

- [x] **Step 4: Run domain tests**

Run: `cd tui; go test ./internal/domain -count=1`

Expected: PASS.

### Task 5: Update golden evidence and verify the complete module

**Files:**
- Modify: `tui/testdata/golden/*.txt` only where focus/scroll rendering intentionally changes a recorded frame.
- Modify: `specs/015-cliente-tui/tasks.md` only if it tracks this evaluation's completion state.

**Interfaces:**
- Consumes: updated UI behavior and the existing golden-update test mode.
- Produces: reviewed, minimal golden deltas and all TUI quality gates green.

- [x] **Step 1: Regenerate only intentional golden changes**

Run: `cd tui; go test -tags goldenupdate ./internal/ui -update`

Inspect: `git diff -- tui/testdata/golden`

- [x] **Step 2: Run the complete quality gate**

Run: `cd tui; gofmt -w internal; gofmt -l .; go vet ./...; go test ./...; go build ./cmd/git-review-ui`

Expected: `gofmt -l .` has no output and every command exits 0.

- [x] **Step 3: Verify repository-level contract parity**

Run: `node scripts/check-client-product-surface.mjs`

Expected: PASS.
