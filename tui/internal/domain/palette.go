package domain

// PanelExcluded mirrors `panel_excluded:` in the canonical (FR-021): the
// four ids that live ONLY in the action list overlay, never in the body —
// keymap_test.go's TestPanelExcludedActionsHaveNoDirectKey enforces the
// keymap half of the same rule (no direct key under keymap.actions);
// palette_test.go enforces this half (reachable from the overlay, with no
// body control anywhere).
var PanelExcluded = []string{"goToEntry", "forgetReview", "previewEditsStat", "showCliLog"}

// PanelOnlyActions is the exact OPPOSITE of PanelExcluded: ids the
// canonical marks `surface: panel` (never `surface: both`), so they live
// ONLY in the body, never in the action list overlay. continueReview and
// discardInventory both need a SPECIFIC row's own name (which saved review,
// which leftover branch) that a generic "pick an action, then run it"
// dispatch has no way to supply — the same reason
// vscode-extension/package.json's menus.commandPalette pins both of their
// commands to `"when": "false"`: registered for the keybinding/context-menu
// surface, deliberately absent from the command palette. Declared here (not
// just left out of PaletteActions) so the omission reads as a decision, not
// a gap — scripts/check-client-product-surface.mjs cross-checks it against
// the canonical's own `surface:` field in both directions.
var PanelOnlyActions = []string{"continueReview", "discardInventory"}

// PaletteAction is one row the action list overlay (T084, ui/palette.go)
// can offer: the situations the canonical's `actions:` block declares for
// this id, plus the two gates it records there (requires_not_busy,
// requires_not_readonly) — the palette's own equivalent of ControlsFor's
// Enabled bit for the ids that never get a body row at all.
type PaletteAction struct {
	ID                  string
	Situations          []Situation
	RequiresNotBusy     bool
	RequiresNotReadonly bool
}

// allEightSituations is the shorthand `situations:` uses in the canonical
// for an id offered everywhere (cli-missing, cli-outdated, no-review,
// finish-pending, review, finish-conflict, out-of-range, error) — spelled
// out once here instead of eight times below.
var allEightSituations = []Situation{
	SituationCliMissing, SituationCliOutdated, SituationNoReview,
	SituationFinishPending, SituationReview, SituationFinishConflict,
	SituationOutOfRange, SituationError,
}

// PaletteActions mirrors contracts/client-product-surface.yaml's `actions:`
// block verbatim — situations, requires_not_busy, requires_not_readonly —
// for the 24 ids this client offers THROUGH THE PALETTE: the 26 offered
// overall (openAllChanges excluded: not_in: [tui], T006) minus the two
// PanelOnlyActions (continueReview, discardInventory — surface: panel in
// the canonical, never surface: both, so they never get a palette row; see
// PanelOnlyActions' own doc). It exists because the action list overlay is
// this client's `surface: action`, the ONE place FR-021's four
// panel_excluded ids (goToEntry, forgetReview, previewEditsStat,
// showCliLog) live, and every OTHER surface:both id besides — so the
// palette needs to know, for each of them, which situations enable it, the
// same question ControlsFor already answers for whichever subset also gets
// a body control.
var PaletteActions = []PaletteAction{
	{ID: "openEntry", Situations: []Situation{SituationReview, SituationFinishConflict}},
	{ID: "openChange", Situations: []Situation{SituationReview, SituationFinishConflict}},
	{ID: "showWhy", Situations: []Situation{SituationReview, SituationFinishConflict}},
	{ID: "next", Situations: []Situation{SituationReview}, RequiresNotBusy: true},
	{ID: "prev", Situations: []Situation{SituationReview}, RequiresNotBusy: true},
	{ID: "goToEntry", Situations: []Situation{SituationReview, SituationFinishConflict}, RequiresNotBusy: true},
	{ID: "refresh", Situations: allEightSituations},
	{ID: "installCli", Situations: []Situation{SituationCliMissing, SituationCliOutdated}},
	{ID: "startReview", Situations: []Situation{SituationNoReview, SituationFinishPending}, RequiresNotBusy: true},
	{ID: "setBase", Situations: allEightSituations, RequiresNotBusy: true},
	{ID: "setRemote", Situations: allEightSituations, RequiresNotBusy: true},
	{ID: "abortReview", Situations: []Situation{SituationReview, SituationFinishConflict}, RequiresNotBusy: true},
	{ID: "saveReview", Situations: []Situation{SituationReview}, RequiresNotBusy: true},
	{ID: "finishReview", Situations: []Situation{SituationReview}, RequiresNotBusy: true, RequiresNotReadonly: true},
	{ID: "undoFinish", Situations: []Situation{SituationFinishPending, SituationFinishConflict}, RequiresNotBusy: true},
	{ID: "resumeFinish", Situations: []Situation{SituationFinishConflict}, RequiresNotBusy: true},
	{ID: "cleanReview", Situations: allEightSituations, RequiresNotBusy: true},
	{ID: "forgetReview", Situations: allEightSituations, RequiresNotBusy: true},
	{ID: "previewEdits", Situations: []Situation{SituationReview, SituationFinishConflict}, RequiresNotBusy: true},
	{ID: "previewEditsStat", Situations: []Situation{SituationReview, SituationFinishConflict}, RequiresNotBusy: true},
	{ID: "compareReview", Situations: allEightSituations, RequiresNotBusy: true},
	{ID: "walkthroughInit", Situations: allEightSituations, RequiresNotBusy: true},
	{ID: "walkthroughBuild", Situations: allEightSituations, RequiresNotBusy: true},
	{ID: "showCliLog", Situations: allEightSituations},
}

