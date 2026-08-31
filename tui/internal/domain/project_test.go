package domain

import "testing"

func TestProjectReviewWhole(t *testing.T) {
	status, ok := ParsePorcelain(readFixture("whole-basic.txt"))
	if !ok {
		t.Fatal("fixture must parse")
	}
	m := Project(ProjectInput{Situation: SituationReview, Status: status, HasStatus: true})
	if m.Mode != ModeWhole || m.Branch != "review/feat-x" || m.Base != "develop" {
		t.Fatalf("core fields wrong: %+v", m)
	}
	if m.Total != 2 {
		t.Fatalf("Total = %d, want 2 (len(Entries))", m.Total)
	}
	if m.Files != "README.md\nsrc/quoting.ts" {
		t.Fatalf("Files = %q", m.Files)
	}
}

func TestProjectReviewWalk(t *testing.T) {
	status, ok := ParsePorcelain(readFixture("walk-basic.txt"))
	if !ok {
		t.Fatal("fixture must parse")
	}
	m := Project(ProjectInput{Situation: SituationReview, Status: status, HasStatus: true, Why: "because", WhyState: WhyPresent})
	if m.Mode != ModeWalk {
		t.Fatalf("Mode = %v", m.Mode)
	}
	if m.Position != 3 || m.Total != 7 {
		t.Fatalf("Position/Total = %d/%d, want 3/7", m.Position, m.Total)
	}
	if m.AtFirst || m.AtLast {
		t.Fatalf("AtFirst/AtLast = %v/%v, want both false at 3 of 7", m.AtFirst, m.AtLast)
	}
	if !m.HasCurrent || m.CurrentPath.Display != "src/core.ts" {
		t.Fatalf("CurrentPath = %+v", m.CurrentPath)
	}
	if m.WhyState != WhyPresent || m.Why != "because" {
		t.Fatalf("Why not carried through: %+v", m)
	}
}

// TestProjectReviewWalkDegradedWalkthrough is T094's own gate: a review
// whose walkthrough could not be applied degrades to whole, and the panel
// says so with a note instead of failing outright (CLAUDE.md § Walk y
// walkthrough: "un walkthrough roto o stale nunca falla una review").
func TestProjectReviewWalkDegradedWalkthrough(t *testing.T) {
	status := PorcelainResult{
		State: StateRecord{
			Branch: "review/feat-x", Mode: ModeWhole, Walkthrough: WalkthroughDegraded,
		},
	}
	m := Project(ProjectInput{Situation: SituationReview, Status: status, HasStatus: true})
	if !m.Degraded {
		t.Fatalf("Degraded = false, want true for a degraded walkthrough: %+v", m)
	}
	if m.Note != WalkthroughDegradedToWholeNote {
		t.Fatalf("Note = %q, want the degraded-to-whole note", m.Note)
	}
}

// TestProjectReviewWalkNotDegraded is the negative case: an ordinary review
// (walkthrough none/applied) never sets Degraded or Note on its own.
func TestProjectReviewWalkNotDegraded(t *testing.T) {
	status, ok := ParsePorcelain(readFixture("walk-basic.txt"))
	if !ok {
		t.Fatal("fixture must parse")
	}
	m := Project(ProjectInput{Situation: SituationReview, Status: status, HasStatus: true})
	if m.Degraded || m.Note != "" {
		t.Fatalf("an ordinary review must not set Degraded/Note: %+v", m)
	}
}

// TestProjectEntryPickerRows is goToEntry's own gate (T086): the picker's
// list comes from the SAME `entry` records status --porcelain reports,
// never re-derived, and step mode's raw stays the SHA (never a subject)
// even when a subject is available to use as the DISPLAY label.
func TestProjectEntryPickerRows(t *testing.T) {
	status, ok := ParsePorcelain(readFixture("walk-basic.txt"))
	if !ok {
		t.Fatal("fixture must parse")
	}
	m := Project(ProjectInput{Situation: SituationReview, Status: status, HasStatus: true})
	if m.EntryPickerRows == "" {
		t.Fatalf("EntryPickerRows must not be empty for a walk fixture with entries")
	}
	rows := FooterRows(m.EntryPickerRows)
	if len(rows) != len(status.Entries) {
		t.Fatalf("EntryPickerRows has %d rows, want %d (len(Entries))", len(rows), len(status.Entries))
	}
	first := rows[0]
	if len(first) != 3 {
		t.Fatalf("EntryPickerRows row shape = %v, want 3 cells", first)
	}
	if first[0] != "1" {
		t.Fatalf("first entry position = %q, want \"1\"", first[0])
	}
}

