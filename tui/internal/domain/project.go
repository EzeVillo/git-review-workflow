package domain

import (
	"strconv"
	"strings"
)

// ProjectInput is everything one read cycle produced, before it becomes a
// PanelModel: the derived Situation, the raw parses `status`/`list`/`config`
// returned (each guarded by its own Has* flag, since `list`/`config` are
// only ever invoked for no-review/finish-pending — contracts/cli-
// invocation.md § Lecturas de estado), plus the two pieces of state that are
// NOT porcelain at all (MouseEnabled, Busy) and the raw stderr a failure
// situation shows.
//
// Phase 4 populates every CORE field this carries into PanelModel: the
// identity/cursor/entry fields a review-shaped situation needs, and the two
// config-derived fields no-review-setup's own split depends on
// (NoBaseConfigured, used by LayoutSituationFor). It deliberately leaves
// every FOOTER row (WalkthroughRow, the two guide rows, both draft-row
// groups, FixesRows, InventoryRows) at its zero value: those are drawn by
// their own five row-control maps (layout.go), which is Phase 7's stated
// scope (tasks.md T075-T080, "El pie y los cinco mapas de fila") — the data
// to fill them is already sitting in Config (drafts, guides, walkthrough)
// and List (fixes), parsed since Phase 3, and Phase 7 is expected to read it
// from here rather than re-parse anything.
type ProjectInput struct {
	Situation Situation

	Status    PorcelainResult
	HasStatus bool

	Branches []BranchRecord
	Fixes    []FixesRecord
	HasList  bool

	Config    ConfigPorcelainResult
	HasConfig bool

	Why      string
	WhyState WhyState

	MouseEnabled bool
	Busy         bool
	Stderr       string
	// StatusLine: the UI layer's own sticky "toast" text (PanelModel.
	// StatusLine's own doc) — not porcelain, carried through unchanged.
	StatusLine string
}

// currentBranch returns the `list --porcelain` row marked current, if any —
// the row a no-review/finish-pending read describes THIS branch with, since
// `status --porcelain` itself carries no `state` record once the review is
// gone (ParsePorcelain requires one to return ok=true).
func currentBranch(branches []BranchRecord) (BranchRecord, bool) {
	for _, b := range branches {
		if b.Current {
			return b, true
		}
	}
	return BranchRecord{}, false
}

// PendingFinish returns the unresolved finish reported by list porcelain. A
// finish is repository state: list retains its record on review/<source> even
// after HEAD moves to review-fixes/<source> or elsewhere, so checkout does not
// affect whether the panel must offer its undo/clean flow.
func PendingFinish(branches []BranchRecord) (BranchRecord, bool) {
	for _, branch := range branches {
		if branch.Finish != nil && branch.Finish.State == "pending" {
			return branch, true
		}
	}
	return BranchRecord{}, false
}

// finishDestination names where a finish-pending branch's edits landed:
// review-fixes/<source> normally, or the source branch itself when the
// finish ran --onto-source (list --porcelain's `onto` bit).
func finishDestination(b BranchRecord) string {
	source := SourceOf(b)
	if b.Finish != nil && b.Finish.Onto {
		return source
	}
	return "review-fixes/" + source
}

// joinDisplayPaths newline-joins a slice of entries' DISPLAY form — never
// Raw, which would send a porcelain-quoted string to the screen
// (data-model.md § PathRef).
func joinDisplayPaths(entries []EntryRecord) string {
	lines := make([]string, len(entries))
	for i, e := range entries {
		lines[i] = e.Path.Display
	}
	return strings.Join(lines, "\n")
}

