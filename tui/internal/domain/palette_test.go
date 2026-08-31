package domain

import "testing"

// TestPaletteActionsCoversExactlyTheOfferedActions ties palette.go's own
// table to ProductActions — ALREADY gated against the canonical in both
// directions by scripts/check-client-product-surface.mjs (T030) — so a
// product action added or removed there cannot silently drift out of sync
// with what the action list overlay (T084) offers: every id ProductActions
// declares has EITHER a PaletteActions row OR is one of the two declared
// PanelOnlyActions (continueReview/discardInventory — surface: panel in
// the canonical, never in the palette), and PaletteActions never invents an
// id that is neither offered nor one it should legitimately carry.
func TestPaletteActionsCoversExactlyTheOfferedActions(t *testing.T) {
	panelOnly := map[string]bool{}
	for _, id := range PanelOnlyActions {
		panelOnly[id] = true
	}
	inPalette := map[string]bool{}
	for _, a := range PaletteActions {
		if inPalette[a.ID] {
			t.Errorf("PaletteActions declares %q twice", a.ID)
		}
		if panelOnly[a.ID] {
			t.Errorf("PaletteActions declares %q, which PanelOnlyActions says never gets a palette row", a.ID)
		}
		inPalette[a.ID] = true
	}
	for _, id := range ProductActions {
		if panelOnly[id] {
			continue
		}
		if !inPalette[id] {
			t.Errorf("PaletteActions is missing product action %q", id)
		}
	}
	for id := range inPalette {
		if !Actions[id] {
			t.Errorf("PaletteActions declares %q, which is not one of the 26 offered actions", id)
		}
	}
	for _, id := range PanelOnlyActions {
		if !Actions[id] {
			t.Errorf("PanelOnlyActions declares %q, which is not one of the 26 offered actions", id)
		}
	}
}

// TestPaletteActionsHasALabel: every entry needs something to show in the
// overlay — a blank row would be a control nobody could pick.
func TestPaletteActionsHasALabel(t *testing.T) {
	for _, a := range PaletteActions {
		if PaletteLabel[a.ID] == "" {
			t.Errorf("PaletteActions %q has no PaletteLabel entry", a.ID)
		}
		if len(a.Situations) == 0 {
			t.Errorf("PaletteActions %q declares zero situations — it could never be offered", a.ID)
		}
	}
}

// TestPanelExcludedActionsAreAllInPalette: FR-021's four ids must actually
// be reachable from PaletteActions — declaring panel_excluded without a
// palette row would leave them with no surface at all.
func TestPanelExcludedActionsAreAllInPalette(t *testing.T) {
	inPalette := map[string]bool{}
	for _, a := range PaletteActions {
		inPalette[a.ID] = true
	}
	for _, id := range PanelExcluded {
		if !inPalette[id] {
			t.Errorf("panel_excluded action %q has no PaletteActions row", id)
		}
	}
}

// TestPaletteActionsForFiltersByAllThreeGates: situation, busy and
// readonly all narrow the offered set — the palette's own equivalent of
// ControlsFor's Enabled bit for ids that never get a body row.
func TestPaletteActionsForFiltersByAllThreeGates(t *testing.T) {
	if got := PaletteActionsFor(SituationReview, true, false); containsPaletteID(got, "next") {
		t.Error("next requires_not_busy: true and must not be offered while busy")
	}
	if got := PaletteActionsFor(SituationReview, false, true); containsPaletteID(got, "finishReview") {
		t.Error("finishReview requires_not_readonly: true and must not be offered on a readonly review")
	}
	if got := PaletteActionsFor(SituationNoReview, false, false); containsPaletteID(got, "next") {
		t.Error("next only applies to situation review")
	}
}

// TestPanelOnlyActionsNeverReachThePalette is the direct form of the bug
// this test guards against: continueReview and discardInventory both need
// a SPECIFIC row's own name a generic "pick an action, run it" dispatch
// cannot supply (the same reason vscode-extension/package.json pins both
// of their commandPalette entries to "when": "false") — neither may ever
// show up in PaletteActionsFor's output, for any situation.
func TestPanelOnlyActionsNeverReachThePalette(t *testing.T) {
	for _, sit := range allEightSituations {
		got := PaletteActionsFor(sit, false, false)
		for _, id := range PanelOnlyActions {
			if containsPaletteID(got, id) {
				t.Errorf("situation %s: PaletteActionsFor offers %q, a declared PanelOnlyActions id", sit, id)
			}
		}
	}
}

func containsPaletteID(actions []PaletteAction, id string) bool {
	for _, a := range actions {
		if a.ID == id {
			return true
		}
	}
	return false
}