func TestProjectReviewStepBoundaries(t *testing.T) {
	status := PorcelainResult{
		State: StateRecord{Branch: "review/x", Mode: ModeStep, Position: 1, Total: 1, CurrentSHA: "abc123"},
		Files: []EntryRecord{{Position: 1, Path: NewPathRef("a.go")}, {Position: 2, Path: NewPathRef("b.go")}},
	}
	m := Project(ProjectInput{Situation: SituationReview, Status: status, HasStatus: true})
	if !m.AtFirst || !m.AtLast {
		t.Fatalf("single-commit step review must be both AtFirst and AtLast: %+v", m)
	}
	if m.EntryCount != 2 {
		t.Fatalf("EntryCount = %d, want 2 (len(Files))", m.EntryCount)
	}
	if m.Files != "a.go\nb.go" {
		t.Fatalf("Files = %q", m.Files)
	}
}

func TestProjectFinishConflictSetsFlag(t *testing.T) {
	status := PorcelainResult{
		State:  StateRecord{Branch: "review/x", Mode: ModeWhole},
		Finish: &StatusFinishRecord{State: "conflict", Onto: true},
	}
	m := Project(ProjectInput{Situation: SituationFinishConflict, Status: status, HasStatus: true})
	if !m.FinishConflict {
		t.Fatal("FinishConflict must be set when status carries a finish record")
	}
}

func TestProjectNoReviewWithoutConfigDefaultsToSetup(t *testing.T) {
	m := Project(ProjectInput{Situation: SituationNoReview})
	if !m.NoBaseConfigured {
		t.Fatal("no config read at all must fall back to the setup screen, not silently claim a base is configured")
	}
}

func TestProjectNoReviewWithConfig(t *testing.T) {
	cfg := ParseConfigPorcelain(readFixture("config-basic.txt"))
	m := Project(ProjectInput{Situation: SituationNoReview, Config: cfg, HasConfig: true})
	if m.NoBaseConfigured {
		t.Fatal("config-basic.txt declares a base; NoBaseConfigured must be false")
	}
	if m.ConfiguredBase != "develop" || m.ConfiguredRemote != "origin" {
		t.Fatalf("ConfiguredBase/Remote = %q/%q", m.ConfiguredBase, m.ConfiguredRemote)
	}
}

func TestProjectFinishPendingDestination(t *testing.T) {
	branches := ParseListPorcelain(readFixture("list-basic.txt"))
	m := Project(ProjectInput{Situation: SituationFinishPending, Branches: branches, HasList: true})
	if !m.PendingFinish {
		t.Fatal("expected PendingFinish for the current branch's pending finish record")
	}
	if m.FinishDestination != "review-fixes/feature" {
		t.Fatalf("FinishDestination = %q, want review-fixes/feature", m.FinishDestination)
	}
}

func TestProjectFailureSituationsCarryOnlyStderrAndBusy(t *testing.T) {
	for _, sit := range []Situation{SituationCliMissing, SituationCliOutdated, SituationOutOfRange, SituationError} {
		m := Project(ProjectInput{Situation: sit, Stderr: "boom", Busy: true, MouseEnabled: true})
		want := PanelModel{Situation: sit, Stderr: "boom", Busy: true, MouseEnabled: true}
		if m != want {
			t.Fatalf("%s: got %+v, want %+v", sit, m, want)
		}
	}
}

// --- the footer (Phase 7, T075-T083) ---------------------------------------

func TestProjectFooterWalkthroughAndGuideRows(t *testing.T) {
	cfg := ParseConfigPorcelain(readFixture("config-basic.txt"))
	m := Project(ProjectInput{Situation: SituationNoReview, Config: cfg, HasConfig: true})
	if !m.HasWalkthroughRow || m.WalkthroughRow != "feature" || m.WalkthroughState != WalkthroughInSync {
		t.Fatalf("walkthrough row mangled: %+v", m)
	}
	if m.WalkthroughAnnotated != 4 || m.WalkthroughTotal != 4 {
		t.Fatalf("walkthrough progress mangled: %d/%d", m.WalkthroughAnnotated, m.WalkthroughTotal)
	}
	if !m.HasGuideRows {
		t.Fatal("HasGuideRows must be true when config-basic.txt's two guide records were read")
	}
	if m.TeamGuideRow != "/home/x/repo/.review/walkthrough-guide.md" || m.TeamGuideState != GuideInForce {
		t.Fatalf("team guide row mangled: %q / %q", m.TeamGuideRow, m.TeamGuideState)
	}
	if m.OwnGuideRow != "/home/x/.git/review-walkthrough-guide.md" || m.OwnGuideState != GuideAbsent {
		t.Fatalf("own guide row mangled: %q / %q", m.OwnGuideRow, m.OwnGuideState)
	}
}