// entryPickerRows packs goToEntry's own list (T086) from the SAME `entry`
// records status --porcelain already reported (in.Status.Entries) — never
// re-derived from Files, which in step mode is the CURRENT commit's file
// inventory, a different list entirely. subjects, when the CLI reports them
// (step mode only), give a picked commit a human label instead of a bare
// SHA; every other mode's raw/display already IS the human label (a path).
func entryPickerRows(mode ReviewMode, entries []EntryRecord, subjects map[int]string) string {
	rows := make([]string, len(entries))
	for i, e := range entries {
		var raw, display string
		if mode == ModeStep {
			raw = e.SHA
			display = e.SHA
			if s, ok := subjects[e.Position]; ok && s != "" {
				display = s
			}
		} else {
			raw = e.Path.Raw
			display = e.Path.Display
		}
		rows[i] = FooterField(strconv.Itoa(e.Position), raw, display)
	}
	return strings.Join(rows, "\n")
}

// Project turns one read cycle's parsed pieces into the flat, comparable
// PanelModel render.go draws. It is the ONE place FR-023 is enforced: for a
// review-shaped situation this function never touches the footer fields at
// all, so PanelModel simply never carries a tools_section while a review is
// open — it is not that render.go chooses to skip them.
func Project(in ProjectInput) PanelModel {
	m := PanelModel{
		Situation:    in.Situation,
		Busy:         in.Busy,
		MouseEnabled: in.MouseEnabled,
		Stderr:       in.Stderr,
		StatusLine:   in.StatusLine,
	}

	switch in.Situation {
	case SituationCliMissing, SituationCliOutdated, SituationOutOfRange, SituationError:
		return m

	case SituationReview, SituationFinishConflict:
		if !in.HasStatus {
			return m
		}
		st := in.Status.State
		m.RepoLabel = st.Branch
		m.Mode = st.Mode
		m.Branch = st.Branch
		m.Source = st.Source
		m.Tip = st.Tip
		m.Readonly = in.Status.Readonly
		m.KeysOnly = in.Status.KeysOnly
		m.WhyState = in.WhyState
		m.Why = in.Why

		// Degraded (T094): the walkthrough this review asked for could not
		// be applied (broken, stale, or otherwise unusable), so the CLI
		// fell back to whole on its own — a walkthrough never fails a
		// review, it degrades it, with a note (CLAUDE.md § Walk y
		// walkthrough). st.Walkthrough carries this for BOTH whole and walk
		// modes (data-model.md § StateRecord): a whole-mode review can
		// still report "degraded" when THAT is how it got there.
		if st.Walkthrough == WalkthroughDegraded {
			m.Degraded = true
			m.Note = WalkthroughDegradedToWholeNote
		}

		m.EntryPickerRows = entryPickerRows(st.Mode, in.Status.Entries, in.Status.Subjects)

		switch st.Mode {
		case ModeWhole:
			m.Base = in.Status.Base
			m.HasBase = m.Base != ""
			m.Total = len(in.Status.Entries)
			m.Files = joinDisplayPaths(in.Status.Entries)
		case ModeStep:
			m.Position = st.Position
			m.Total = st.Total
			m.AtFirst = st.Position <= 1
			m.AtLast = st.Position >= st.Total
			m.HasCurrent = st.CurrentSHA != ""
			m.CurrentSHA = st.CurrentSHA
			m.EntryCount = len(in.Status.Files)
			m.Files = joinDisplayPaths(in.Status.Files)
		case ModeWalk:
			m.Position = st.Position
			m.Total = st.Total
			m.AtFirst = st.Position <= 1
			m.AtLast = st.Position >= st.Total
			m.HasCurrent = st.CurrentPath.Display != ""
			m.CurrentPath = st.CurrentPath
		}

		if in.Situation == SituationFinishConflict && in.Status.Finish != nil {
			m.FinishConflict = true
		}
		return m

	case SituationNoReview, SituationFinishPending:
		if in.HasConfig {
			m.NoBaseConfigured = !in.Config.Config.HasBase
			m.ConfiguredBase = in.Config.Config.Base
			m.ConfiguredRemote = in.Config.Config.Remote
		} else {
			// No config read at all (list/config both failed, or this read
			// never got that far): nothing to offer a base picker against,
			// so the safer of the two screens is the setup one.
			m.NoBaseConfigured = true
		}
		if in.HasList {
			if b, ok := PendingFinish(in.Branches); ok && in.Situation == SituationFinishPending {
				m.PendingFinish = true
				m.FinishDestination = finishDestination(b)
				// Source: the bare branch name, reused from the same field
				// SituationReview/SituationFinishConflict populate from
				// `status`'s own `source` field — cleanReview's "Done, clean
				// up" needs it bare (clean --keep-fixes <source>), which
				// FinishDestination is not: it is already "<source>" or
				// "review-fixes/<source>" depending on --onto-source.
				m.Source = SourceOf(b)
			}
		}
		// The footer (Phase 7, T075-T083): `no-review` only, same as FR-023
		// for a review situation — finish-pending's own panel_layout: has no
		// tools_section at all, so there is nothing here for it to name.
		if in.Situation == SituationNoReview {
			projectFooter(&m, in)
		}
		return m

	default:
		return m
	}
}

