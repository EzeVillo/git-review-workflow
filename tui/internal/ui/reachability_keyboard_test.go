package ui

import (
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	tea "github.com/charmbracelet/bubbletea"
)

// TestEveryDeclaredControlIsReachableAndActivatableByKeyboardAlone is
// FR-073/SC-015's gate: for every one of the 11 panel_layout: situations,
// every control ControlsFor draws can be FOCUSED by real j/k KeyMsg values
// run through Model.Update (proving the message-driven navigation actually
// works, not just that FocusIndex can be poked directly) and then
// ACTIVATED by resolving "enter" against that focus.
//
// This walks all 11 layout situations rather than the informal "eight" the
// spec's prose uses for the Situation enum: review/finish-conflict each
// split into more than one distinct control set by Mode (review-walk,
// review-step, review-whole; finish-conflict's own walk/step split), and
// those are exactly the sets ControlsFor and render.go actually branch on —
// testing only the eight outer Situation values would silently skip two of
// review's three control sets.
//
// Per T053's own text: a control whose action does not fire anything real
// yet (most of Phase 4's — mutations are Phase 6+, delegated actions are
// Phase 8) still has to produce the CORRECT Intent; this test never asserts
// that a mutation ran, only that the right control was named.
func TestEveryDeclaredControlIsReachableAndActivatableByKeyboardAlone(t *testing.T) {
	for _, sit := range domain.AllLayoutSituations {
		sit := sit
		t.Run(string(sit), func(t *testing.T) {
			panel := fixtureFor(sit)
			controls := ControlsFor(panel)
			if len(controls) == 0 {
				// review-whole: openAllChanges is not_in: [tui] (T006), so
				// this situation legitimately has nothing to reach.
				return
			}

			m := Model{Panel: panel}
			for i, want := range controls {
				// Walk from wherever focus currently sits to index i using
				// REAL KeyMsg values through Update, wrapping with 'j' the
				// same number of steps len(controls) would take at most —
				// this proves the whole ring is walkable, not just that one
				// jump lands correctly.
				for step := 0; step < len(controls); step++ {
					if m.FocusIndex == i {
						break
					}
					newModel, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'j'}})
					m = newModel.(Model)
				}
				if m.FocusIndex != i {
					t.Fatalf("control %d (%s/%s): could not reach focus index %d via j (stuck at %d)",
						i, want.ID, want.Variant, i, m.FocusIndex)
				}

				intent := ResolveKey("enter", m)
				if !want.Enabled {
					if intent.Kind == IntentActivate {
						t.Errorf("control %d (%s/%s) is disabled but Enter still activated it", i, want.ID, want.Variant)
					}
					continue
				}
				if intent.Kind != IntentActivate {
					t.Fatalf("control %d (%s/%s): Enter resolved to %+v, want IntentActivate", i, want.ID, want.Variant, intent)
				}
				if intent.Control != want.ID || intent.Variant != want.Variant {
					t.Fatalf("control %d: Enter activated (%s/%s), want (%s/%s)",
						i, intent.Control, intent.Variant, want.ID, want.Variant)
				}
			}

			// k must walk the ring backwards just as reliably.
			for i := len(controls) - 1; i >= 0; i-- {
				for step := 0; step < len(controls); step++ {
					if m.FocusIndex == i {
						break
					}
					newModel, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'k'}})
					m = newModel.(Model)
				}
				if m.FocusIndex != i {
					t.Fatalf("k-navigation: could not reach focus index %d (stuck at %d)", i, m.FocusIndex)
				}
			}
		})
	}
}

// A narrower, explicit check for the situation the spec calls out by name
// (User Story 3, escenario 4): finish-conflict's controls are reachable and
// activatable, and neither n nor p is one of them.
func TestFinishConflictControlsReachableWithoutCursorKeys(t *testing.T) {
	panel := fixtureFor(domain.LayoutFinishConflict)
	controls := ControlsFor(panel)
	if len(controls) == 0 {
		t.Fatal("finish-conflict must draw at least undoFinish/resumeFinish")
	}
	for _, c := range controls {
		if c.ID == "next" || c.ID == "prev" {
			t.Fatalf("finish-conflict must never draw a cursor control, found %q", c.ID)
		}
	}
}
