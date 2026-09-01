# TUI Release Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the terminal client release-safe by wiring every enabled control and making state reads, watcher updates, finish outcomes, version probing, and preview invocation reliable.

**Architecture:** The UI owns read generations and rejects stale `readDoneMsg` values. The composition root owns watcher lifecycle and receives accepted read summaries through a callback so it can incrementally rebuild draft roots. Host keeps process execution policies, adding a logged interactive review command and an evidence-based version probe.

**Tech Stack:** Go 1.25, Bubble Tea, fsnotify, Go unit tests, Bats, Node product-surface checker.

## Global Constraints

- Review state and draft roots come only from `git review ... --porcelain`.
- Keep raw paths as identifiers; pass only display/report paths to editor commands.
- Every behavior change follows red-green TDD and keeps the mutation lock/confirmation model intact.
- The default runtime enables the real watcher; deterministic tests may explicitly request the no-op watcher.
- Do not move non-review state derivation into direct Git commands.

---

### Task 1: Establish compatible test baseline and read ordering

**Files:**
- Modify: `tui/module_boundary_test.go`, `tui/internal/ui/program.go`, `tui/internal/ui/program_test.go`

**Interfaces:**
- Produces: `readDoneMsg{generation int, result host.ReadResult}` and model read-generation state.

- [ ] **Step 1: Write failing tests**

```go
func TestOlderReadResultCannotOverwriteNewerState(t *testing.T) {
    m := NewModel()
    newer, _ := m.scheduleRead()
    got, _ := newer.Update(readDoneMsg{generation: newer.readGeneration, result: readResult(domain.SituationReview)})
    stale, _ := got.(Model).Update(readDoneMsg{generation: newer.readGeneration - 1, result: readResult(domain.SituationNoReview)})
    if stale.(Model).Panel.Situation != domain.SituationReview { t.Fatal("stale read repainted panel") }
}
```

- [ ] **Step 2: Run the focused test and observe the stale result is accepted.**

Run: `go test ./internal/ui -run TestOlderReadResultCannotOverwriteNewerState -count=1`

- [ ] **Step 3: Implement the minimal generation check and update the module-boundary parser to parse both valid `go.mod` require formats.**

```go
type readDoneMsg struct { generation int; result host.ReadResult }
// scheduleRead increments generation and readDoneMsg is applied only if its generation matches the latest requested read.
```

- [ ] **Step 4: Run the focused and root module tests.**

Run: `go test . ./internal/ui -count=1`

### Task 2: Wire all enabled TUI controls to real effects

**Files:**
- Modify: `tui/internal/ui/mutation.go`, `tui/internal/ui/*_test.go`, `tui/internal/domain/actions.go` if required for argument construction, `tui/internal/host/open.go`, `tui/internal/host/open_test.go`

**Interfaces:**
- Consumes: the current `PanelModel` and raw row variants.
- Produces: activation routes for `installCli`, `showWhy`, `outOfRangeHelp`, `startFromDraft`, `openDraft`, `openWalkthrough`, `copyWalkthroughPrompt`, `openGuide`, and `openSupport`.

- [ ] **Step 1: Write focused activation tests that assert each control opens an overlay, starts the correct mutation, copies the documented prompt, or returns a real delegated command.**

```go
func TestStartFromDraftActivationBuildsStartArgs(t *testing.T) {
    m := Model{Panel: draftPanel("feature", "main..feature")}
    got, cmd := m.activateControl("startFromDraft", "feature")
    if cmd == nil || got.lock.Busy() == false { t.Fatal("start-from-draft did not dispatch") }
}
func TestShowWhyActivationShowsWhyResult(t *testing.T) {
    m := Model{Panel: walkPanel("src/a.go")}
    got, cmd := m.activateControl("showWhy", "src/a.go")
    if cmd == nil || got.textOverlay != nil { t.Fatal("why did not request its result") }
}
func TestOpenSupportActivationBuildsVariantURL(t *testing.T) {
    _, cmd := Model{}.activateControl("openSupport", "bug")
    if cmd == nil { t.Fatal("report-bug control was inert") }
}
```

- [ ] **Step 2: Run each focused test and observe its current no-op or missing route.**

Run: `go test ./internal/ui -run 'Test(StartFromDraftActivation|ShowWhyActivation|OpenSupportActivation)' -count=1`

- [ ] **Step 3: Add the smallest handlers that reuse existing assistant, mutation, text-overlay, OSC 52, and `tea.ExecProcess` paths.**

- [ ] **Step 4: Run UI and host tests.**

Run: `go test ./internal/ui ./internal/host -count=1`

### Task 3: Enable and rebuild the watcher from accepted porcelain reads

**Files:**
- Modify: `tui/cmd/git-review-ui/main.go`, `tui/cmd/git-review-ui/main_test.go`, `tui/internal/host/watch.go`, `tui/internal/host/watch_test.go`

**Interfaces:**
- Consumes: `host.ReadResult` with status/config draft paths.
- Produces: default real watcher, explicit no-op override, and `Watcher.Rebuild(gitDir, gitCommonDir, draftPaths)` after accepted state updates.

