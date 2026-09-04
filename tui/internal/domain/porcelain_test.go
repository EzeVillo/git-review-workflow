package domain

import "testing"

// --- status --porcelain -------------------------------------------------

func TestParsePorcelainStepHostileBytesDoNotShiftFields(t *testing.T) {
	out, ok := ParsePorcelain(readFixture("step-hostile-bytes.txt"))
	if !ok {
		t.Fatal("expected a valid state record")
	}
	if out.State.Branch != "review/feature" || out.State.Mode != ModeStep {
		t.Fatalf("state record mangled: %+v", out.State)
	}
	if len(out.Entries) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(out.Entries))
	}
	// The tab inside the subject survives literally, and the record after it
	// is untouched — label and position still line up.
	if out.Subjects[1] != "con\ttab" {
		t.Errorf("subject 1 = %q, want a literal tab preserved", out.Subjects[1])
	}
	if out.Subjects[2] != "plain-second" {
		t.Errorf("subject 2 shifted: %q", out.Subjects[2])
	}
	if out.Authors[1] != "no\tmbre <t@example.com>" {
		t.Errorf("author 1 = %q, want a literal tab preserved", out.Authors[1])
	}
	if out.Authors[2] != "tester <t@example.com>" {
		t.Errorf("author 2 shifted: %q", out.Authors[2])
	}
}

func TestParsePorcelainStepNonASCIIBytesRoundTrip(t *testing.T) {
	out, ok := ParsePorcelain(readFixture("step-non-ascii.txt"))
	if !ok {
		t.Fatal("expected a valid state record")
	}
	if out.Subjects[1] != "añadir café" {
		t.Errorf("subject 1 = %q", out.Subjects[1])
	}
	if out.Subjects[2] != "ship it 🚀" {
		t.Errorf("subject 2 = %q", out.Subjects[2])
	}
	if out.Authors[1] != "Eze Villalón <t@example.com>" {
		t.Errorf("author 1 = %q", out.Authors[1])
	}
}

func TestParsePorcelainEmptySubjectIsAnEmptyFieldNotAMissingRecord(t *testing.T) {
	out, ok := ParsePorcelain(readFixture("step-empty-subject.txt"))
	if !ok {
		t.Fatal("expected a valid state record")
	}
	text, present := out.Subjects[1]
	if !present {
		t.Fatal("subject 1 must be present (empty), not missing")
	}
	if text != "" {
		t.Errorf("subject 1 = %q, want empty", text)
	}
	if out.Subjects[2] != "after-the-empty-one" {
		t.Errorf("subject 2 shifted: %q", out.Subjects[2])
	}
}

func TestParsePorcelainWalkModeDequotesEntryPaths(t *testing.T) {
	out, ok := ParsePorcelain(readFixture("walk-basic.txt"))
	if !ok {
		t.Fatal("expected a valid state record")
	}
	if out.State.Mode != ModeWalk {
		t.Fatalf("mode = %q, want walk", out.State.Mode)
	}
	if out.State.CurrentPath.Display != "src/core.ts" {
		t.Errorf("current path display = %q", out.State.CurrentPath.Display)
	}
	if !out.State.Essential {
		t.Error("state essential should be true")
	}
	if len(out.Entries) != 3 {
		t.Fatalf("expected 3 entries, got %d", len(out.Entries))
	}
	last := out.Entries[2]
	if last.Path.Raw != `"a\303\261o.txt"` {
		t.Errorf("raw path = %q, want the quoted wire form unchanged", last.Path.Raw)
	}
	if last.Path.Display != "año.txt" {
		t.Errorf("display path = %q, want dequoted", last.Path.Display)
	}
}

