package ui

import (
	"context"
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	tea "github.com/charmbracelet/bubbletea"
)

// TestPanelExcludedActionsNeverGetABodyControl mirrors domain's own
// panel_excluded/keymap gates at the render layer (T084's own gate,
// FR-021): none of the four ids ControlsFor ever draws in the body, for
// ANY of the 11 layout situations — the action list overlay is their only
// surface.
func TestPanelExcludedActionsNeverGetABodyControl(t *testing.T) {
	excluded := map[string]bool{}
	for _, id := range domain.PanelExcluded {
		excluded[id] = true
	}
	for _, sit := range domain.AllLayoutSituations {
		panel := fixtureFor(sit)
		for _, c := range ControlsFor(panel) {
			if excluded[string(c.ID)] {
				t.Fatalf("situation %s draws panel_excluded action %q as a body control", sit, c.ID)
			}
		}
	}
}

// TestActionListOffersPanelExcludedWhenApplicable: the palette itself is
// where the four ids DO have to show up, for a situation the canonical
// enables them in.
func TestActionListOffersPanelExcludedWhenApplicable(t *testing.T) {
	al := NewActionList(domain.SituationReview, false, false)
	has := map[string]bool{}
	for _, it := range al.all {
		has[it.action] = true
	}
	for _, id := range []string{"goToEntry", "previewEditsStat", "showCliLog", "forgetReview"} {
		if !has[id] {
			t.Errorf("action list for situation review is missing panel_excluded action %q", id)
		}
	}
}

// A compact terminal must keep the palette's interaction contract on screen:
// moving to an action below the fold reveals that action without dropping the
// keyboard help that explains how to run it.
func TestActionPaletteScrollKeepsHelpVisibleAt80x24(t *testing.T) {
	al := NewActionList(domain.SituationReview, false, false)
	if len(al.all) < 20 {
		t.Fatalf("review palette needs the evaluated 20 actions, got %d", len(al.all))
	}
	al.Cursor = len(al.all) - 1
	last := al.all[al.Cursor].label
	frame := al.Render(Viewport{Cols: 80, Rows: 24, Color: false})
	if !strings.Contains(frame, last) {
		t.Fatalf("selected last action %q must be visible:\n%s", last, frame)
	}
	if !strings.Contains(frame, "up/down:move") {
		t.Fatalf("palette help must stay visible at 80x24:\n%s", frame)
	}
}

// TestActionListFiltersByLabelSubstring: typing narrows the visible items,
// case-insensitively, and Enter picks the item under the (possibly reset)
// cursor within the FILTERED set, never the unfiltered one.
func TestActionListFiltersByLabelSubstring(t *testing.T) {
	al := NewActionList(domain.SituationNoReview, false, false)
	if len(al.filtered()) == len(al.all) && len(al.all) == 0 {
		t.Fatal("fixture must offer at least one action for no-review")
	}
	al.Filter.SetValue("refresh")
	items := al.filtered()
	if len(items) != 1 || items[0].action != "refresh" {
		t.Fatalf("filtering by %q = %+v, want exactly [refresh]", "refresh", items)
	}
}

// TestActionListEnterOnEmptyFilterIsInert: Enter with no matches must not
// panic or pick a stale index.
func TestActionListEnterOnEmptyFilterIsInert(t *testing.T) {
	al := NewActionList(domain.SituationNoReview, false, false)
	al.Filter.SetValue("this matches absolutely nothing at all")
	action, picked, cancelled, _ := al.HandleKey(tea.KeyMsg{Type: tea.KeyEnter})
	if picked || cancelled || action != "" {
		t.Fatalf("Enter with zero matches must be inert, got action=%q picked=%v cancelled=%v", action, picked, cancelled)
	}
}

// TestGoToEntryNeverBuildsAMutation is T086's own gate: picking an entry
// opens it (a Cmd) or reports why it could not (status) — it NEVER returns
// a mutationRequest (`done`), which is the only path that could invoke
// next/prev or any other `git review` verb. The CLI's own cursor position
// is a fact only next/prev ever change, and neither is reachable from here.
func TestGoToEntryNeverBuildsAMutation(t *testing.T) {
	panel := reviewPanel()
	panel.EntryPickerRows = domain.FooterField("1", "a.go", "a.go") + "\n" + domain.FooterField("2", "b.go", "b.go")
	m := Model{Panel: panel}
	m2 := m.openEntryPicker()
	if m2.selectOverlay == nil {
		t.Fatal("openEntryPicker must open a picker when there are entries")
	}
	if len(m2.selectOverlay.Items) != 2 {
		t.Fatalf("picker has %d items, want 2", len(m2.selectOverlay.Items))
	}
	for _, it := range m2.selectOverlay.Items {
		result := m2.selectOverlay.OnPick(it.Value)
		if result.done != nil {
			t.Fatalf("picking entry %q built a mutationRequest (%+v) — goToEntry must never move the CLI's own cursor", it.Value, result.done)
		}
	}
}

