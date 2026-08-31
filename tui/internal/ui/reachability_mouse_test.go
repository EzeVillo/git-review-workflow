package ui

import (
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	tea "github.com/charmbracelet/bubbletea"
)

// outcomeSignature summarizes the OBSERVABLE part of an activation's result
// — which overlay (if any) is now open, the status line, and whether a
// tea.Cmd was returned — without trying to compare ConfirmOverlay/
// SelectOverlay by value (both carry closures, which reflect.DeepEqual only
// calls equal when both are nil). Two activations of the SAME control from
// the SAME starting PanelModel must produce the same signature, whichever
// input device triggered them.
type outcomeSignature struct {
	focus                          int
	confirm, sel, pal, txt, hasCmd bool
	status                         string
}

func signatureOf(m Model, cmd tea.Cmd) outcomeSignature {
	return outcomeSignature{
		focus: m.FocusIndex, confirm: m.confirm != nil, sel: m.selectOverlay != nil,
		pal: m.actionList != nil, txt: m.textOverlay != nil, hasCmd: cmd != nil, status: m.statusLine,
	}
}

// TestEveryDrawnControlIsReachableAndActivatableByMouseAlone is SC-015's
// mouse half (reachability_keyboard_test.go covers the keyboard one, T053):
// for every one of the 11 panel_layout: situations, every control
// ControlsFor draws has a REAL rectangle in View's own HitMap, a synthetic
// tea.MouseMsg click at that rectangle reaches it through Update (not
// HitMap.At() poked directly), focuses it, and — for an ENABLED control —
// activates it through the exact same activateControl call the keyboard
// path (Enter) resolves to; a DISABLED control focuses but must not
// activate, mirroring the keyboard test's own disabled-control assertion.
//
// Per T053's own text (still true here): a control whose activation does
// not fire anything real yet only has to produce the SAME outcome the
// keyboard path produces for it — this test never asserts that a mutation
// ran, only that clicking is not a second, different way to resolve a
// control.
func TestEveryDrawnControlIsReachableAndActivatableByMouseAlone(t *testing.T) {
	// copyCliInstall/copyDraftPrompt are real, enabled controls this sweep
	// clicks — silence the OSC 52 write so a real click does not spam the
	// test's own stdout with an escape sequence.
	restore := host.SetOSC52WriterForTest(func(string) {})
	defer restore()

	vp := Viewport{Cols: 120, Rows: 300, Color: true} // tall enough that capFooter's 55% budget never hides a row
	for _, sit := range domain.AllLayoutSituations {
		sit := sit
		t.Run(string(sit), func(t *testing.T) {
			panel := fixtureFor(sit)
			panel.MouseEnabled = true // mouse reporting is on by default (T090); off is covered separately below.
			controls := ControlsFor(panel)
			if len(controls) == 0 {
				return // review-whole: nothing drawn, same exemption T053 documents.
			}
			_, hm := View(panel, vp)

			for i, c := range controls {
				rect, ok := hm.Rect(c.ID, c.Variant)
				if !ok {
					t.Fatalf("control %d (%s/%s): no rectangle in the HitMap", i, c.ID, c.Variant)
				}

				// The mouse path: a real MouseMsg through Update, from a
				// fresh Model with focus nowhere near this control yet. Two
				// controls can share a row (a draft's copyDraftPrompt and
				// startFromDraft, say), so the CLICK's own column matters,
				// not just its row.
				mm := Model{Panel: panel, Viewport: vp, FocusIndex: -1}
				clicked, cmd := mm.Update(tea.MouseMsg{X: rect.Col, Y: rect.Row, Action: tea.MouseActionPress, Button: tea.MouseButtonLeft})
				mouseModel := clicked.(Model)
				if mouseModel.FocusIndex != i {
					t.Fatalf("control %d (%s/%s): click at (%d,%d) focused index %d, want %d",
						i, c.ID, c.Variant, rect.Col, rect.Row, mouseModel.FocusIndex, i)
				}
				mouseSig := signatureOf(mouseModel, cmd)

				if !c.Enabled {
					if mouseSig.confirm || mouseSig.sel || mouseSig.pal || mouseSig.txt || mouseSig.hasCmd {
						t.Fatalf("control %d (%s/%s) is disabled but the click activated it: %+v", i, c.ID, c.Variant, mouseSig)
					}
					continue
				}

				// The keyboard path: the SAME control, already focused, Enter
				// pressed — activateFocused -> IntentActivate -> the SAME
				// activateControl(id, variant) handleMouse itself calls.
				km := Model{Panel: panel, Viewport: vp, FocusIndex: i}
				kb, kcmd := km.activateControl(c.ID, c.Variant)
				keySig := signatureOf(kb, kcmd)
				keySig.focus = i // handleMouse's own focus-setting step is compared above already

				if keySig != mouseSig {
					t.Fatalf("control %d (%s/%s): mouse activation %+v != keyboard activation %+v",
						i, c.ID, c.Variant, mouseSig, keySig)
				}
			}
		})
	}
}