func TestProjectFooterSplitsDraftsFreshVsSpent(t *testing.T) {
	cfg := ConfigPorcelainResult{Drafts: []DraftRecord{
		{Src: "feat-a", Path: "/g/feat-a.md", Annotated: 1, Total: 2, Source: DraftSourceRemote, Range: DraftRangeFull, State: DraftFresh},
		{Src: "feat-b", Path: "/g/feat-b.md", Annotated: 3, Total: 3, Source: DraftSourceLocal, Range: DraftRangeDelta, State: DraftReviewed},
	}}
	m := Project(ProjectInput{Situation: SituationNoReview, Config: cfg, HasConfig: true})
	if m.FreshDraftCount != 1 || m.SpentDraftCount != 1 {
		t.Fatalf("expected 1 fresh + 1 spent, got %d/%d", m.FreshDraftCount, m.SpentDraftCount)
	}
	wantFresh := FooterField("feat-a", "/g/feat-a.md", "remote", "full", "1", "2")
	if m.FreshDraftRows != wantFresh {
		t.Errorf("fresh draft row = %q, want %q", m.FreshDraftRows, wantFresh)
	}
	wantSpent := FooterField("feat-b", "/g/feat-b.md", "local", "delta", "3", "3")
	if m.SpentDraftRows != wantSpent {
		t.Errorf("spent draft row = %q, want %q", m.SpentDraftRows, wantSpent)
	}
}

func TestProjectFooterFixesRows(t *testing.T) {
	fixes := ParseListFixes(readFixture("list-basic.txt"))
	m := Project(ProjectInput{Situation: SituationNoReview, Fixes: fixes, HasList: true})
	if m.FixesCount != 2 {
		t.Fatalf("FixesCount = %d, want 2", m.FixesCount)
	}
	rows := FooterRows(m.FixesRows)
	if len(rows) != 2 || rows[0][0] != "review-fixes/old-one" || rows[0][1] != string(FixesMerged) {
		t.Fatalf("fixes rows mangled: %v", rows)
	}
}

// TestProjectFooterInventoryResumability is panelModel.ts's own
// toPanelReviews rule, ported: a saved review stops being resumable once
// ANOTHER branch already has an active (non-saved) review for the same
// source — the exact case `git review continue` itself refuses.
func TestProjectFooterInventoryResumability(t *testing.T) {
	branches := []BranchRecord{
		{Name: "review-saved/feature", Saved: true},
		{Name: "review/feature", Saved: false, Current: true, Mode: ModeWalk, Position: 2, Total: 5, HasPositionTotal: true},
		{Name: "review-saved/other", Saved: true},
		{Name: "review/broken", Orphan: true},
	}
	m := Project(ProjectInput{Situation: SituationNoReview, Branches: branches, HasList: true})
	if !m.HasReviews || m.InventoryCount != 4 {
		t.Fatalf("HasReviews/InventoryCount = %v/%d, want true/4", m.HasReviews, m.InventoryCount)
	}
	rows := FooterRows(m.InventoryRows)
	if len(rows) != 4 {
		t.Fatalf("expected 4 inventory rows, got %d", len(rows))
	}
	// review-saved/feature: saved, but review/feature is active for the same
	// source -- NOT resumable.
	if rows[0][0] != "review-saved/feature" || cellBool(rows[0][4]) {
		t.Fatalf("review-saved/feature must not be resumable while review/feature is active: %v", rows[0])
	}
	// review-saved/other: saved, nothing else active for "other" -- resumable.
	if rows[2][0] != "review-saved/other" || !cellBool(rows[2][4]) {
		t.Fatalf("review-saved/other must be resumable: %v", rows[2])
	}
	// review/broken: orphan, never resumable regardless of Saved.
	if rows[3][0] != "review/broken" || !cellBool(rows[3][2]) || cellBool(rows[3][4]) {
		t.Fatalf("review/broken must be orphan and not resumable: %v", rows[3])
	}
}

// FR-023: a review situation never projects a footer row, regardless of
// what a caller happens to pass in Config/Branches — the projector never
// even looks at them for SituationReview/SituationFinishConflict.
func TestProjectReviewNeverProjectsFooterRows(t *testing.T) {
	cfg := ParseConfigPorcelain(readFixture("config-basic.txt"))
	branches := ParseListPorcelain(readFixture("list-basic.txt"))
	status, ok := ParsePorcelain(readFixture("whole-basic.txt"))
	if !ok {
		t.Fatal("fixture must parse")
	}
	for _, sit := range []Situation{SituationReview, SituationFinishConflict} {
		m := Project(ProjectInput{
			Situation: sit, Status: status, HasStatus: true,
			Config: cfg, HasConfig: true, Branches: branches, HasList: true,
		})
		if m.HasWalkthroughRow || m.TeamGuideRow != "" || m.OwnGuideRow != "" ||
			m.FreshDraftRows != "" || m.SpentDraftRows != "" || m.FixesRows != "" ||
			m.InventoryRows != "" || m.HasReviews {
			t.Fatalf("%s: projector must never fill footer fields inside a review: %+v", sit, m)
		}
	}
}
