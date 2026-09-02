# TUI Unified Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every asynchronous TUI read, wizard probe, mutation, and delegated action visible, non-clippable feedback consistent with the three editor clients.

**Architecture:** Add one generated presentation activity to the Bubble Tea model while retaining `MutationLock` as the only concurrency authority. Render the last truthful panel with disabled controls and a delayed fixed progress/status tail; use an immediate progress overlay for Start assistant probes. Correlate command results and delayed timers by generation, then use the existing authoritative read cycle to resolve final panel state.

**Tech Stack:** Go 1.23, Bubble Tea, Lip Gloss, existing `internal/domain`, `internal/host`, and `internal/ui` packages.

## Global Constraints

- Work directly on `main`; do not create a worktree.
- Use TDD for every behavior change.
- The loading threshold is exactly 120 ms, matching the editor panels.
- `MutationLock` remains the only concurrency mechanism.
- Do not add polling, progress percentages, porcelain formats, confirmations, dependencies, an editor, or a diff viewer.
- Product-facing text lives in `tui/internal/domain/usercopy.go`; argv remains visible only in Show CLI Log.
- Preserve the 55% tools-footer cap and one shared footer scrollbar.
- Errors, acknowledgements, and the key bar must remain visible at 80x24 and 120x40.

---

## File structure

- Create `tui/internal/ui/activity.go`: generated activity state, 120 ms visibility message, progress overlay, and effective presentation panel.
- Create `tui/internal/ui/activity_test.go`: timer generation, immediate busy, delayed visibility, and overlay behavior.
- Modify `tui/internal/domain/usercopy.go`: progress and guide-created copy.
- Modify `tui/internal/domain/usercopy_test.go`: exact progress-copy coverage.
- Modify `tui/internal/ui/program.go`: activity fields, message routing, read lifecycle, and rendering through the effective panel.
- Modify `tui/internal/ui/render.go`: fixed non-clippable tail and hit-map clipping.
- Modify `tui/internal/ui/render_test.go`: fixed-tail regression at reference sizes.
- Modify `tui/internal/ui/controls.go` and `tui/internal/ui/keys.go`: disable stale controls and mutation/navigation keys while busy.
- Modify `tui/internal/ui/assistant.go`, `select.go`, and assistant tests: immediate progress overlay between Start questions.
- Modify `tui/internal/ui/mutation.go` and mutation/control tests: mutation activity correlation, Continue interpolation, Create Guide refresh-then-open, and immediate delegated failures.
- Modify `tui/internal/ui/palette.go` only if needed to keep Show CLI Log reachable during activity through the existing canonical `RequiresNotBusy` gate.
- Modify `tui/testdata/golden/*` only if intentional fixed-tail changes alter existing reference frames; regenerate locally and inspect every changed frame.

---

### Task 1: Activity state and product copy

**Files:**
- Create: `tui/internal/ui/activity.go`
- Create: `tui/internal/ui/activity_test.go`
- Modify: `tui/internal/domain/usercopy.go`
- Modify: `tui/internal/domain/usercopy_test.go`
- Modify: `tui/internal/ui/program.go`

**Interfaces:**
- Produces: `activityPhase`, `activityState`, `activityVisibleMsg`, `activityDelay`, `Model.startActivity`, `Model.clearActivity`, `Model.presentationPanel`, and `ProgressOverlay`.
- Produces: `domain.ProgressText(action string, params domain.ActionParams) string`, `domain.ReadOptionsProgress`, and `domain.GuideCreated(path string) string`.
- Consumes: existing `Model.statusLine`, `PanelModel.Busy`, and `domain.ActionParams`.

- [ ] **Step 1: Write failing activity and copy tests**