// TestMouseClickIgnoredWhenAnOverlayIsOpen: a stray mouse event while a
// confirm/select/palette/text overlay is showing must not resolve against
// the HIDDEN base panel underneath it.
func TestMouseClickIgnoredWhenAnOverlayIsOpen(t *testing.T) {
	panel := fixtureFor(domain.LayoutNoReview)
	panel.MouseEnabled = true
	vp := Viewport{Cols: 120, Rows: 60, Color: true}
	_, hm := View(panel, vp)
	controls := ControlsFor(panel)
	rect, ok := hm.Rect(controls[0].ID, controls[0].Variant)
	if !ok {
		t.Fatal("fixture must draw at least one control")
	}
	overlay := ConfirmMutation("abortReview", "t", "d", "a", domain.StateToken{}, mutationRequest{})
	m := Model{Panel: panel, Viewport: vp, confirm: overlay}
	got, cmd := m.Update(tea.MouseMsg{X: rect.Col, Y: rect.Row, Action: tea.MouseActionPress, Button: tea.MouseButtonLeft})
	m2 := got.(Model)
	if m2.confirm == nil {
		t.Fatal("a stray click must not close the open confirm overlay")
	}
	if m2.FocusIndex != 0 || cmd != nil {
		t.Fatalf("a stray click while a confirm overlay is open must be a pure no-op, got FocusIndex=%d cmd!=nil=%v", m2.FocusIndex, cmd != nil)
	}
}

// TestMouseIgnoredWhenReportingIsOff: with MouseEnabled=false (the toggle,
// FR-067), a MouseMsg must not resolve to anything — mirroring the real
// terminal behavior this toggle exists to restore (native drag-select),
// and covering the defensive check in case a stray event arrives anyway.
func TestMouseIgnoredWhenReportingIsOff(t *testing.T) {
	panel := fixtureFor(domain.LayoutNoReview)
	panel.MouseEnabled = false
	vp := Viewport{Cols: 120, Rows: 60, Color: true}
	_, hm := View(panel, vp)
	controls := ControlsFor(panel)
	rect, ok := hm.Rect(controls[0].ID, controls[0].Variant)
	if !ok {
		t.Fatal("fixture must draw at least one control")
	}
	m := Model{Panel: panel, Viewport: vp, FocusIndex: -1}
	got, cmd := m.Update(tea.MouseMsg{X: rect.Col, Y: rect.Row, Action: tea.MouseActionPress, Button: tea.MouseButtonLeft})
	m2 := got.(Model)
	if m2.FocusIndex != -1 || cmd != nil {
		t.Fatalf("a click must be inert while mouse reporting is off, got FocusIndex=%d cmd!=nil=%v", m2.FocusIndex, cmd != nil)
	}
}
