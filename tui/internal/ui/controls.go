// Package ui is the bubbletea/lipgloss layer: Model, Update, View, key and
// mouse resolution. Everything here may import bubbletea/lipgloss/bubbles
// freely — internal/domain stays the only package forbidden to.
package ui

import (
	"strconv"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

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

// ControlsFor returns m's controls in draw order. Phase 7 (tasks.md
// T075-T080) adds the five row-control maps' actual instances for
// LayoutNoReview — one Control per draft/guide/fixes/inventory row, built in
// noReviewControls below — on top of the fixed body controls Phase 4 already
// drew.
func ControlsFor(m domain.PanelModel) (controls []Control) {
	defer func() {
		if !m.Busy {
			return
		}
		for i := range controls {
			controls[i].Enabled = false
		}
	}()
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
		return noReviewControls(m)

	case domain.LayoutReviewWhole:
		// openAllChanges is not_in: [tui] (T006) — the only control this
		// situation would otherwise draw, so it is empty on purpose.
		return nil

	case domain.LayoutReviewWalk:
		var cs []Control
		if m.WhyState == domain.WhyPresent {
			// Variant carries the entry's RAW path (T094) — same pattern
			// every other row control uses (a draft's Src, a fixes branch's
			// Name): the subject travels with the control, not by position.
			cs = append(cs, Control{ID: "showWhy", Variant: m.CurrentPath.Raw, Enabled: true})
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
			if m.WhyState == domain.WhyPresent {
				cs = append(cs, Control{ID: "showWhy", Variant: m.CurrentPath.Raw, Enabled: true})
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

// --- no-review's footer: the five row-control maps, instantiated ----------
//
// noReviewControls builds the FULL no-review control list in the same
// top-to-bottom order panel_layout: draws its blocks in (contracts/
// client-product-surface.yaml, the `no-review:` key): fresh drafts, the
// inventory, startReview, the walkthrough row (init/build plus its two body
// controls), the two guide rows, spent drafts, the extracted-fixes section,
// then the three fixed tools_sections (Compare/Settings/Support) Phase 4
// already drew.
//
// Every row control's Variant is the RAW identifier the row names (a
// draft's Src, a fixes branch's Name, an inventory row's Name, "team"/"own"
// for the two guide rows) — never a position. mutation.go's activateControl
// resolves the target row the same way, by scanning m.Panel's own
// FooterRows for a matching Variant, so a row that moved between two
// refreshes still names the right one instead of "whatever is now at index
// N".
func noReviewControls(m domain.PanelModel) []Control {
	var cs []Control

	for _, d := range decodeDraftRows(m.FreshDraftRows) {
		cs = append(cs,
			Control{ID: "copyDraftPrompt", Variant: d.src, Enabled: true},
			Control{ID: "startFromDraft", Variant: d.src, Enabled: d.startable()},
			Control{ID: "openDraft", Variant: d.src, Enabled: true},
			Control{ID: "discardDraft", Variant: d.src, Enabled: true},
		)
	}

	for _, r := range decodeInventoryRows(m.InventoryRows) {
		if !r.canDiscard() {
			continue
		}
		if r.saved {
			cs = append(cs, Control{ID: "continueReview", Variant: r.name, Enabled: r.resumable})
		}
		cs = append(cs, Control{ID: "discardInventory", Variant: r.name, Enabled: true})
	}

	cs = append(cs, Control{ID: "startReview", Enabled: true})
	cs = append(cs, Control{ID: "walkthroughInit", Enabled: true}, Control{ID: "walkthroughBuild", Enabled: true})

	// The row's own two body controls only exist once there is a row to
	// hang them on — same gate as the guide rows below (HasGuideRows), and
	// unlike walkthroughInit/walkthroughBuild above, which are fixed body
	// controls of the section itself (Layout[LayoutNoReview]) and are drawn
	// regardless of whether the `walkthrough` record was ever read.
	if m.HasWalkthroughRow {
		fileExists := m.WalkthroughState != domain.WalkthroughAbsent
		cs = append(cs,
			Control{ID: "openWalkthrough", Enabled: fileExists},
			Control{ID: "copyWalkthroughPrompt", Enabled: fileExists},
		)
	}

	if m.HasGuideRows {
		cs = append(cs,
			Control{ID: "openGuide", Variant: "team", Enabled: m.TeamGuideState != domain.GuideAbsent},
			Control{ID: "createGuide", Variant: "team", Enabled: m.TeamGuideState == domain.GuideAbsent},
			Control{ID: "openGuide", Variant: "own", Enabled: m.OwnGuideState != domain.GuideAbsent},
			Control{ID: "createGuide", Variant: "own", Enabled: m.OwnGuideState == domain.GuideAbsent},
			// discardGuide: own row only (guide_rows.controls' own comment —
			// the shared guide is a tracked file, and the CLI itself refuses
			// --delete --team).
			Control{ID: "discardGuide", Variant: "own", Enabled: m.OwnGuideState != domain.GuideAbsent},
		)
	}

	for _, d := range decodeDraftRows(m.SpentDraftRows) {
		// A spent draft's row loses the two labelled controls (draft_controls'
		// own comment: Copy for agent and Validate and start both promise a
		// step that already happened) and keeps only the two icons.
		cs = append(cs,
			Control{ID: "openDraft", Variant: d.src, Enabled: true},
			Control{ID: "discardDraft", Variant: d.src, Enabled: true},
		)
	}

	if m.FixesCount > 0 {
		for _, f := range decodeFixesRows(m.FixesRows) {
			cs = append(cs, Control{ID: "discardFixes", Variant: f.name, Enabled: !f.current})
		}
		cs = append(cs, Control{ID: "discardAllFixes", Enabled: true})
	}

	cs = append(cs,
		Control{ID: "compareReview", Enabled: true},
		Control{ID: "setBase", Enabled: true},
		Control{ID: "setRemote", Enabled: true},
		Control{ID: "openSupport", Variant: "star", Enabled: true},
		Control{ID: "openSupport", Variant: "bug", Enabled: true},
	)
	return cs
}

// --- decoding the footer's tab-packed rows (domain.FooterRows) ------------
//
// Three tiny row views, one per list-shaped footer field. Each wraps the
// cell layout project.go's draftRow/projectFixesRows/projectInventoryRows
// write, in ONE place, so a field added to one side is a compile error on
// the other instead of a silently-misread column.

type draftRowView struct {
	src, path, source, rrange string
	annotated, total          int
}

// startable mirrors draft_controls' own comment on startFromDraft: disabled
// whenever the source/range flags are unknown (the instructions block was
// deleted by hand) OR the order is not yet fully annotated — the flags
// reason is checked first because it is the one that also breaks `build`,
// regardless of how complete the order looks.
func (d draftRowView) startable() bool {
	if d.source == string(domain.DraftSourceUnknown) || d.rrange == string(domain.DraftRangeUnknown) {
		return false
	}
	return d.total > 0 && d.annotated >= d.total
}

func decodeDraftRows(joined string) []draftRowView {
	rows := domain.FooterRows(joined)
	out := make([]draftRowView, 0, len(rows))
	for _, r := range rows {
		if len(r) < 6 {
			continue
		}
		ann, _ := strconv.Atoi(r[4])
		tot, _ := strconv.Atoi(r[5])
		out = append(out, draftRowView{src: r[0], path: r[1], source: r[2], rrange: r[3], annotated: ann, total: tot})
	}
	return out
}

type fixesRowView struct {
	name, state      string
	session, current bool
}

func decodeFixesRows(joined string) []fixesRowView {
	rows := domain.FooterRows(joined)
	out := make([]fixesRowView, 0, len(rows))
	for _, r := range rows {
		if len(r) < 4 {
			continue
		}
		out = append(out, fixesRowView{name: r[0], state: r[1], session: r[2] == "1", current: r[3] == "1"})
	}
	return out
}

type inventoryRowView struct {
	name                              string
	saved, orphan, current, resumable bool
	status                            string
}

func (r inventoryRowView) canDiscard() bool { return r.saved || r.orphan }

func decodeInventoryRows(joined string) []inventoryRowView {
	rows := domain.FooterRows(joined)
	out := make([]inventoryRowView, 0, len(rows))
	for _, r := range rows {
		if len(r) < 6 {
			continue
		}
		out = append(out, inventoryRowView{
			name: r[0], saved: r[1] == "1", orphan: r[2] == "1", current: r[3] == "1",
			resumable: r[4] == "1", status: r[5],
		})
	}
	return out
}

// findDraftRow / findFixesRow / findInventoryRow resolve a row by the same
// raw identifier its controls carry as Variant — mutation.go's activation
// handlers use these to re-read the target row's full data (a path, a
// saved/orphan bit) from m.Panel at the moment a control fires, rather than
// trusting a position that could have shifted between two refreshes.
func findDraftRow(rows []draftRowView, src string) (draftRowView, bool) {
	for _, r := range rows {
		if r.src == src {
			return r, true
		}
	}
	return draftRowView{}, false
}

func findFixesRow(rows []fixesRowView, name string) (fixesRowView, bool) {
	for _, r := range rows {
		if r.name == name {
			return r, true
		}
	}
	return fixesRowView{}, false
}

func findInventoryRow(rows []inventoryRowView, name string) (inventoryRowView, bool) {
	for _, r := range rows {
		if r.name == name {
			return r, true
		}
	}
	return inventoryRowView{}, false
}