```go
func TestActivityIsBusyImmediatelyButVisibleOnlyAfterThreshold(t *testing.T) {
    m, cmd := (Model{Panel: domain.PanelModel{Situation: domain.SituationNoReview}}).
        startActivity(activityMutation, "Starting the review of feature/x…", true)
    if !m.presentationPanel().Busy { t.Fatal("activity must disable controls immediately") }
    if m.presentationPanel().StatusLine != "" { t.Fatal("fast activity must not flash") }
    msg := cmd()
    shown, _ := m.Update(msg)
    if got := shown.(Model).presentationPanel().StatusLine; got != "Starting the review of feature/x…" {
        t.Fatalf("visible progress = %q", got)
    }
}

func TestStaleActivityTimerCannotRevealNewerActivity(t *testing.T) {
    first, _ := (Model{}).startActivity(activityReading, domain.WaitingText, true)
    second, _ := first.startActivity(activityMutation, "Creating the authoring guide…", true)
    got, _ := second.Update(activityVisibleMsg{generation: first.activity.generation})
    if got.(Model).activity.visible { t.Fatal("stale timer revealed a newer activity") }
}

func TestProgressCopyMatchesEditorClients(t *testing.T) {
    if got := ProgressText("startReview", ActionParams{Intent: ReviewIntent{Branch: "feature/x"}}); got != "Starting the review of feature/x…" { t.Fatal(got) }
    if got := ProgressText("continueReview", ActionParams{Source: "feature/x"}); got != "Continuing the review of feature/x…" { t.Fatal(got) }
    if got := ProgressText("createGuide", ActionParams{}); got != "Creating the authoring guide…" { t.Fatal(got) }
}
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run: `cd tui && go test ./internal/ui ./internal/domain -run 'Test(Activity|StaleActivity|ProgressCopy)'`

Expected: FAIL because the activity types and progress-copy functions do not exist.

- [ ] **Step 3: Implement generated activity and copy**

```go
const activityDelay = 120 * time.Millisecond

type activityPhase string
const (
    activityReading activityPhase = "reading"
    activityAssistant activityPhase = "assistant"
    activityMutation activityPhase = "mutation"
    activityDelegated activityPhase = "delegated"
)

type activityState struct {
    generation int
    phase activityPhase
    text string
    active bool
    visible bool
    blocksControls bool
}

type activityVisibleMsg struct{ generation int }

func (m Model) startActivity(phase activityPhase, progress string, blocks bool) (Model, tea.Cmd) {
    m.activityGeneration++
    m.activity = activityState{generation: m.activityGeneration, phase: phase, text: progress, active: true, blocksControls: blocks}
    gen := m.activityGeneration
    return m, tea.Tick(activityDelay, func(time.Time) tea.Msg { return activityVisibleMsg{generation: gen} })
}

func (m Model) presentationPanel() domain.PanelModel {
    panel := m.Panel
    panel.StatusLine = m.statusLine
    if m.activity.active && m.activity.blocksControls { panel.Busy = true }
    if m.activity.active && m.activity.visible { panel.StatusLine = m.activity.text }
    return panel
}
```

Add exact action-specific copy for every mutation action currently routed by `activateControl`/`activateBoundAction`, using the equivalent strings already present in `UserCopy.ts`, `UserCopy.kt`, and `UserCopy.cs`. Unknown internal actions fall back to `Working…`, never to an argv.

- [ ] **Step 4: Route `activityVisibleMsg` and render the effective panel**

In `Model.Update`, reveal only when `msg.generation == m.activity.generation && m.activity.active`. In `View`, `presentationState`, `handleMouse`, and any geometry call, use `m.presentationPanel()` so immediate status and busy state are visible without waiting for a repository read.

- [ ] **Step 5: Run focused tests**

Run: `cd tui && go test ./internal/ui ./internal/domain -run 'Test(Activity|StaleActivity|ProgressCopy)'`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add tui/internal/ui/activity.go tui/internal/ui/activity_test.go tui/internal/ui/program.go tui/internal/domain/usercopy.go tui/internal/domain/usercopy_test.go
git commit -m "feat(tui): model unified operation activity"
```

### Task 2: Fixed status/activity tail and busy controls

**Files:**
- Modify: `tui/internal/ui/render.go`
- Modify: `tui/internal/ui/render_test.go`
- Modify: `tui/internal/ui/controls.go`
- Modify: `tui/internal/ui/keys.go`
- Modify: `tui/internal/ui/keys_test.go`
- Modify: `tui/internal/ui/reachability_keyboard_test.go`
- Modify: `tui/internal/ui/reachability_mouse_test.go`

