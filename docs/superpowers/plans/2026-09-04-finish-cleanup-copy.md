# Finish Cleanup Copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every finished-review surface plainly state that the reviewer keeps their edits while removing the option to undo.

**Architecture:** The finish-pending state, `clean --keep-fixes` invocation, controls, and state transitions remain intact. Each client changes only its visible banner, control, and confirmation copy; client-local unit tests assert that exact contract. The TUI regenerates its deterministic finish-pending golden frames.

**Tech Stack:** TypeScript/Mocha, C#/.NET/xUnit, Kotlin/JUnit/Gradle, Go/Bubble Tea.

## Global Constraints

- Banner line 2 is exactly `Commit and push them from Source Control. You can still undo this finish.`
- Primary action and its confirmation accept button are exactly `Keep edits & remove Undo`.
- Secondary action is exactly `Undo Finish`.
- Primary confirmation title is exactly `Keep your edits & remove Undo?`.
- Primary confirmation detail is exactly `Your edits stay on {destination} — commit and push them from Source Control. What goes away is the option to undo this finish.`
- Do not expose `review/<source>` or alter command arguments, state transitions, or layout behavior beyond natural text wrapping.

---

### Task 1: VS Code

**Files:**
- Modify: `vscode-extension/src/views/panelHtml.ts:1366-1375`
- Modify: `vscode-extension/src/review/housekeeping.ts:177-191`
- Test: `vscode-extension/test/unit/panelHtml.spec.ts:544-575`
- Test: `vscode-extension/test/unit/housekeeping.spec.ts:98-146`

**Interfaces:** Uses `renderEmptyState` and `confirmCopyFor`; preserves `cleanReview`, `undoFinish`, and `clean-keep-fixes`.

- [ ] **Step 1: Write failing tests**

```ts
assert.ok(pendingBranch.includes('"Keep edits & remove Undo", "cleanReview"'));
assert.ok(pendingBranch.includes('"Undo Finish", "undoFinish"'));
assert.ok(pendingBranch.includes("You can still undo this finish."));
assert.strictEqual(c.title, "Keep your edits & remove Undo?");
assert.strictEqual(c.button, "Keep edits & remove Undo");
assert.ok(c.detail.includes("What goes away is the option to undo this finish."));
```

- [ ] **Step 2: Verify RED**

Run: `npm run test:unit -- --grep "finish-pending|clean-keep-fixes"`

Expected: fails on the existing `Done, clean up`, `Undo`, and old confirmation text.

- [ ] **Step 3: Implement minimal copy changes**

Replace only the banner, control labels, and `clean-keep-fixes` confirmation literals with the global contract.

- [ ] **Step 4: Verify GREEN**

Run: `npm run test:unit -- --grep "finish-pending|clean-keep-fixes"`

Expected: all focused tests pass.

- [ ] **Step 5: Commit**

```bash
git add vscode-extension/src/views/panelHtml.ts vscode-extension/src/review/housekeeping.ts vscode-extension/test/unit/panelHtml.spec.ts vscode-extension/test/unit/housekeeping.spec.ts
git commit -m "fix(vscode): clarify finish cleanup"
```

### Task 2: Visual Studio

**Files:**
- Modify: `visualstudio-extension/src/GitReview.Domain/PanelLayout.cs:700-714`
- Modify: `visualstudio-extension/src/GitReview.Domain/Housekeeping.cs:126-130`
- Test: `visualstudio-extension/tests/GitReview.Domain.Tests/PanelLayoutFinishTests.cs:8-35`
- Test: `visualstudio-extension/tests/GitReview.Domain.Tests/HousekeepingTests.cs:168-183`

**Interfaces:** Uses `PanelLayoutBuilder.PanelLayout` and `HousekeepingLogic.ConfirmCopyFor`; retains `ControlId.CleanReview`, `ControlId.UndoFinish`, and `--keep-fixes` argv.

- [ ] **Step 1: Write failing tests**

```csharp
Assert.Equal("Keep edits & remove Undo", controls[0].Label);
Assert.Equal("Undo Finish", controls[1].Label);
Assert.Contains("You can still undo this finish.", banner.Paragraphs[1]);
Assert.Equal("Keep your edits & remove Undo?", separate.Title);
Assert.Equal("Keep edits & remove Undo", separate.Button);
```

- [ ] **Step 2: Verify RED**

Run: `dotnet test tests/GitReview.Domain.Tests/GitReview.Domain.Tests.csproj --filter "FullyQualifiedName~PanelLayoutFinishTests|FullyQualifiedName~HousekeepingTests" --no-restore`

Expected: fails on prior labels and copy.

- [ ] **Step 3: Implement minimal copy changes**

Replace only the finish-pending and `CleanKeepFixes` string literals with the global contract.

- [ ] **Step 4: Verify GREEN**

Run: `dotnet test tests/GitReview.Domain.Tests/GitReview.Domain.Tests.csproj --filter "FullyQualifiedName~PanelLayoutFinishTests|FullyQualifiedName~HousekeepingTests" --no-restore`

Expected: selected tests pass.

- [ ] **Step 5: Commit**

