package ui

import (
	"fmt"
	"io"
	"strconv"
	"strings"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/termenv"
)

// Viewport is everything about the terminal render.go needs beyond the
// PanelModel itself (data-model.md § Viewport): size and the two
// capabilities decided at startup. Never consulted from the domain — always
// passed in alongside the model, so View stays pure.
type Viewport struct {
	Cols, Rows int
	// Color: false means NO_COLOR / -nocolor — zero ANSI escape sequences in
	// the frame, not merely dimmer ones.
	Color bool
	// ASCII: true selects domain.IconVocabulary's ASCII glyph over Unicode.
	ASCII bool
}

// Rect is one control's drawn rectangle, 0-based rows/cols.
type Rect struct{ Row, Col, Width, Height int }

type hit struct {
	id      domain.ControlID
	variant string
	rect    Rect
}

// HitMap maps every drawn control to the rectangle it occupies (contracts/
// tui-surface.md § Mouse): a click resolves against real geometry, never
// guessed coordinates.
type HitMap struct{ hits []hit }

func (h *HitMap) add(id domain.ControlID, variant string, row, col, width int) {
	if width < 1 {
		width = 1
	}
	h.hits = append(h.hits, hit{id: id, variant: variant, rect: Rect{Row: row, Col: col, Width: width, Height: 1}})
}

// At returns the control (and disambiguating variant, if any) whose
// rectangle contains (col, row).
func (h HitMap) At(col, row int) (domain.ControlID, string, bool) {
	for i := len(h.hits) - 1; i >= 0; i-- {
		r := h.hits[i].rect
		if col >= r.Col && col < r.Col+r.Width && row >= r.Row && row < r.Row+r.Height {
			return h.hits[i].id, h.hits[i].variant, true
		}
	}
	return "", "", false
}

// ControlRow returns the row this control (its first drawn occurrence, or
// the matching variant) is on, and ok=false if it was never drawn. Used by
// keys.go's mouse resolution tests and by focus-follows-scroll bookkeeping.
func (h HitMap) ControlRow(id domain.ControlID, variant string) (int, bool) {
	for _, e := range h.hits {
		if e.id == id && e.variant == variant {
			return e.rect.Row, true
		}
	}
	return 0, false
}

// --- styling -----------------------------------------------------------------

// styles holds the handful of lipgloss styles render.go uses, all built off
// ONE renderer with an explicitly forced color profile — never the global
// default renderer, which auto-detects from os.Stdout and would make golden
// output depend on whatever terminal happens to run `go test`.
type styles struct {
	heading, primary, secondary, link, disabled, note, stderrText, keybar lipgloss.Style
}

func stylesFor(color bool) styles {
	profile := termenv.Ascii
	if color {
		profile = termenv.ANSI
	}
	r := lipgloss.NewRenderer(io.Discard)
	r.SetColorProfile(profile)
	return styles{
		heading:   r.NewStyle().Bold(true),
		primary:   r.NewStyle().Bold(true).Foreground(lipgloss.Color("2")),
		secondary: r.NewStyle().Foreground(lipgloss.Color("4")),
		// No Underline: lipgloss deliberately does not underline space runs
		// (some terminals render that oddly), which wraps every word in its
		// own escape sequence — correct, but far noisier than this client's
		// short link labels need. Color alone already distinguishes it.
		link:       r.NewStyle().Foreground(lipgloss.Color("6")),
		disabled:   r.NewStyle().Faint(true),
		note:       r.NewStyle().Faint(true),
		stderrText: r.NewStyle().Foreground(lipgloss.Color("1")),
		keybar:     r.NewStyle().Faint(true),
	}
}

// glyph picks the Unicode or ASCII form of one icon per vp.ASCII.
func glyph(vp Viewport, name domain.IconName) string {
	icon := domain.IconVocabulary[name]
	if vp.ASCII {
		return string(icon.ASCII)
	}
	return string(icon.Unicode)
}

// --- the builder ---------------------------------------------------------

type builder struct {
	vp    Viewport
	st    styles
	lines []string
	hm    HitMap
}

func newBuilder(vp Viewport) *builder {
	return &builder{vp: vp, st: stylesFor(vp.Color)}
}