// --- the footer: walkthrough row, guide rows, draft rows, fixes rows,
// inventory rows (Phase 7, T075-T083) ---------------------------------------
//
// Every helper below reads straight off in.Config/in.Fixes/in.Branches —
// parsed since Phase 3 (porcelain.go) — and writes into m's flat fields
// using FooterField (rowdata.go) for anything list-shaped, never a slice:
// PanelModel's own comparability depends on it (panelmodel_test.go).

// projectFooter fills every no-review footer field. Guarded per source
// (HasConfig / HasList) rather than all-or-nothing: a read that got `list`
// but not `config` (or vice versa) still projects whichever half it has,
// the same defensive shape the rest of this function already uses for
// NoBaseConfigured above.
func projectFooter(m *PanelModel, in ProjectInput) {
	if in.HasConfig {
		projectWalkthroughRow(m, in.Config.Walkthrough)
		projectGuideRows(m, in.Config.Guides)
		projectDraftRows(m, in.Config.Drafts)
	}
	if in.HasList {
		projectFixesRows(m, in.Fixes)
		projectInventoryRows(m, in.Branches)
	}
}

// projectWalkthroughRow: the row is either there or it is not — an older
// CLI that never emits the `walkthrough` record at all leaves
// HasWalkthroughRow false, the same "the record's absence is what turns the
// row off" shape the two guide rows below use for HasGuideRows. A CLI that
// DOES emit it always reports one of the five states (never omits the
// record just because the file itself is absent — CLAUDE.md: the absence is
// reported, not implied by silence), so HasWalkthroughRow is not a proxy
// for "the file exists".
func projectWalkthroughRow(m *PanelModel, w *WalkthroughRecord) {
	if w == nil {
		return
	}
	m.HasWalkthroughRow = true
	if w.HasBranch {
		m.WalkthroughRow = w.Branch
	}
	m.WalkthroughState = w.State
	m.WalkthroughAnnotated = w.Annotated
	m.WalkthroughTotal = w.Total
}

// projectGuideRows: the CLI always emits BOTH `guide` records together
// (emit_guide_records in bin/git-review-lib.sh), so HasGuideRows only ever
// turns on once — this loop does not assume that order, only that kind
// disambiguates which of the two rows a record fills.
func projectGuideRows(m *PanelModel, guides []GuideRecord) {
	for _, g := range guides {
		switch g.Kind {
		case GuideTeam:
			m.HasGuideRows = true
			m.TeamGuideRow = g.Path
			m.TeamGuideState = g.State
		case GuideOwn:
			m.HasGuideRows = true
			m.OwnGuideRow = g.Path
			m.OwnGuideState = g.State
		}
	}
}

// draftRow packs one DraftRecord into a FooterField row shared by both
// FreshDraftRows and SpentDraftRows: a spent draft only ever draws its two
// icon controls (draft_controls' own comment), but keeping the same six
// cells for both lists means one decoder serves both, never two slightly
// different formats a future reader has to keep straight.
func draftRow(d DraftRecord) string {
	return FooterField(d.Src, d.Path, string(d.Source), string(d.Range), strconv.Itoa(d.Annotated), strconv.Itoa(d.Total))
}

