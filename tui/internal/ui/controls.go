// Package ui is the bubbletea/lipgloss layer: Model, Update, View, key and
// mouse resolution. Everything here may import bubbletea/lipgloss/bubbles
// freely — internal/domain stays the only package forbidden to.
package ui

import "github.com/EzeVillo/git-review-workflow/tui/internal/domain"

// Control is one body control this phase actually draws and can activate —
// mode-resolved and de-duplicated, unlike layout.go's Layout[] map, which is
// a textual mirror of the canonical kept for the CI contract test
// (layout_contract_test.go) and lists a control once per `when:` branch even
// when only one of those branches ever applies to a given PanelModel.
// render.go and keys.go both build their view of "what's in this situation"
// from this one function, which is what keeps the drawn buttons and the
// keyboard-reachable ones from silently disagreeing.
type Control struct {
	ID domain.ControlID
	// Variant disambiguates a control id the canonical repeats with two
	// different targets in the same situation (openSupport: star vs bug).
	Variant string
	Enabled bool
}

// ControlsFor returns m's controls in draw order. Only controls Phase 4
// actually owns are listed here (see layout.go's own comment on the five
// row-control maps): draft/guide/fixes/inventory rows are Phase 7's
// (tasks.md T075-T080) and are deliberately absent — this phase's no-review
// screen draws the body controls below and nothing from those five maps.
func ControlsFor(m domain.PanelModel) []Control {
	switch domain.LayoutSituationFor(m) {
	case domain.LayoutCliMissing, domain.LayoutCliOutdated:
		return []Control{
			{ID: "copyCliInstall", Enabled: true},
			{ID: "installCli", Enabled: true},
		}

	case domain.LayoutNoReviewSetup:
		return []Control{
			{ID: "setBase", Enabled: true},
			{ID: "setRemote", Enabled: true},
		}

	case domain.LayoutNoReview:
		return []Control{
			{ID: "startReview", Enabled: true},
			{ID: "walkthroughInit", Enabled: true},
			{ID: "walkthroughBuild", Enabled: true},
			{ID: "compareReview", Enabled: true},
			{ID: "setBase", Enabled: true},
			{ID: "setRemote", Enabled: true},
			{ID: "openSupport", Variant: "star", Enabled: true},
			{ID: "openSupport", Variant: "bug", Enabled: true},
		}

	case domain.LayoutReviewWhole:
		// openAllChanges is not_in: [tui] (T006) — the only control this
		// situation would otherwise draw, so it is empty on purpose.
		return nil

	case domain.LayoutReviewWalk:
		var cs []Control
		if m.HasWhy {
			cs = append(cs, Control{ID: "showWhy", Enabled: true})
		}
		cs = append(cs,
			Control{ID: "openEntry", Enabled: true},
			Control{ID: "openChange", Enabled: true},
			Control{ID: "prev", Enabled: !m.AtFirst},
			Control{ID: "next", Enabled: !m.AtLast},
		)
		return cs

	case domain.LayoutReviewStep:
		return []Control{
			{ID: "openChange", Enabled: true},
			{ID: "prev", Enabled: !m.AtFirst},
			{ID: "next", Enabled: !m.AtLast},
		}

	case domain.LayoutFinishPending:
		return []Control{
			{ID: "cleanReview", Enabled: true},
			{ID: "undoFinish", Enabled: true},
		}

	case domain.LayoutFinishConflict:
		cs := []Control{
			{ID: "undoFinish", Enabled: true},
			{ID: "resumeFinish", Enabled: true},
		}
		if m.Mode == domain.ModeWalk {
			if m.HasWhy {
				cs = append(cs, Control{ID: "showWhy", Enabled: true})
			}
			cs = append(cs, Control{ID: "openEntry", Enabled: true})
		}
		cs = append(cs, Control{ID: "openChange", Enabled: true})
		return cs

	case domain.LayoutOutOfRange, domain.LayoutError:
		return []Control{{ID: "outOfRangeHelp", Enabled: true}}

	default:
		return nil
	}
}