```bash
git add visualstudio-extension/src/GitReview.Domain/PanelLayout.cs visualstudio-extension/src/GitReview.Domain/Housekeeping.cs visualstudio-extension/tests/GitReview.Domain.Tests/PanelLayoutFinishTests.cs visualstudio-extension/tests/GitReview.Domain.Tests/HousekeepingTests.cs
git commit -m "fix(visualstudio): clarify finish cleanup"
```

### Task 3: JetBrains

**Files:**
- Modify: `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/PanelLayout.kt:700-716`
- Modify: `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/Housekeeping.kt:114-126`
- Test: `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutFinishTest.kt:10-33`
- Test: `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/HousekeepingTest.kt:158-174`

**Interfaces:** Uses `panelLayout` and `confirmCopyFor`; preserves `CLEAN_REVIEW`, `UNDO_FINISH`, and `CLEAN_KEEP_FIXES`.

- [ ] **Step 1: Write failing tests**

```kotlin
assertEquals("Keep edits & remove Undo", banner.row.controls[0].label)
assertEquals("Undo Finish", banner.row.controls[1].label)
assertTrue(banner.paragraphs[1].contains("You can still undo this finish."))
assertEquals("Keep your edits & remove Undo?", separate.title)
assertEquals("Keep edits & remove Undo", separate.button)
```

- [ ] **Step 2: Verify RED**

Run: `./gradlew.bat test --tests "com.ezevillo.gitreview.domain.PanelLayoutFinishTest" --tests "com.ezevillo.gitreview.domain.HousekeepingTest"`

Expected: fails on the current strings.

- [ ] **Step 3: Implement minimal copy changes**

Change only the finish-pending banner and `CLEAN_KEEP_FIXES` confirmation strings.

- [ ] **Step 4: Verify GREEN**

Run: `./gradlew.bat test --tests "com.ezevillo.gitreview.domain.PanelLayoutFinishTest" --tests "com.ezevillo.gitreview.domain.HousekeepingTest"`

Expected: selected tests pass.

- [ ] **Step 5: Commit**

```bash
git add jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/PanelLayout.kt jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/Housekeeping.kt jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutFinishTest.kt jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/HousekeepingTest.kt
git commit -m "fix(jetbrains): clarify finish cleanup"
```

### Task 4: TUI

**Files:**
- Modify: `tui/internal/domain/usercopy.go:200-201,306-307,514-516`
- Test: `tui/internal/ui/mutation_test.go:232-247`
- Test: `tui/internal/ui/render_test.go`
- Modify: six `tui/testdata/golden/finish-pending-*.txt` files

**Interfaces:** Uses the finish-pending copy constants and `beginCleanReview`; preserves `CleanKeepFixes` and the deterministic golden fixture.

- [ ] **Step 1: Write failing tests**

```go
if domain.FinishPendingLine2 != "Commit and push them from Source Control. You can still undo this finish." { t.Fatal("unexpected finish-pending line") }
if domain.DoneCleanUpLabel != "Keep edits & remove Undo" { t.Fatal("unexpected clean label") }
if domain.UndoLabel != "Undo Finish" { t.Fatal("unexpected undo label") }
if domain.CleanReviewConfirmTitle != "Keep your edits & remove Undo?" { t.Fatal("unexpected clean title") }
if domain.DoneLabel != "Keep edits & remove Undo" { t.Fatal("unexpected confirmation label") }
```

- [ ] **Step 2: Verify RED**

Run: `go test ./internal/ui -run "TestFinishPending"`

Expected: the new copy assertions fail.

- [ ] **Step 3: Implement copy and regenerate goldens**

Update the five constants, then run:

```bash
go test -tags goldenupdate ./internal/ui -update
```

Confirm only the six finish-pending golden files change.

- [ ] **Step 4: Verify GREEN**

Run: `go test ./internal/ui`

Expected: all 68 golden frames and TUI unit tests pass.

- [ ] **Step 5: Commit**

```bash
git add tui/internal/domain/usercopy.go tui/internal/ui/mutation_test.go tui/internal/ui/render_test.go tui/testdata/golden/finish-pending-80x24.txt tui/testdata/golden/finish-pending-80x24-nocolor.txt tui/testdata/golden/finish-pending-80x24-ascii.txt tui/testdata/golden/finish-pending-120x40.txt tui/testdata/golden/finish-pending-120x40-nocolor.txt tui/testdata/golden/finish-pending-120x40-ascii.txt
git commit -m "fix(tui): clarify finish cleanup"
```

### Task 5: Cross-client verification

**Files:**
- Verify: files from Tasks 1-4.

**Interfaces:** Consumes the approved copy contract and each client test suite; proves behavior remains unchanged.

- [ ] **Step 1: Check that new copy has no technical branch detail**

Run: `rg -n "temporary review branch|temporary undo branch" vscode-extension/src/views/panelHtml.ts vscode-extension/src/review/housekeeping.ts visualstudio-extension/src/GitReview.Domain/PanelLayout.cs visualstudio-extension/src/GitReview.Domain/Housekeeping.cs jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/PanelLayout.kt jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/Housekeeping.kt tui/internal/domain/usercopy.go`

Expected: no matches.

- [ ] **Step 2: Run the targeted client suites**

Run the green commands from Tasks 1-4.

Expected: every command exits 0.

- [ ] **Step 3: Inspect the worktree**

Run: `git diff --check && git status --short`

Expected: no whitespace errors; only intentional, committed work remains.