// projectDraftRows splits the CLI's own draft list into fresh/spent by
// State — never reordering or filtering beyond that split, so within each
// list the CLI's own order survives (mirrors panelModel.ts's toPanelDrafts).
func projectDraftRows(m *PanelModel, drafts []DraftRecord) {
	var fresh, spent []string
	for _, d := range drafts {
		if d.State == DraftReviewed {
			spent = append(spent, draftRow(d))
		} else {
			fresh = append(fresh, draftRow(d))
		}
	}
	m.FreshDraftRows = strings.Join(fresh, "\n")
	m.FreshDraftCount = len(fresh)
	m.SpentDraftRows = strings.Join(spent, "\n")
	m.SpentDraftCount = len(spent)
}

func projectFixesRows(m *PanelModel, fixes []FixesRecord) {
	rows := make([]string, len(fixes))
	for i, f := range fixes {
		rows[i] = FooterField(f.Name, string(f.State), boolCell(f.Session), boolCell(f.Current))
	}
	m.FixesRows = strings.Join(rows, "\n")
	m.FixesCount = len(fixes)
}

// FixesSourceOf strips a review-fixes/* branch's own prefix, the bare
// source `clean --fixes-only` expects on a single-row discardFixes — kept
// apart from sourceOf (review/review-saved) because the two namespaces
// never overlap on one branch, and folding them into one function would let
// a mistyped review-saved/x quietly fall through unmatched instead of
// naming a branch this row could never have named.
func FixesSourceOf(name string) string {
	return strings.TrimPrefix(name, "review-fixes/")
}

// projectInventoryRows lists EVERY review/review-saved branch (list
// --porcelain's own universe), including the ones with neither Continue nor
// Delete: an active review on another branch is still a row this repository
// has, and dropping it would leave the inventory silently short one entry.
// resumable mirrors panelModel.ts's toPanelReviews: a saved review stops
// being resumable once ANOTHER branch already has it active (the exact
// case `git review continue` itself refuses with "is already active"), so
// the check needs the whole list, never one row in isolation.
func projectInventoryRows(m *PanelModel, branches []BranchRecord) {
	if len(branches) == 0 {
		return
	}
	active := map[string]bool{}
	for _, b := range branches {
		if !b.Saved {
			active[sourceOf(b.Name)] = true
		}
	}
	rows := make([]string, len(branches))
	for i, b := range branches {
		resumable := b.Saved && !b.Orphan && !active[sourceOf(b.Name)]
		rows[i] = FooterField(b.Name, boolCell(b.Saved), boolCell(b.Orphan), boolCell(b.Current), boolCell(resumable), inventoryStatus(b))
	}
	m.InventoryRows = strings.Join(rows, "\n")
	m.InventoryCount = len(branches)
	m.HasReviews = true
}

// inventoryStatus mirrors panelHtml.ts's reviewMeta (the mode/position pair
// list already recorded — never re-derived, contracts/list-porcelain.md)
// folded together with inventoryHelpTitle (why a row with neither Continue
// nor Delete has no button): a finish waiting to be cleaned or stuck mid-
// conflict is the one thing worth naming over the plain mode/position pair,
// an orphan branch has no metadata left to report at all, and a plain
// active review on another branch gets the generic "still active" note
// that used to live only behind a "?" badge's hover text.
func inventoryStatus(b BranchRecord) string {
	if b.Finish != nil {
		source := sourceOf(b.Name)
		if b.Finish.State == "pending" {
			dest := source
			if !b.Finish.Onto {
				dest = "review-fixes/" + source
			}
			return "Finish waiting on " + dest + " -- use Undo above."
		}
		return "Finish stopped mid-conflict -- switch to this branch to resolve or undo."
	}
	if b.Orphan {
		return "details are gone"
	}
	if b.HasPositionTotal {
		return string(b.Mode) + " . " + strconv.Itoa(b.Position) + "/" + strconv.Itoa(b.Total)
	}
	if b.Saved {
		return string(b.Mode)
	}
	return "Still active -- switch to this branch to work on it."
}
