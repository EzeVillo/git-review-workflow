package domain

// ControlID names a control drawn by the panel: either one of the 26
// product actions this client offers (actions.go) or a body-only control
// that has no row of its own to hang from (copyCliInstall, outOfRangeHelp,
// openSupport) — the same "not one of the 27" status as the five row-control
// maps below (contracts/client-product-surface.md § 7).
type ControlID string

// LayoutSituation is one of the 11 keys of `panel_layout:` in
// contracts/client-product-surface.yaml. "review-walk"/"review-step"/
// "review-whole" and "no-review-setup" are not Situation values — they are
// how the canonical splits the single "review" and "no-review" situations
// by mode / by whether a base is configured, and PanelModel's own Situation
// field never takes these values.
type LayoutSituation string

const (
	LayoutCliMissing     LayoutSituation = "cli-missing"
	LayoutCliOutdated    LayoutSituation = "cli-outdated"
	LayoutNoReviewSetup  LayoutSituation = "no-review-setup"
	LayoutNoReview       LayoutSituation = "no-review"
	LayoutReviewWalk     LayoutSituation = "review-walk"
	LayoutReviewStep     LayoutSituation = "review-step"
	LayoutReviewWhole    LayoutSituation = "review-whole"
	LayoutFinishPending  LayoutSituation = "finish-pending"
	LayoutFinishConflict LayoutSituation = "finish-conflict"
	LayoutOutOfRange     LayoutSituation = "out-of-range"
	LayoutError          LayoutSituation = "error"
)

// AllLayoutSituations is the 11 keys, in the order the canonical declares
// them — the same order layout_contract_test.go reads them off the YAML in.
var AllLayoutSituations = []LayoutSituation{
	LayoutCliMissing, LayoutCliOutdated, LayoutNoReviewSetup, LayoutNoReview,
	LayoutReviewWalk, LayoutReviewStep, LayoutReviewWhole,
	LayoutFinishPending, LayoutFinishConflict, LayoutOutOfRange, LayoutError,
}

// Layout is this client's mirror of `panel_layout:`: for each situation, the
// sequence of drawn control ids, in the order the canonical's blocks
// declare them. Only controls are recorded — prose, headings and other
// non-control blocks are not verifiable structure
// (contracts/client-product-surface.yaml `panel_unverified:`) and carry no
// entry here. A control that appears twice in the canonical (openSupport's
// two buttons; openChange's two `when:` branches in finish-conflict) is
// listed twice, in the order it is declared: this is a textual mirror of
// the YAML's blocks, not a simulation of which `when:` branch a given
// PanelModel would take.
var Layout = map[LayoutSituation][]ControlID{
	LayoutCliMissing:    {"copyCliInstall", "installCli"},
	LayoutCliOutdated:   {"copyCliInstall", "installCli"},
	LayoutNoReviewSetup: {"setBase", "setRemote"},
	LayoutNoReview: {
		"startReview",
		"walkthroughInit", "walkthroughBuild",
		"compareReview",
		"setBase", "setRemote",
		"openSupport", "openSupport",
	},
	// openAllChanges is not_in: [tui] (T006): the only control review-whole
	// would otherwise draw, so this client's mirror is empty on purpose —
	// not a gap. See ReviewWholeExcludesOpenAllChanges below, which is what
	// layout_contract_test.go actually asserts instead of an empty literal.
	LayoutReviewWhole:    {},
	LayoutReviewWalk:     {"showWhy", "openEntry", "openChange", "prev", "next"},
	LayoutReviewStep:     {"openChange", "prev", "next"},
	LayoutFinishPending:  {"cleanReview", "undoFinish"},
	LayoutFinishConflict: {"undoFinish", "resumeFinish", "showWhy", "openEntry", "openChange", "openChange"},
	LayoutOutOfRange:     {"outOfRangeHelp"},
	LayoutError:          {"outOfRangeHelp"},
}

// RowControlSpec is one entry of a row-control map: the label a control
// carries (empty for an icon-only control, which is identified by its
// accessible name instead) and whether choosing it opens a confirmation.
type RowControlSpec struct {
	Label    string // "" for an icon-only control
	Confirms bool
}

// InventoryControls mirrors `inventory_controls:` — per-row controls of the
// review/saved inventory in no-review. Not one of the 27 actions: without
// the row it draws in, neither has a subject.
var InventoryControls = map[ControlID]RowControlSpec{
	"continueReview":   {Label: "Continue", Confirms: true},
	"discardInventory": {Label: "Delete", Confirms: true},
}

// DraftControls mirrors `draft_controls:` — the four controls of a loose
// draft's row, always in this order and always all four present (only
// enabled/emphasis vary with progress).
var DraftControls = map[ControlID]RowControlSpec{
	"copyDraftPrompt": {Label: "Copy for agent", Confirms: false},
	"startFromDraft":  {Label: "Validate and start", Confirms: false},
	"openDraft":       {Confirms: false},
	"discardDraft":    {Confirms: true},
}

// GuideRowControls mirrors `guide_rows.controls:`.
var GuideRowControls = map[ControlID]RowControlSpec{
	"openGuide":    {Confirms: false},
	"createGuide":  {Label: "Create", Confirms: false},
	"discardGuide": {Confirms: true},
}

// WalkthroughRowControls mirrors `walkthrough_row.controls:`. walkthroughInit
// and walkthroughBuild are product actions (they live in Layout[NoReview]
// instead, inside the same row) and are not repeated here.
var WalkthroughRowControls = map[ControlID]RowControlSpec{
	"openWalkthrough":       {Confirms: false},
	"copyWalkthroughPrompt": {Label: "Copy for agent", Confirms: false},
}

// FixesRowControls mirrors `fixes_rows.controls:`.
var FixesRowControls = map[ControlID]RowControlSpec{
	"discardFixes":    {Confirms: true},
	"discardAllFixes": {Label: "Discard all", Confirms: true},
}

// FooterCapPercent is the hard ceiling on the footer's share of the panel's
// height (FR-022): the footer scrolls inside itself past this point rather
// than ever becoming the whole panel.
const FooterCapPercent = 55

// ScrollbarCount is fixed at 1: every open section asks for its own
// content's height and none of them scrolls internally — splitting the
// height across open sections would give each one its own bar, none able
// to show all of it (contracts/tui-surface.md § El pie).
const ScrollbarCount = 1

// RowHeaderOrder mirrors `row_shape.header:` — the fixed order of a row's
// header cells. The badge always closes the line so every section's badges
// land in the same column regardless of how many icons a given row carries
// before it.
var RowHeaderOrder = []string{"name", "progress?", "icons", "badge"}

// RowActionLayout is how a row's button area is laid out, mirroring
// `row_shape.actions:`.
type RowActionLayout string

const (
	// EvenColumns: exactly two labelled controls, laid out in two equal
	// columns — so one row's buttons line up with the row below it.
	EvenColumns RowActionLayout = "even_columns"
	// LeftAtLabelWidth: any other count of labelled controls (one, or
	// three) sized to their own label instead of stretched or squeezed to
	// match a two-column grid that does not apply to them.
	LeftAtLabelWidth RowActionLayout = "left_at_label_width"
)

// RowActionLayoutFor picks the layout for a row with n labelled controls,
// mirroring `row_shape.actions: {two_labelled: even_columns, otherwise:
// left_at_label_width}`.
func RowActionLayoutFor(labelledControlCount int) RowActionLayout {
	if labelledControlCount == 2 {
		return EvenColumns
	}
	return LeftAtLabelWidth
}