**Interfaces:**
- Consumes: `PanelModel.Busy` and `PanelModel.StatusLine` from Task 1.
- Produces: fixed tail layout where content is capped before status/keybar append.

- [ ] **Step 1: Write failing fixed-tail tests**

Build a no-review fixture with enough inventory and footer rows to overflow 80x24, set `StatusLine` to `error: you have local changes; commit or stash them first`, and assert both that text and `q:quit` occur in the rendered frame. Repeat at 120x40. Assert `len(strings.Split(stripANSI(frame), "\n")) <= vp.Rows`.

- [ ] **Step 2: Write failing busy-control tests**

```go
func TestBusyPanelDisablesBodyControlsAndCursorKeys(t *testing.T) {
    panel := reviewWalkPanel()
    panel.Busy = true
    for _, c := range ControlsFor(panel) {
        if c.Enabled { t.Fatalf("%s stayed enabled while busy", c.ID) }
    }
    if got := ResolveKey("n", Model{Panel: panel}); got.Kind != IntentNone { t.Fatalf("n resolved while busy: %+v", got) }
}
```

- [ ] **Step 3: Run tests and verify failure**

Run: `cd tui && go test ./internal/ui -run 'Test(FixedTail|BusyPanel)'`

Expected: FAIL because the status is clipped and body controls remain enabled.

- [ ] **Step 4: Refactor rendering into body plus fixed tail**

Stop calling `b.statusLine` and `b.keyBar` as ordinary body append operations. Build wrapped tail lines first: optional status/activity, one separator, and keybar. Cap/wrap the body to `vp.Rows-len(tail)` and append the tail afterward. Remove hit-map entries whose final row is outside the retained body.

Pass the computed tail reserve into `capFooter`; replace `keyBarReserve` with the actual reserve so the 55% footer window and its one scrollbar remain intact.

- [ ] **Step 5: Disable stale interaction while busy**

Refactor `ControlsFor` into a situation builder followed by a busy pass that sets every body control `Enabled=false` when `m.Busy`. Gate cursor and bound mutation intents in `ResolveKey`; keep refresh, action list, mouse toggle, and quit available. Ensure `KeyBarFor` does not advertise disabled mutation/navigation keys.

- [ ] **Step 6: Run UI tests**

Run: `cd tui && go test ./internal/ui -run 'Test(FixedTail|BusyPanel|Keyboard|Mouse|KeyBar|Footer)'`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add tui/internal/ui/render.go tui/internal/ui/render_test.go tui/internal/ui/controls.go tui/internal/ui/keys.go tui/internal/ui/keys_test.go tui/internal/ui/reachability_keyboard_test.go tui/internal/ui/reachability_mouse_test.go
git commit -m "fix(tui): keep feedback visible and controls truthful"
```

### Task 3: Start assistant progress continuity

**Files:**
- Modify: `tui/internal/ui/activity.go`
- Modify: `tui/internal/ui/assistant.go`
- Modify: `tui/internal/ui/select.go`
- Modify: `tui/internal/ui/program.go`
- Modify: `tui/internal/ui/assistant_test.go`

**Interfaces:**
- Consumes: `ProgressOverlay` and activity generations from Task 1.
- Produces: `assistantStepMsg.activityGeneration` and `Model.beginAssistantProbe(progress string, cmd tea.Cmd)`.

- [ ] **Step 1: Write failing assistant continuity tests**

Assert that `startAssistant()` immediately sets a progress overlay containing `Reading the available review options…`. After choosing a branch or range, assert the old picker closes into that progress overlay rather than exposing `Model.Panel`. Assert a stale assistant result cannot close or replace a newer flow.

- [ ] **Step 2: Run and verify failure**

Run: `cd tui && go test ./internal/ui -run 'Test.*Assistant.*(Progress|Stale|Between)'`

Expected: FAIL because config probes currently leave every overlay nil.

- [ ] **Step 3: Correlate probes and keep an overlay visible**

Add `activityGeneration int` to `assistantStepMsg`. `configProbeCmd` receives that generation. `startAssistant` and `selectResult.cmd` probe transitions call `beginAssistantProbe`, which opens `ProgressOverlay{Text: domain.ReadOptionsProgress}` immediately. `handleAssistantStep` ignores stale generations, clears the assistant activity, and opens the next picker or a visible fixed error.

- [ ] **Step 4: Run assistant tests**

Run: `cd tui && go test ./internal/ui -run 'Test.*Assistant'`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tui/internal/ui/activity.go tui/internal/ui/assistant.go tui/internal/ui/select.go tui/internal/ui/program.go tui/internal/ui/assistant_test.go
git commit -m "fix(tui): keep start feedback between questions"
```