func TestParsePorcelainWholeModeReadsBase(t *testing.T) {
	out, ok := ParsePorcelain(readFixture("whole-basic.txt"))
	if !ok {
		t.Fatal("expected a valid state record")
	}
	if out.State.Mode != ModeWhole {
		t.Fatalf("mode = %q, want whole", out.State.Mode)
	}
	if out.Base != "develop" {
		t.Errorf("base = %q", out.Base)
	}
	if len(out.Entries) != 2 || out.Entries[0].Path.Display != "README.md" {
		t.Fatalf("entries = %+v", out.Entries)
	}
}

// FR-015, form 2: a record with MORE fields than this parser knows about is
// read anyway — the extra trailing fields are simply not consulted.
func TestParsePorcelainIgnoresUnknownTrailingFields(t *testing.T) {
	out, ok := ParsePorcelain("state\treview/x\tx\tsha1\twhole\tnone\tSOME\tFUTURE\tFIELDS\n")
	if !ok {
		t.Fatal("a record with extra trailing fields must still parse")
	}
	if out.State.Branch != "review/x" {
		t.Errorf("branch = %q", out.State.Branch)
	}
}

// FR-015, form 3: an unknown record tag is skipped without error, not
// treated as a parse failure.
func TestParsePorcelainIgnoresUnknownRecordTag(t *testing.T) {
	out, ok := ParsePorcelain("state\treview/x\tx\tsha1\twhole\tnone\n" +
		"totally-unknown-tag-from-a-newer-cli\tfoo\tbar\n")
	if !ok {
		t.Fatal("an unknown record must not fail the whole parse")
	}
	if out.State.Branch != "review/x" {
		t.Errorf("branch = %q", out.State.Branch)
	}
}

// FR-015, form 1: a record with FEWER fields than a newer client expects
// (an older CLI) still yields a usable state instead of panicking on an
// out-of-range index.
func TestParsePorcelainToleratesShortRecords(t *testing.T) {
	out, ok := ParsePorcelain("state\treview/x\tx\tsha1\twhole\n")
	if !ok {
		t.Fatal("a short state record should still parse")
	}
	if out.State.Walkthrough != "" {
		t.Errorf("missing walkthrough field should read as empty, got %q", out.State.Walkthrough)
	}
}

func TestParsePorcelainNoStateRecordIsAFailure(t *testing.T) {
	if _, ok := ParsePorcelain("entry\t1\tfoo.txt\n"); ok {
		t.Fatal("an entry record before any state record must fail")
	}
	if _, ok := ParsePorcelain(""); ok {
		t.Fatal("empty output has no state record")
	}
}

// --- list --porcelain ----------------------------------------------------

func TestParseListPorcelain(t *testing.T) {
	branches := ParseListPorcelain(readFixture("list-basic.txt"))
	if len(branches) != 2 {
		t.Fatalf("expected 2 branches, got %d: %+v", len(branches), branches)
	}
	feature := branches[0]
	if feature.Name != "review/feature" || feature.Mode != ModeWalk {
		t.Fatalf("feature branch mangled: %+v", feature)
	}
	if feature.Finish == nil || feature.Finish.State != "pending" {
		t.Fatalf("feature finish not matched by branch name: %+v", feature.Finish)
	}
	other := branches[1]
	if !other.Saved || !other.Orphan {
		t.Fatalf("saved/orphan branch mangled: %+v", other)
	}
	if SourceOf(feature) != "feature" {
		t.Errorf("SourceOf(review/feature) = %q", SourceOf(feature))
	}
	if SourceOf(other) != "other" {
		t.Errorf("SourceOf(review-saved/other) = %q", SourceOf(other))
	}
}

func TestParseListPorcelainNoReviewsIsValid(t *testing.T) {
	branches := ParseListPorcelain("")
	if branches == nil {
		t.Fatal("ParseListPorcelain must return a non-nil empty slice, not nil")
	}
	if len(branches) != 0 {
		t.Fatalf("expected no branches, got %d", len(branches))
	}
}

