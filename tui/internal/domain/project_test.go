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
	m := Project(ProjectInput{Situation: SituationReview, Status: status, HasStatus: true, Why: "because", HasWhy: true})
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
	if !m.HasWhy || m.Why != "because" {
		t.Fatalf("Why not carried through: %+v", m)
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