### Task 4: Mutation lifecycle, visible failures, and Continue copy

**Files:**
- Modify: `tui/internal/ui/mutation.go`
- Modify: `tui/internal/ui/mutation_test.go`
- Modify: `tui/internal/ui/program.go`
- Modify: `tui/internal/ui/program_test.go`
- Modify: `tui/internal/domain/usercopy.go`

**Interfaces:**
- Consumes: `Model.startActivity`, `ProgressText`, and fixed tail.
- Produces: `mutationDoneMsg.activityGeneration` and a mutation lifecycle that starts busy before spawn and clears only the matching generation.

- [ ] **Step 1: Write failing mutation lifecycle tests**

Assert that accepting Continue immediately yields `Panel.Busy=true`; after 120 ms its rendered frame contains `Continuing the review of feature/search…`; a failure result clears activity and immediately renders the exact stderr. Use a long no-review inventory at 80x24 to prove the stderr is still visible.

Add a regression asserting Continue's detail contains `feature/search` and does not contain `{source}`.

- [ ] **Step 2: Run and verify failure**

Run: `cd tui && go test ./internal/ui -run 'Test(MutationActivity|Continue.*Detail|DirtyTree.*Visible)'`

Expected: FAIL.

- [ ] **Step 3: Start and correlate mutation activity**

After the lock and state-token checks in `beginMutation`, build argv, clear the previous acknowledgement, start `activityMutation` with `domain.ProgressText(req.action, req.params)`, and batch its 120 ms tick with `mutationCmd`. Add the generation to `mutationDoneMsg`; `handleMutationDone` ignores only activity changes from a different generation, clears the matching activity, records failure text, and schedules the authoritative read.

- [ ] **Step 4: Fix Continue interpolation**

Change the detail passed to `ConfirmMutation` to:

```go
detail := interpolate(domain.ContinueReviewConfirmDetail, "{source}", source)
```

- [ ] **Step 5: Run mutation and program tests**