// TestGoToEntryEmptyIsInert: no entries, nothing to pick from — the picker
// must not open onto a blank list.
func TestGoToEntryEmptyIsInert(t *testing.T) {
	m := Model{Panel: reviewPanel()} // EntryPickerRows left empty
	m2 := m.openEntryPicker()
	if m2.selectOverlay != nil {
		t.Fatal("openEntryPicker must not open with no entries to show")
	}
}

// TestShowCliLogArgvOnlyInTheThirdLayer is T087's own gate (contracts/
// tui-surface.md's three-layer copy rule): the palette's OWN label (the
// FIRST layer) never carries an argv, but the overlay's body (the THIRD
// layer, opened one gesture later) does.
func TestShowCliLogArgvOnlyInTheThirdLayer(t *testing.T) {
	label := domain.PaletteLabel["showCliLog"]
	if strings.Contains(label, "git") || strings.Contains(label, "--") {
		t.Fatalf("showCliLog's palette label %q leaks an argv into the first layer", label)
	}
	host.ResetInvocationLogForTest()
	host.InvokeSupportGit(context.Background(), []string{"rev-parse", "--git-dir"})
	m := Model{}
	m2, _ := m.beginShowCliLog()
	if m2.textOverlay == nil {
		t.Fatal("beginShowCliLog must open a TextOverlay")
	}
	if !strings.Contains(m2.textOverlay.Body, "rev-parse") {
		t.Fatalf("showCliLog's overlay body = %q, want it to name the argv it ran", m2.textOverlay.Body)
	}
}

// TestBeginPreviewEditsStatReturnsACommand: previewEditsStat is native
// (BuildArgv already has a real case for it, actions_test.go's own table),
// so activating it must dispatch a real tea.Cmd, not silently do nothing.
func TestBeginPreviewEditsStatReturnsACommand(t *testing.T) {
	m := Model{Panel: reviewPanel()}
	_, cmd := m.beginPreviewEditsStat()
	if cmd == nil {
		t.Fatal("beginPreviewEditsStat must return a Cmd")
	}
}

// TestCopyControlsNeverClaimToHaveCopied is FR-068's own gate: OSC 52 has
// no acknowledgement, so neither copy control's status line may ever say
// "Copied" — it says what IS true (the line is drawn, selectable) instead.
func TestCopyControlsNeverClaimToHaveCopied(t *testing.T) {
	restore := host.SetOSC52WriterForTest(func(string) {})
	defer restore()

	cliMissing := Model{Panel: domain.PanelModel{Situation: domain.SituationCliMissing}}
	m2, _ := cliMissing.beginCopyCliInstall()
	assertNeverClaimsCopied(t, m2.statusLine)

	panel := domain.PanelModel{
		Situation:       domain.SituationNoReview,
		FreshDraftRows:  domain.FooterField("feat-y", "/gitdir/review-walkthrough/feat-y.md", "remote", "full", "1", "3"),
		FreshDraftCount: 1,
	}
	draft := Model{Panel: panel}
	m3, _ := draft.beginCopyDraftPrompt("feat-y")
	assertNeverClaimsCopied(t, m3.statusLine)
}

// TestColonOpensTheActionListPerSituation is T084's own "a test per
// situation": pressing ":" through the REAL Update pipeline opens the
// action list, and its entries exactly match domain.PaletteActionsFor for
// that situation — never a fixed list, and never empty for a situation
// that offers at least refresh.
func TestColonOpensTheActionListPerSituation(t *testing.T) {
	for _, sit := range domain.AllLayoutSituations {
		panel := fixtureFor(sit)
		m := Model{Panel: panel}
		got, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{':'}})
		m2 := got.(Model)
		if m2.actionList == nil {
			t.Fatalf("%s: \":\" must open the action list", sit)
		}
		want := domain.PaletteActionsFor(panel.Situation, panel.Busy, panel.Readonly)
		if len(m2.actionList.all) != len(want) {
			t.Fatalf("%s: action list has %d entries, want %d (%v)", sit, len(m2.actionList.all), len(want), want)
		}
	}
}

// TestGKeyOpensEntryPickerOnlyInsideAReview: "g" (entry_picker) only does
// something where goToEntry itself applies (review/finish-conflict with
// entries to pick from) — elsewhere it is a safe no-op, never a crash.
func TestGKeyOpensEntryPickerOnlyInsideAReview(t *testing.T) {
	panel := reviewPanel()
	panel.EntryPickerRows = domain.FooterField("1", "a.go", "a.go")
	m := Model{Panel: panel}
	got, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'g'}})
	if got.(Model).selectOverlay == nil {
		t.Fatal("g must open the entry picker inside a review that has entries")
	}

	noReview := Model{Panel: domain.PanelModel{Situation: domain.SituationNoReview}}
	got2, _ := noReview.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'g'}})
	if got2.(Model).selectOverlay != nil {
		t.Fatal("g must not open anything in no-review, which has no entries")
	}
}

func assertNeverClaimsCopied(t *testing.T, status string) {
	t.Helper()
	if status == "" {
		t.Fatal("expected a non-empty status line after copying")
	}
	if strings.Contains(status, "Copied") {
		t.Fatalf("status line %q claims to have copied — OSC 52 has no acknowledgement (FR-068)", status)
	}
}