func TestParseListFixes(t *testing.T) {
	fixes := ParseListFixes(readFixture("list-basic.txt"))
	if len(fixes) != 2 {
		t.Fatalf("expected 2 fixes records, got %d", len(fixes))
	}
	if fixes[0].State != FixesMerged {
		t.Errorf("fixes[0].State = %q", fixes[0].State)
	}
	// An unrecognized state value folds to Unknown, never one of the three
	// concrete ones.
	if fixes[1].State != FixesUnknown {
		t.Errorf("fixes[1].State = %q, want unknown", fixes[1].State)
	}
}

// --- config --porcelain ---------------------------------------------------

func TestParseConfigPorcelain(t *testing.T) {
	out := ParseConfigPorcelain(readFixture("config-basic.txt"))
	if out.Config.Base != "develop" || !out.Config.HasBase {
		t.Fatalf("config.base mangled: %+v", out.Config)
	}
	if out.Config.Remote != "origin" {
		t.Errorf("config.remote = %q", out.Config.Remote)
	}
	if len(out.Candidates) != 2 {
		t.Fatalf("expected 2 candidates, got %d", len(out.Candidates))
	}
	if len(out.Remotes) != 1 || out.Remotes[0].Name != "origin" {
		t.Fatalf("remotes mangled: %+v", out.Remotes)
	}
	if len(out.Deltas) != 1 || out.Deltas[0].Origin != "remote" {
		t.Fatalf("deltas mangled: %+v", out.Deltas)
	}
	if len(out.Offers) != 2 {
		t.Fatalf("expected 2 offers, got %d", len(out.Offers))
	}
	if len(out.Drafts) != 1 || out.Drafts[0].State != DraftFresh {
		t.Fatalf("drafts mangled: %+v", out.Drafts)
	}
	if len(out.Guides) != 2 {
		t.Fatalf("expected 2 guide rows always, got %d", len(out.Guides))
	}
	if out.Guides[0].Kind != GuideTeam || out.Guides[0].State != GuideInForce {
		t.Errorf("team guide mangled: %+v", out.Guides[0])
	}
	if out.Guides[1].Kind != GuideOwn || out.Guides[1].State != GuideAbsent {
		t.Errorf("own guide mangled: %+v", out.Guides[1])
	}
	if out.Walkthrough == nil || out.Walkthrough.Branch != "feature" {
		t.Fatalf("walkthrough row mangled: %+v", out.Walkthrough)
	}
}

// TestParseConfigPorcelainReportsAbsenceRatherThanOmittingTheRow is T075's
// own gate: a branch with neither guide written nor a walkthrough on it
// still gets the team guide row, the own guide row and the walkthrough row
// — each carrying its `absent` state — exactly as many rows as a branch
// with all three in force. Only `draft` is legitimately absent-as-in-no-row:
// a loose draft only exists once a reviewer starts one, and this fixture has
// none.
func TestParseConfigPorcelainReportsAbsenceRatherThanOmittingTheRow(t *testing.T) {
	out := ParseConfigPorcelain(readFixture("config-no-prose.txt"))
	if len(out.Drafts) != 0 {
		t.Fatalf("draft has no record here, so no draft row should appear: %+v", out.Drafts)
	}
	if len(out.Guides) != 2 {
		t.Fatalf("the two guide rows must still be reported when both files are absent, got %d", len(out.Guides))
	}
	if out.Guides[0].Kind != GuideTeam || out.Guides[0].State != GuideAbsent {
		t.Errorf("team guide row must report absent, not disappear: %+v", out.Guides[0])
	}
	if out.Guides[1].Kind != GuideOwn || out.Guides[1].State != GuideAbsent {
		t.Errorf("own guide row must report absent, not disappear: %+v", out.Guides[1])
	}
	if out.Walkthrough == nil {
		t.Fatal("the walkthrough row must still be reported when the file is absent, not omitted")
	}
	if out.Walkthrough.State != WalkthroughAbsent {
		t.Errorf("walkthrough row must report absent, got %+v", out.Walkthrough)
	}
	if !out.Walkthrough.HasBranch || out.Walkthrough.Branch != "main" {
		t.Errorf("walkthrough row must still name its branch: %+v", out.Walkthrough)
	}
}