func (b *builder) text(s string)    { b.lines = append(b.lines, s) }
func (b *builder) blank()           { b.lines = append(b.lines, "") }
func (b *builder) heading(s string) { b.lines = append(b.lines, b.st.heading.Render(s)) }

// note draws PanelModel.Note — a single derived, presentation-only line —
// and does nothing at all when there is none, rather than emitting a styled
// empty line (an escape-sequence pair around nothing is still a stray line
// no terminal collapses on its own).
func (b *builder) note(s string) {
	if s == "" {
		return
	}
	b.lines = append(b.lines, b.st.note.Render(s))
}

// button draws one labelled control on its own line and records its
// rectangle. Phase 4 stacks every control vertically, one per line — the
// two-column button grid row_shape.go describes is a rendering refinement
// left to whichever later phase actually needs two controls sharing a row
// (none of Phase 4's situations do: every situation here draws at most one
// labelled control that isn't already naturally alone, and prev/next are
// icon-only).
func (b *builder) button(id domain.ControlID, variant, label string, style lipgloss.Style, enabled bool) {
	s := style
	prefix := "[ "
	suffix := " ]"
	if !enabled {
		s = b.st.disabled
	}
	rendered := prefix + s.Render(label) + suffix
	row := len(b.lines)
	b.lines = append(b.lines, rendered)
	b.hm.add(id, variant, row, 0, lipgloss.Width(rendered))
}

// iconButton draws an icon-only control (prev/next) with its accessible
// name as a trailing hint — there is no visible label to click on top of,
// so the WHOLE line is the hit target.
func (b *builder) iconButton(id domain.ControlID, icon domain.IconName, name string, style lipgloss.Style, enabled bool) {
	s := style
	if !enabled {
		s = b.st.disabled
	}
	rendered := "[" + glyph(b.vp, icon) + "] " + s.Render(name)
	row := len(b.lines)
	b.lines = append(b.lines, rendered)
	b.hm.add(id, "", row, 0, lipgloss.Width(rendered))
}

func (b *builder) stderrBlock(stderr string) {
	if stderr == "" {
		return
	}
	b.blank()
	for _, line := range strings.Split(strings.TrimRight(stderr, "\n"), "\n") {
		b.lines = append(b.lines, b.st.stderrText.Render(line))
	}
}

// frame joins the built lines into the final string, word-wrapping any line
// that overflows vp.Cols (a long paragraph, mainly) BEFORE applying the row
// cap — wrapping first is what keeps "no line overflows" from also meaning
// "long sentences lose their tail": a truncated MaxWidth() cut is a byte
// count away from cutting mid-glyph the moment a wide rune shows up, and it
// throws away content a reader never gets back. Wrapping can only ever
// ADD lines, so it has to happen before vp.Rows trims the frame down.
func (b *builder) frame() string {
	lines := b.lines
	if b.vp.Cols > 0 {
		var wrapped []string
		for _, l := range lines {
			wrapped = append(wrapped, wrapLine(l, b.vp.Cols)...)
		}
		lines = wrapped
	}
	if b.vp.Rows > 0 && len(lines) > b.vp.Rows {
		lines = lines[:b.vp.Rows]
	}
	return strings.Join(lines, "\n")
}

func wrapLine(l string, cols int) []string {
	if lipgloss.Width(l) <= cols {
		return []string{l}
	}
	return strings.Split(lipgloss.NewStyle().Width(cols).Render(l), "\n")
}

func interpolate(template string, pairs ...string) string {
	out := template
	for i := 0; i+1 < len(pairs); i += 2 {
		out = strings.ReplaceAll(out, pairs[i], pairs[i+1])
	}
	return out
}

// --- View ------------------------------------------------------------------

