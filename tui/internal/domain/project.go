package domain

import "strings"

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

	Why    string
	HasWhy bool

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
		m.HasWhy = in.HasWhy
		m.Why = in.Why

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
			if b, ok := currentBranch(in.Branches); ok && in.Situation == SituationFinishPending {
				m.PendingFinish = true
				m.FinishDestination = finishDestination(b)
			}
		}
		return m

	default:
		return m
	}
}