func TestParseConfigPorcelainDefaultsRemoteToOrigin(t *testing.T) {
	out := ParseConfigPorcelain("")
	if out.Config.HasBase {
		t.Error("no base line means no base configured")
	}
	if out.Config.Remote != "origin" {
		t.Errorf("remote = %q, want origin as the last-resort default", out.Config.Remote)
	}
	if out.Candidates == nil || out.Guides == nil || out.Drafts == nil || out.Remotes == nil {
		t.Fatal("all list fields must default to non-nil empty slices")
	}
}

func TestDeltaForSourceMapsLocalAndOfflineToTheLocalRow(t *testing.T) {
	deltas := []DeltaRecord{{Name: "feature", Tip: "abc", Origin: "remote"}, {Name: "feature", Tip: "def", Origin: "local"}}
	if d, ok := DeltaForSource(deltas, "remote"); !ok || d.Tip != "abc" {
		t.Errorf("remote source should pick the remote row, got %+v ok=%v", d, ok)
	}
	if d, ok := DeltaForSource(deltas, "local"); !ok || d.Tip != "def" {
		t.Errorf("local source should pick the local row, got %+v ok=%v", d, ok)
	}
	if d, ok := DeltaForSource(deltas, "offline"); !ok || d.Tip != "def" {
		t.Errorf("offline source should also pick the local row, got %+v ok=%v", d, ok)
	}
}

func TestParseMergedRecordAcceptsOnlyThreeNonNegativeCounts(t *testing.T) {
	got, ok := ParseMergedRecord("noise\nmerged\t4\t2\t1\n")
	if !ok || got.Kept != 4 || got.Added != 2 || got.Dropped != 1 {
		t.Fatalf("ParseMergedRecord(valid) = %+v, %v", got, ok)
	}
	for _, bad := range []string{"merged\t4\t-1\t0\n", "merged\tx\t1\t0\n", "merged\t1\t2\n"} {
		if _, ok := ParseMergedRecord(bad); ok {
			t.Fatalf("ParseMergedRecord(%q) accepted malformed counts", bad)
		}
	}
}

func TestBranchPickerItemsCollapsesByNamePreferringCurrent(t *testing.T) {
	items := BranchPickerItems([]CandidateBranch{
		{Name: "feature", Origin: "remote", Current: false},
		{Name: "feature", Origin: "local", Current: true},
		{Name: "other", Origin: "remote", Current: false},
	})
	if len(items) != 2 {
		t.Fatalf("expected 2 collapsed items, got %d: %+v", len(items), items)
	}
	if items[0].Name != "feature" || !items[0].Current {
		t.Errorf("feature row should be the current one: %+v", items[0])
	}
}

// The start wizard must present the same deterministic default as VS Code,
// JetBrains, and Visual Studio: current first, then branch name. A porcelain
// producer changing its arrival order must not silently choose another branch.
func TestBranchPickerItemsOrdersCurrentThenName(t *testing.T) {
	items := BranchPickerItems([]CandidateBranch{
		{Name: "zebra", Origin: "remote"},
		{Name: "feature/checkout", Origin: "remote"},
		{Name: "develop", Origin: "local", Current: true},
		{Name: "feature/checkout", Origin: "local"},
		{Name: "alpha", Origin: "remote"},
	})
	want := []string{"develop", "alpha", "feature/checkout", "zebra"}
	if len(items) != len(want) {
		t.Fatalf("got %d candidates, want %d: %+v", len(items), len(want), items)
	}
	for i, name := range want {
		if items[i].Name != name {
			t.Fatalf("item %d = %q, want %q (all=%+v)", i, items[i].Name, name, items)
		}
	}
}