// View renders m at vp, returning the frame and the HitMap every drawn
// control left behind. Pure: no I/O, no package-level mutable state besides
// the deterministic, explicitly-profiled styles built fresh each call.
func View(m domain.PanelModel, vp Viewport) (string, HitMap) {
	b := newBuilder(vp)

	if m.Situation == domain.SituationWaiting || m.Situation == "" {
		b.text(domain.WaitingText)
		return b.frame(), b.hm
	}

	switch domain.LayoutSituationFor(m) {
	case domain.LayoutCliMissing:
		renderCliInstall(b, domain.CliMissingTitle, domain.NpmInstallHint, domain.NpmInstallCmd, m.Stderr)
	case domain.LayoutCliOutdated:
		renderCliInstall(b, domain.CliOutdatedTitle, domain.NpmUpdateHint, domain.NpmUpdateCmd, m.Stderr)
	case domain.LayoutNoReviewSetup:
		renderNoReviewSetup(b, m)
	case domain.LayoutNoReview:
		renderNoReview(b, m)
	case domain.LayoutReviewWalk:
		renderReviewWalk(b, m)
	case domain.LayoutReviewStep:
		renderReviewStep(b, m)
	case domain.LayoutReviewWhole:
		renderReviewWhole(b, m)
	case domain.LayoutFinishPending:
		renderFinishPending(b, m)
	case domain.LayoutFinishConflict:
		renderFinishConflict(b, m)
	case domain.LayoutOutOfRange:
		renderOutOfRangeOrError(b, m, domain.OutOfRangeMessage)
	case domain.LayoutError:
		renderOutOfRangeOrError(b, m, domain.ErrorMessage)
	}

	b.statusLine(m.StatusLine)
	b.keyBar(m)
	return b.frame(), b.hm
}

// statusLine draws PanelModel.StatusLine (T074): what a toast would say in
// the other three clients, and empty exactly when there is nothing to say
// — "en un pane no hay toasts: el panel ES la superficie" (contracts/
// tui-surface.md). None of golden_test.go's fixtures ever set it, so this
// never touches a golden file; a mutation's own outcome is the only source.
func (b *builder) statusLine(s string) {
	if s == "" {
		return
	}
	b.blank()
	b.lines = append(b.lines, b.st.note.Render(s))
}

// keyBar draws the footer key bar (T048) from the SAME table KeyBarFor
// resolves keys against — a key shown here always resolves, and one that
// resolves is always shown, by construction.
func (b *builder) keyBar(m domain.PanelModel) {
	items := KeyBarFor(m)
	if len(items) == 0 {
		return
	}
	parts := make([]string, len(items))
	for i, it := range items {
		parts[i] = b.st.keybar.Render(it.Key) + ":" + it.Label
	}
	b.blank()
	b.text(strings.Join(parts, "  "))
}

func renderCliInstall(b *builder, title, hint, cmd, stderr string) {
	b.text(interpolate(title, "{min}", domain.MinCLIVersion))
	b.text(hint)
	b.blank()
	line := "  " + cmd
	row := len(b.lines)
	b.lines = append(b.lines, line)
	b.hm.add("copyCliInstall", "", row, 0, lipgloss.Width(line))
	b.blank()
	b.text(domain.AfterInstall)
	b.blank()
	b.button("installCli", "", domain.OtherInstallOptions, b.st.link, true)
	b.stderrBlock(stderr)
}

func renderNoReviewSetup(b *builder, m domain.PanelModel) {
	b.text(domain.SetupQuestion)
	b.button("setBase", "", domain.ChooseBranchLabel, b.st.primary, true)
	b.blank()
	b.text(domain.ReviewsCompareAgainstNote)
	b.text(interpolate(domain.RemoteOptionalLine, "{remote}", m.ConfiguredRemote))
	b.button("setRemote", "", domain.ChangeRemoteLabel, b.st.secondary, true)
}

func renderNoReview(b *builder, m domain.PanelModel) {
	b.text(domain.NoActiveReviewNote)
	b.button("startReview", "", domain.StartReviewLabel, b.st.primary, true)
	b.blank()

	b.heading(domain.WalkthroughSectionTitle)
	b.button("walkthroughInit", "", domain.WalkthroughInitLabel, b.st.secondary, true)
	b.button("walkthroughBuild", "", domain.WalkthroughBuildLabel, b.st.secondary, true)
	b.blank()

	b.heading(domain.CompareSectionTitle)
	b.button("compareReview", "", domain.CompareRevisionsLabel, b.st.secondary, true)
	b.blank()

	b.heading(domain.SettingsSectionTitle)
	b.text(interpolate(domain.BaseLine, "{base}", m.ConfiguredBase))
	b.button("setBase", "", domain.ChangeBaseLabel, b.st.secondary, true)
	b.text(interpolate(domain.RemoteLine, "{remote}", m.ConfiguredRemote))
	b.button("setRemote", "", domain.ChangeRemoteLabel, b.st.secondary, true)
	b.blank()

	b.heading(domain.SupportSectionTitle)
	b.button("openSupport", "star", domain.StarOnGitHubLabel, b.st.secondary, true)
	b.button("openSupport", "bug", domain.ReportABugLabel, b.st.secondary, true)
}

