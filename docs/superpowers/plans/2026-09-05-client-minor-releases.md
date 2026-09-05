# Client Minor Releases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish-ready `0.4.0` releases for VS Code and JetBrains plus a `0.3.0` release for Visual Studio, each with complete release notes, while retaining TUI `0.1.0` unchanged.

**Architecture:** Use each client's existing version-stamping script as the only writer of its distributed version metadata. Add one hand-written, dated top-level section to each corresponding changelog that summarizes the client-visible changes accumulated since `origin/main`.

**Tech Stack:** POSIX shell bump scripts, npm package metadata, Gradle properties, MSBuild/VSIX XML, Markdown changelogs, Bats.

## Global Constraints

- VS Code changes from `0.3.0` to exactly `0.4.0`.
- JetBrains changes from `0.3.0` to exactly `0.4.0`.
- Visual Studio changes from `0.2.0` to exactly `0.3.0`.
- Do not change `tui/CHANGELOG.md`, `tui/internal/domain/version.go`, or TUI packaging metadata.
- Do not change CLI version `0.9.0` or its changelog.
- Changelog notes describe user-visible behavior grouped by release category, never raw commit history.

---

### Task 1: Stamp the three independently released clients

**Files:**
- Modify: `vscode-extension/package.json`
- Modify: `vscode-extension/package-lock.json`
- Modify: `jetbrains-plugin/gradle.properties`
- Modify: `visualstudio-extension/src/GitReview.VS/GitReview.VS.csproj`
- Modify: `visualstudio-extension/src/GitReview.VS/source.extension.vsixmanifest`
- Modify: `visualstudio-extension/Directory.Build.props`

**Interfaces:**
- Consumes: `vscode-extension/bump-version.sh X.Y.Z`, `jetbrains-plugin/bump-version.sh X.Y.Z`, and `visualstudio-extension/bump-version.sh X.Y.Z`.
- Produces: version metadata that `tests/version-consistency.bats` reads from package JSON, Gradle properties, MSBuild XML, and VSIX XML.

- [ ] **Step 1: Inspect the currently stamped version sites**

Run: `git diff -- vscode-extension/package.json vscode-extension/package-lock.json jetbrains-plugin/gradle.properties visualstudio-extension/src/GitReview.VS/GitReview.VS.csproj visualstudio-extension/src/GitReview.VS/source.extension.vsixmanifest visualstudio-extension/Directory.Build.props`

Expected: no pre-existing release-version edits.

- [ ] **Step 2: Stamp the versions through their release scripts**

Run:

```sh
./vscode-extension/bump-version.sh 0.4.0
./jetbrains-plugin/bump-version.sh 0.4.0
./visualstudio-extension/bump-version.sh 0.3.0
```

Expected: VS Code package and lock metadata are `0.4.0`, JetBrains `pluginVersion` is `0.4.0`, and all three Visual Studio sites are `0.3.0`.

- [ ] **Step 3: Verify metadata consistency**

Run: `bats tests/version-consistency.bats`

Expected: PASS after the matching changelog headings are added in Task 2; before that it may fail only for the three absent release headings.

### Task 2: Add the three release-note sections

**Files:**
- Modify: `vscode-extension/CHANGELOG.md`
- Modify: `jetbrains-plugin/CHANGELOG.md`
- Modify: `visualstudio-extension/CHANGELOG.md`

**Interfaces:**
- Consumes: source changes in `origin/main..HEAD` and the version values produced by Task 1.
- Produces: the topmost `## [0.4.0]` (VS Code and JetBrains) and `## [0.3.0]` (Visual Studio) sections that marketplace/release workflows extract.

- [ ] **Step 1: Write the VS Code `0.4.0` section**

Insert a dated section before `0.3.0`, with user-facing notes covering: dependable completion of panel actions, deduplicated base-branch selection, precise finish-cleanup confirmation, and truthful staged-edits messaging.

- [ ] **Step 2: Write the JetBrains `0.4.0` section**

Insert a dated section before `0.3.0`, covering: readable CLI failure details, refreshed current branch after mutations, deduplicated base selection, and precise finish/undo cleanup messaging.

- [ ] **Step 3: Write the Visual Studio `0.3.0` section**

Insert a dated section before `0.2.0`, covering: deduplicated base-branch selection, cleanup confirmation that states exactly what is deleted, and accurate staged-edits copy following a finish.

- [ ] **Step 4: Test the changelog-to-version contract**

Run: `bats tests/version-consistency.bats tests/release-notes.bats`

Expected: PASS. The newest release heading for every client exists, has non-empty notes, and no client changelog carries an `Unreleased` heading.

### Task 3: Validate the release surfaces and scope boundary

**Files:**
- Verify: `contracts/client-product-surface.yaml`
- Verify: `scripts/check-client-product-surface.mjs`
- Verify unchanged: `tui/CHANGELOG.md`
- Verify unchanged: `tui/internal/domain/version.go`
- Verify unchanged: `VERSION`
- Verify unchanged: `CHANGELOG.md`

**Interfaces:**
- Consumes: the version and changelog modifications from Tasks 1 and 2.
- Produces: evidence that the product contract remains valid and no out-of-scope release metadata changed.

- [ ] **Step 1: Run the product-surface consistency check**

Run: `node scripts/check-client-product-surface.mjs`

Expected: exits zero and reports `check-client-product-surface: ok`.

- [ ] **Step 2: Confirm release scope**

Run: `git diff -- tui/CHANGELOG.md tui/internal/domain/version.go VERSION CHANGELOG.md`

Expected: no output.

- [ ] **Step 3: Inspect the complete release diff**

Run: `git diff --check && git diff --stat && git status --short`

Expected: no whitespace errors; only the three clients' version metadata and changelogs, plus the already-approved planning/design documentation, are modified.

- [ ] **Step 4: Commit the completed release preparation**

Run: `git add vscode-extension jetbrains-plugin visualstudio-extension docs/superpowers/specs/2026-09-05-client-minor-release-design.md docs/superpowers/plans/2026-09-05-client-minor-releases.md && git commit -m "chore(release): bump editor client minor versions"`

Expected: one commit containing all three client release preparations; it must not include TUI or CLI version/changelog files.