- [ ] **Step 1: Write failing composition tests for default watcher selection and rebuilding after a later read reports a new draft root.**

```go
func TestWatcherDefaultsToFsnotify(t *testing.T) {
    t.Setenv("GIT_REVIEW_UI_WATCH", "")
    if kind := watcherKindFromEnv(); kind != watcherFsnotify { t.Fatalf("kind = %v", kind) }
}
func TestForwardWatchTicksRebuildsForNewDraftPath(t *testing.T) {
    w := &recordingWatcher{}
    result := host.ReadResult{HasConfig: true, Config: domain.ConfigResult{Drafts: []domain.DraftRecord{{Path: "C:/drafts/feat.md"}}}}
    rebuildWatcher(w, gitDirs, result)
    if got := w.rebuildPaths; !slices.Contains(got, "C:/drafts/feat.md") { t.Fatalf("paths = %v", got) }
}
```

- [ ] **Step 2: Run the tests and observe default no-op selection / no rebuild call.**

Run: `go test ./cmd/git-review-ui -run 'TestWatcherDefaultsToFsnotify|TestForwardWatchTicksRebuildsForNewDraftPath' -count=1`

- [ ] **Step 3: Pass accepted read summaries to the watcher loop, derive draft paths only from porcelain result fields, and rebuild incrementally.**

- [ ] **Step 4: Run command and watcher tests.**

Run: `go test ./cmd/git-review-ui ./internal/host -count=1`

### Task 4: Correlate finish outcome and harden version probes

**Files:**
- Modify: `tui/internal/ui/program.go`, `tui/internal/ui/mutation.go`, `tui/internal/ui/mutation_test.go`, `tui/internal/domain/situation.go`, `tui/internal/domain/situation_test.go`, `tui/internal/host/versionprobe.go`, `tui/internal/host/versionprobe_test.go`

**Interfaces:**
- Produces: pending-finish matching by source branch and version outcomes that distinguish missing executable from unknown/transient failure.

- [ ] **Step 1: Write failing tests for another review's pending record, blank successful version output, and generic failure classification/retry.**

```go
func TestFinishOutcomeIgnoresPendingForAnotherSource(t *testing.T) {
    m := Model{pendingFinish: &pendingFinishOutcome{source: "feat-a"}}
    got, _ := m.Update(readDoneMsg{generation: 0, result: finishPendingRead("feat-b")})
    if !strings.Contains(got.(Model).statusLine, domain.FinishReadySuffix) { t.Fatal("other pending suppressed feat-a outcome") }
}
func TestBlankVersionIsOutdated(t *testing.T) {
    situation, ok := SituationFromVersionProbe(VersionProbeOutcome{Version: ""}, MinCLIVersion)
    if ok || situation != SituationCliOutdated { t.Fatalf("situation = %q ok=%v", situation, ok) }
}
```

- [ ] **Step 2: Run the tests and observe global pending and blank version are wrongly accepted.**

Run: `go test ./internal/ui ./internal/domain ./internal/host -run 'TestFinishOutcomeIgnoresPendingForAnotherSource|TestBlankVersionIsOutdated' -count=1`

- [ ] **Step 3: Match finish records on source and add evidence-based missing-command classification with bounded retry.**

- [ ] **Step 4: Run domain, host, and UI tests.**

Run: `go test ./internal/domain ./internal/host ./internal/ui -count=1`

### Task 5: Centralize interactive preview policy and verify release surface

**Files:**
- Modify: `tui/internal/host/invoke.go`, `tui/internal/host/open.go`, `tui/internal/host/invoke_test.go`, `tui/internal/host/open_test.go`, `tui/internal/ui/mutation.go`

**Interfaces:**
- Produces: an interactive `git review` command builder that applies the same environment and invocation logging policy as `InvokeReview` without capturing or timing out its terminal session.

- [ ] **Step 1: Write failing host tests that inspect preview environment and invocation log after the interactive command is constructed/executed through its shared policy.**

```go
func TestInteractivePreviewUsesReviewEnvironment(t *testing.T) {
    cmd := InteractiveReviewCmd("preview", nil, ".")
    if !slices.Contains(cmd.Env, "GIT_REVIEW_ADVICE=0") { t.Fatal("interactive preview omitted review environment") }
}
func TestInteractivePreviewIsLogged(t *testing.T) {
    ResetInvocationLogForTest()
    cmd := InteractiveReviewCmd("preview", nil, ".")
    _ = recordInteractiveStart(cmd)
    if len(InvocationLog()) != 1 { t.Fatal("interactive preview was not logged") }
}
```

- [ ] **Step 2: Run the focused host tests and observe direct `exec.Command` bypasses policy.**

Run: `go test ./internal/host -run 'TestInteractivePreview(UsesReviewEnvironment|IsLogged)' -count=1`

- [ ] **Step 3: Implement the interactive invoker and replace `PreviewEditsCmd`'s parallel construction path.**

- [ ] **Step 4: Run the full release verification.**

Run: `go test ./... -count=1 && go vet ./... && gofmt -l . && bats tests/ui.bats && node scripts/check-client-product-surface.mjs`