func identityLine(m domain.PanelModel) string {
	return m.Branch
}

func renderReviewWalk(b *builder, m domain.PanelModel) {
	b.heading(identityLine(m))
	b.note(m.Note)
	b.text(fmt.Sprintf("Entry %d/%d: %s", m.Position, m.Total, m.CurrentPath.Display))
	if m.HasWhy {
		b.blank()
		b.text(m.Why)
		b.button("showWhy", "", domain.OpenInEditorLabel, b.st.link, true)
	}
	b.blank()
	b.button("openEntry", "", domain.FileLabel, b.st.secondary, true)
	b.button("openChange", "", domain.DiffLabel, b.st.secondary, true)
	b.blank()
	b.iconButton("prev", domain.IconPrev, domain.PreviousEntryName, b.st.secondary, !m.AtFirst)
	b.iconButton("next", domain.IconNext, domain.NextEntryName, b.st.secondary, !m.AtLast)
}

func renderReviewStep(b *builder, m domain.PanelModel) {
	b.heading(identityLine(m))
	b.note(m.Note)
	b.text(fmt.Sprintf("Entry %d/%d: %s", m.Position, m.Total, m.CurrentSHA))
	b.blank()
	b.button("openChange", "", domain.DiffLabel, b.st.secondary, true)
	b.blank()
	b.heading(interpolate(domain.FilesInCommitHeading, "{n}", strconv.Itoa(m.EntryCount)))
	for _, f := range nonEmptyLines(m.Files) {
		b.text("  " + f)
	}
	b.blank()
	b.iconButton("prev", domain.IconPrev, domain.PreviousEntryName, b.st.secondary, !m.AtFirst)
	b.iconButton("next", domain.IconNext, domain.NextEntryName, b.st.secondary, !m.AtLast)
}

func renderReviewWhole(b *builder, m domain.PanelModel) {
	b.heading(identityLine(m))
	b.note(m.Note)
	b.heading(interpolate(domain.FilesInReviewHeading, "{n}", strconv.Itoa(m.Total)))
	// openAllChanges is not_in: [tui] (T006) — no control drawn here.
	for _, f := range nonEmptyLines(m.Files) {
		b.text("  " + f)
	}
}

func renderFinishPending(b *builder, m domain.PanelModel) {
	b.text(interpolate(domain.FinishPendingLine1, "{destination}", m.FinishDestination))
	b.text(domain.FinishPendingLine2)
	b.blank()
	b.button("cleanReview", "", domain.DoneCleanUpLabel, b.st.primary, true)
	b.button("undoFinish", "", domain.UndoLabel, b.st.secondary, true)
}

func renderFinishConflict(b *builder, m domain.PanelModel) {
	b.text(domain.FinishConflictBanner)
	b.button("undoFinish", "", domain.UndoLabel, b.st.secondary, true)
	b.button("resumeFinish", "", domain.ContinueLabel, b.st.secondary, true)
	b.blank()
	b.heading(identityLine(m))
	b.note(m.Note)

	if m.Mode == domain.ModeWalk {
		if m.HasWhy {
			b.text(m.Why)
			b.button("showWhy", "", domain.OpenInEditorLabel, b.st.link, true)
		}
		b.button("openEntry", "", domain.FileLabel, b.st.secondary, true)
		b.button("openChange", "", domain.DiffLabel, b.st.secondary, true)
		return
	}

	b.button("openChange", "", domain.DiffLabel, b.st.secondary, true)
	if m.Mode == domain.ModeStep {
		b.heading(interpolate(domain.FilesInCommitHeading, "{n}", strconv.Itoa(m.EntryCount)))
		for _, f := range nonEmptyLines(m.Files) {
			b.text("  " + f)
		}
	}
}

func renderOutOfRangeOrError(b *builder, m domain.PanelModel, message string) {
	b.text(message)
	b.button("outOfRangeHelp", "", domain.HowToFixItLabel, b.st.primary, true)
	b.stderrBlock(m.Stderr)
}

func nonEmptyLines(s string) []string {
	if s == "" {
		return nil
	}
	return strings.Split(s, "\n")
}