Run: `cd tui && go test ./internal/ui -run 'Test(Mutation|Continue|DirtyTree|Program|StatusLine)'`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add tui/internal/ui/mutation.go tui/internal/ui/mutation_test.go tui/internal/ui/program.go tui/internal/ui/program_test.go tui/internal/domain/usercopy.go
git commit -m "fix(tui): expose mutation progress and failures"
```

### Task 5: Create Guide refresh-then-open and delegated feedback

**Files:**
- Modify: `tui/internal/ui/mutation.go`
- Modify: `tui/internal/ui/program.go`
- Modify: `tui/internal/ui/control_activation_test.go`
- Modify: `tui/internal/ui/mutation_test.go`
- Modify: `tui/internal/host/open_test.go`

**Interfaces:**
- Produces: `mutationRequest.successOpenPath string`, `Model.pendingOpenPath string`, and a post-read `tea.ExecProcess` launch.
- Consumes: porcelain-reported guide paths and `domain.GuideCreated`.

- [ ] **Step 1: Write failing guide and Open feedback tests**

Assert Create Team/Own records the exact corresponding `PanelModel` path before spawning. Simulate successful `mutationDoneMsg`, then accepted `readDoneMsg`, and assert the returned command launches that path when `$EDITOR` exists. With `$EDITOR` empty, assert the rendered fixed status says `Created <path>.` immediately after the accepted read.

For an ordinary Open with `$EDITOR` empty, assert `Model.View()` immediately contains `No editor is configured: set $EDITOR and try again.` without scheduling a refresh.

- [ ] **Step 2: Run and verify failure**

Run: `cd tui && go test ./internal/ui -run 'Test(CreateGuide.*Open|Open.*Visible)'`

Expected: FAIL because Create currently ends after refresh and immediate status is stored outside the rendered panel.

- [ ] **Step 3: Queue the reported guide path through the authoritative read**

Set `successOpenPath` from `TeamGuideRow`/`OwnGuideRow` in `beginCreateGuide`. Carry it in `mutationDoneMsg`; on successful creation store `pendingOpenPath`. In the matching accepted `readDoneMsg`, clear the pending path and call `host.OpenInEditorCmd`. Return `execCmd` when available; otherwise set `statusLine = domain.GuideCreated(path)` and `Panel.StatusLine` in the same update.

- [ ] **Step 4: Make delegated failures immediately renderable**

Rely on `presentationPanel()` for pre-spawn validation failures. Preserve the existing policy that normal editor non-zero exits are not errors; only absence/not-found prevents dispatch and yields copy.

- [ ] **Step 5: Run focused tests**

Run: `cd tui && go test ./internal/ui ./internal/host -run 'Test(CreateGuide|Open|Editor)'`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add tui/internal/ui/mutation.go tui/internal/ui/program.go tui/internal/ui/control_activation_test.go tui/internal/ui/mutation_test.go tui/internal/host/open_test.go
git commit -m "feat(tui): open newly created guides with feedback"
```

### Task 6: Full regression and sandbox acceptance

**Files:**
- Modify if required: `tui/testdata/golden/*.txt`
- Modify if required: `tests/ui.bats`
- Modify: `tui/CHANGELOG.md`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: release evidence across unit, race, static contract, and real sandbox paths.

- [ ] **Step 1: Add or extend the UI integration test**

Exercise a dirty-tree Start/Continue result through the TUI model or existing `tests/ui.bats` harness and assert the stderr is in the visible 80x24 frame. Do not assert only `Model.statusLine`.

- [ ] **Step 2: Run formatting and static checks**

Run:

```bash
cd tui && gofmt -w internal/domain/*.go internal/ui/*.go internal/host/*.go
cd .. && git diff --check
node scripts/check-client-product-surface.mjs
```

Expected: all commands exit 0.

- [ ] **Step 3: Run complete TUI verification**

Run:

```bash
cd tui && go test -count=1 ./...
go test -race ./internal/ui ./internal/host
go vet ./...
```

Expected: all packages PASS and vet prints no diagnostics.

- [ ] **Step 4: Build and reproduce the supplied sandbox flow**

Run the supplied Git Bash sequence with the newly built executable. Verify manually and through the CLI log that:

- Start probes never expose the base panel between questions;
- Continue displays progress after 120 ms;
- the dirty-tree error is visible without opening Show CLI Log;
- Open without `$EDITOR` visibly explains the missing editor;
- with `EDITOR="code --wait"`, Open delegates successfully;
- Create Guide displays progress and opens the created file, or acknowledges its path.

- [ ] **Step 5: Inspect golden changes**

If golden files changed, render both 80x24 and 120x40 in color, no-color, and ASCII modes. Confirm only intended fixed-tail spacing changed. Never accept mass regeneration without inspecting the diff.

- [ ] **Step 6: Update changelog**

Add a concise entry under the current unreleased TUI section describing visible operation progress, non-clippable failures, uninterrupted Start questions, and Create Guide opening its file.

- [ ] **Step 7: Commit release-ready verification changes**

```bash
git add tui tests/ui.bats
git commit -m "test(tui): verify unified operation feedback"
```

- [ ] **Step 8: Final clean-tree evidence**

Run `git status --short`, `git log -6 --oneline`, and the full verification commands again if any file changed after Step 3. Expected: clean worktree and all checks green.