// PaletteLabel names each PaletteActions entry for the overlay's own list —
// short and imperative, matching the body's own button labels where one
// already exists (usercopy.go) and inventing a plain new one only for the
// ids that never draw a body control at all (goToEntry, refresh,
// installCli, forgetReview, previewEdits, showCliLog): nothing here is
// declared by the canonical, so nothing needs to match the other three
// clients byte for byte — only be true. No entry for continueReview/
// discardInventory (PanelOnlyActions): they never appear in the palette,
// so nothing here would ever read it.
var PaletteLabel = map[string]string{
	"openEntry":        "Open file",
	"openChange":       "Open diff",
	"showWhy":          OpenInEditorLabel,
	"next":             NextEntryName,
	"prev":             PreviousEntryName,
	"goToEntry":        "Go to entry…",
	"refresh":          "Refresh",
	"installCli":       "Install or update the CLI",
	"startReview":      StartReviewLabel,
	"setBase":          ChangeBaseLabel,
	"setRemote":        ChangeRemoteLabel,
	"abortReview":      "Cancel review",
	"saveReview":       "Save for later",
	"finishReview":     "Finish review",
	"undoFinish":       UndoLabel,
	"resumeFinish":     ContinueLabel,
	"cleanReview":      DoneCleanUpLabel,
	"forgetReview":     "Forget a saved review…",
	"previewEdits":     "Preview edits",
	"previewEditsStat": "Preview edits (summary)",
	"compareReview":    CompareRevisionsLabel,
	"walkthroughInit":  WalkthroughInitLabel,
	"walkthroughBuild": WalkthroughBuildLabel,
	"showCliLog":       "Show CLI log",
}

// PaletteActionsFor returns the entries of PaletteActions enabled for the
// CURRENT panel state — situation, busy and readonly all matter, the exact
// three gates the canonical's own actions: block records — in PaletteActions'
// declared order (never re-sorted: a stable order is what makes the same
// filter text always land the cursor on the same row).
func PaletteActionsFor(situation Situation, busy, readonly bool) []PaletteAction {
	var out []PaletteAction
	for _, a := range PaletteActions {
		if !situationIn(a.Situations, situation) {
			continue
		}
		if a.RequiresNotBusy && busy {
			continue
		}
		if a.RequiresNotReadonly && readonly {
			continue
		}
		out = append(out, a)
	}
	return out
}

func situationIn(list []Situation, s Situation) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}
