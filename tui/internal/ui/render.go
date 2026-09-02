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

// controlTarget is the concrete body control the presentation layer marks.
// Variant matters for repeated row actions such as the two Support links.
type controlTarget struct {
	id      domain.ControlID
	variant string
}

// renderState is ephemeral UI state. It deliberately stays outside
// domain.PanelModel: porcelain decides product state; focus, hover, and a
// terminal viewport offset belong solely to this client presentation.
type renderState struct {
	focus, hover *controlTarget
	footerOffset int
}

type renderMetrics struct {
	footerOffset int
	footerMax    int
}

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

// Rect returns this control's own drawn rectangle, ok=false if it was
// never drawn — the mouse reachability test's own need (T091): a row that
// carries TWO controls side by side (a draft's copyDraftPrompt and
// startFromDraft, say) puts them at the SAME row but different columns, so
// a synthetic click needs the real column, not just the row.
func (h HitMap) Rect(id domain.ControlID, variant string) (Rect, bool) {
	for _, e := range h.hits {
		if e.id == id && e.variant == variant {
			return e.rect, true
		}
	}
	return Rect{}, false
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
	vp          Viewport
	st          styles
	state       renderState
	lines       []string
	hm          HitMap
	metrics     renderMetrics
	tailReserve int
}

func newBuilder(vp Viewport, state renderState) *builder {
	return &builder{vp: vp, st: stylesFor(vp.Color), state: state}
}

func (b *builder) text(s string)    { b.lines = append(b.lines, s) }
func (b *builder) blank()           { b.lines = append(b.lines, "") }
func (b *builder) heading(s string) { b.lines = append(b.lines, b.st.heading.Render(s)) }

// marker is deliberately textual rather than color-only: NO_COLOR and the
// ASCII fallback must leave keyboard focus just as legible as a full-color
// terminal. Hover is distinct but secondary to focus when both name a row.
func (b *builder) marker(targets ...controlTarget) string {
	for _, target := range targets {
		if b.state.focus != nil && *b.state.focus == target {
			return "> "
		}
	}
	for _, target := range targets {
		if b.state.hover != nil && *b.state.hover == target {
			return "~ "
		}
	}
	if b.state.focus == nil && b.state.hover == nil {
		return ""
	}
	return "  "
}

func (b *builder) controlPrefix(target controlTarget) string {
	if b.state.focus != nil && *b.state.focus == target {
		return ">"
	}
	if b.state.hover != nil && *b.state.hover == target {
		return "~"
	}
	if b.state.focus == nil && b.state.hover == nil {
		return ""
	}
	return " "
}

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
	rendered := b.marker(controlTarget{id: id, variant: variant}) + prefix + s.Render(label) + suffix
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
	rendered := b.marker(controlTarget{id: id}) + "[" + glyph(b.vp, icon) + "] " + s.Render(name)
	row := len(b.lines)
	b.lines = append(b.lines, rendered)
	b.hm.add(id, "", row, 0, lipgloss.Width(rendered))
}

// rowButton is one entry of buttonRow/iconRow: a control drawn as part of a
// multi-control LINE (a footer row's icon pair, or its two even-columned
// labelled actions — row_shape.actions: two_labelled: even_columns) rather
// than on its own line the way button()/iconButton() draw a situation's
// fixed body controls.
type rowButton struct {
	id      domain.ControlID
	variant string
	label   string
	style   lipgloss.Style
	enabled bool
}

// buttonRow draws N labelled controls on ONE line, each keeping its own hit
// rectangle — the footer's row_shape.actions layout (even columns for
// exactly two, left-at-label-width otherwise; this renderer treats both the
// same way, since a fixed terminal font has no "stretch to fill" concept to
// tell them apart visually).
func (b *builder) buttonRow(btns ...rowButton) {
	if len(btns) == 0 {
		return
	}
	var line string
	cols := make([]int, len(btns))
	widths := make([]int, len(btns))
	for i, bt := range btns {
		s := bt.style
		if !bt.enabled {
			s = b.st.disabled
		}
		part := b.controlPrefix(controlTarget{id: bt.id, variant: bt.variant}) + "[ " + s.Render(bt.label) + " ]"
		if i > 0 {
			line += "  "
		}
		cols[i] = lipgloss.Width(line)
		widths[i] = lipgloss.Width(part)
		line += part
	}
	row := len(b.lines)
	b.lines = append(b.lines, line)
	for i, bt := range btns {
		b.hm.add(bt.id, bt.variant, row, cols[i], widths[i])
	}
}

// rowIcon is one entry of iconRow.
type rowIcon struct {
	id      domain.ControlID
	variant string
	icon    domain.IconName
	hint    string // short trailing word ("open", "discard") — not the full accessible name, which is a screen-reader affordance this renderer has no equivalent surface for
	enabled bool
}

// iconRow draws N icon-only controls on ONE line, pegged together the way
// row_shape.header describes ("icons" sit as one group before the badge).
func (b *builder) iconRow(icons ...rowIcon) {
	if len(icons) == 0 {
		return
	}
	var line string
	cols := make([]int, len(icons))
	widths := make([]int, len(icons))
	for i, ic := range icons {
		s := b.st.secondary
		if !ic.enabled {
			s = b.st.disabled
		}
		part := b.controlPrefix(controlTarget{id: ic.id, variant: ic.variant}) + "[" + glyph(b.vp, ic.icon) + "] " + s.Render(ic.hint)
		if i > 0 {
			line += "  "
		}
		cols[i] = lipgloss.Width(line)
		widths[i] = lipgloss.Width(part)
		line += part
	}
	row := len(b.lines)
	b.lines = append(b.lines, line)
	for i, ic := range icons {
		b.hm.add(ic.id, ic.variant, row, cols[i], widths[i])
	}
}

// rowHeader draws one footer row's name/progress/badge line — row_shape.
// header's own order, minus icons: those are drawn separately by iconRow
// right below, on their own line, so each keeps a clean hit rectangle
// rather than one spliced into the middle of a longer styled string.
func (b *builder) rowHeader(name, progress, badge string) {
	line := name
	if progress != "" {
		line += "  " + progress
	}
	if badge != "" {
		line += "  " + b.st.note.Render("("+badge+")")
	}
	b.text(line)
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
	frame, hm, _ := viewWithState(m, vp, renderState{})
	return frame, hm
}

// viewWithState is the model-facing panel renderer. View remains the pure,
// state-free API used by golden/domain tests; this narrow sibling adds only
// presentation state that a real terminal interaction owns.
func viewWithState(m domain.PanelModel, vp Viewport, state renderState) (string, HitMap, renderMetrics) {
	b := newBuilder(vp, state)

	if m.Situation == domain.SituationWaiting || m.Situation == "" {
		b.text(domain.WaitingText)
		return b.frame(), b.hm, b.metrics
	}
	tail := fixedTailLines(m, vp, b.st)
	b.tailReserve = len(tail)

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

	return b.frameWithTail(tail), b.hm, b.metrics
}

func fixedTailLines(m domain.PanelModel, vp Viewport, st styles) []string {
	var raw []string
	if m.StatusLine != "" {
		raw = append(raw, st.note.Render(m.StatusLine))
	}
	raw = append(raw, "")
	items := KeyBarFor(m)
	parts := make([]string, len(items))
	for i, it := range items {
		parts[i] = st.keybar.Render(it.Key) + ":" + it.Label
	}
	raw = append(raw, strings.Join(parts, "  "))
	if vp.Cols <= 0 {
		return raw
	}
	var lines []string
	for _, line := range raw {
		lines = append(lines, wrapLine(line, vp.Cols)...)
	}
	return lines
}

func (b *builder) frameWithTail(tail []string) string {
	body := b.lines
	if b.vp.Cols > 0 {
		var wrapped []string
		for _, line := range body {
			wrapped = append(wrapped, wrapLine(line, b.vp.Cols)...)
		}
		body = wrapped
	}
	limit := len(body)
	if b.vp.Rows > 0 {
		limit = b.vp.Rows - len(tail)
		if limit < 0 {
			limit = 0
		}
		if len(body) > limit {
			body = body[:limit]
		}
		kept := b.hm.hits[:0]
		for _, h := range b.hm.hits {
			if h.rect.Row < limit {
				kept = append(kept, h)
			}
		}
		b.hm.hits = kept
	}
	lines := append(append([]string{}, body...), tail...)
	if b.vp.Rows > 0 && len(lines) > b.vp.Rows {
		lines = lines[len(lines)-b.vp.Rows:]
	}
	return strings.Join(lines, "\n")
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
	prefix := b.marker(controlTarget{id: "copyCliInstall"})
	if prefix == "" {
		prefix = "  "
	}
	line := prefix + cmd
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
	renderFreshDrafts(b, m)

	if m.HasReviews {
		b.heading(domain.ReviewsInThisRepositoryHeading)
		renderInventoryRows(b, m)
		b.blank()
	}

	b.text(domain.NoActiveReviewNote)
	b.button("startReview", "", domain.StartReviewLabel, b.st.primary, true)
	b.blank()

	// The footer proper (FR-022): everything from here down is a
	// tools_section, and the one thing capped to 55% of the panel's height.
	// The draft block and the inventory above are NOT part of it — they sit
	// directly in no-review's own body, same as "No active review..." and
	// its button.
	footerStart := len(b.lines)

	b.heading(domain.WalkthroughSectionTitle)
	renderWalkthroughRow(b, m)
	renderGuideRows(b, m)

	if m.SpentDraftCount > 0 {
		b.blank()
		b.heading(domain.ReadingOrdersFinishedHeading)
		b.text(domain.ReadingOrdersFinishedNote)
		renderSpentDrafts(b, m)
	}

	if m.FixesCount > 0 {
		b.blank()
		b.heading(domain.EditsExtractedHeading)
		b.text(domain.EditsExtractedNote)
		renderFixesRows(b, m)
	}

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

	b.capFooter(footerStart)
}

// progressPair formats an annotated/total pair the way every row that
// carries one (drafts, the walkthrough row) shows it.
func progressPair(annotated, total int) string {
	return fmt.Sprintf("%d/%d", annotated, total)
}

func renderFreshDrafts(b *builder, m domain.PanelModel) {
	for _, d := range decodeDraftRows(m.FreshDraftRows) {
		b.rowHeader(d.src, progressPair(d.annotated, d.total), "")
		b.iconRow(
			rowIcon{id: "openDraft", variant: d.src, icon: domain.IconFile, hint: "open", enabled: true},
			rowIcon{id: "discardDraft", variant: d.src, icon: domain.IconTrash, hint: "discard", enabled: true},
		)
		// copyDraftPrompt/startFromDraft's emphasis follows progress, not
		// order (draft_controls' own comment): filled -> startFromDraft
		// leads; anything else, including a still-loading 0/0 -> the copy
		// prompt does.
		copyStyle, startStyle := b.st.secondary, b.st.primary
		filled := d.startable() && d.total > 0
		if filled {
			copyStyle, startStyle = b.st.primary, b.st.secondary
		}
		b.buttonRow(
			rowButton{id: "copyDraftPrompt", variant: d.src, label: domain.CopyForAgentLabel, style: copyStyle, enabled: true},
			rowButton{id: "startFromDraft", variant: d.src, label: domain.ValidateAndStartLabel, style: startStyle, enabled: d.startable()},
		)
		if !d.startable() {
			b.note(draftDisabledReason(d))
		}
		b.blank()
	}
}

// draftDisabledReason picks which of startFromDraft's two tooltips applies
// — the flags reason wins when both would apply (draft_controls' own
// comment: an unknown source/range breaks build regardless of how complete
// the order looks).
func draftDisabledReason(d draftRowView) string {
	if d.source == string(domain.DraftSourceUnknown) || d.rrange == string(domain.DraftRangeUnknown) {
		return domain.StartFromDraftDisabledTooltip
	}
	return domain.StartFromDraftUnfilledTooltip
}

func renderSpentDrafts(b *builder, m domain.PanelModel) {
	for _, d := range decodeDraftRows(m.SpentDraftRows) {
		b.rowHeader(d.src, progressPair(d.annotated, d.total), "")
		b.iconRow(
			rowIcon{id: "openDraft", variant: d.src, icon: domain.IconFile, hint: "open", enabled: true},
			rowIcon{id: "discardDraft", variant: d.src, icon: domain.IconTrash, hint: "discard", enabled: true},
		)
	}
}

func renderWalkthroughRow(b *builder, m domain.PanelModel) {
	// Without a `walkthrough` record at all (HasWalkthroughRow false — an
	// older CLI, or this read never got that far) there is nothing to
	// reconcile against, so the button reads exactly as it would for a
	// freshly-absent file: "Init".
	initLabel := domain.WalkthroughInitLabel
	if m.HasWalkthroughRow {
		initLabel = domain.WalkthroughInitButtonLabel(m.WalkthroughState)
	}
	b.buttonRow(
		rowButton{id: "walkthroughInit", label: initLabel, style: b.st.secondary, enabled: true},
		rowButton{id: "walkthroughBuild", label: domain.WalkthroughBuildLabel, style: b.st.secondary, enabled: true},
	)
	if !m.HasWalkthroughRow {
		return
	}
	name := m.WalkthroughRow
	if name == "" {
		// label_detached: the file and its two verbs work with HEAD
		// detached, only the branch name has no answer.
		name = domain.WalkthroughSectionTitle
	}
	progress := ""
	if m.WalkthroughState != domain.WalkthroughAbsent && m.WalkthroughTotal > 0 {
		progress = progressPair(m.WalkthroughAnnotated, m.WalkthroughTotal)
	}
	b.rowHeader(name, progress, domain.WalkthroughBadge[m.WalkthroughState])
	fileExists := m.WalkthroughState != domain.WalkthroughAbsent
	b.iconRow(rowIcon{id: "openWalkthrough", icon: domain.IconFile, hint: "open", enabled: fileExists})
	b.buttonRow(rowButton{id: "copyWalkthroughPrompt", label: domain.CopyForAgentLabel, style: b.st.secondary, enabled: fileExists})
}

func renderGuideRows(b *builder, m domain.PanelModel) {
	if !m.HasGuideRows {
		return
	}
	renderGuideRow(b, "team", domain.RepositoryGuideLabel, m.TeamGuideState, false)
	renderGuideRow(b, "own", domain.YourGuideLabel, m.OwnGuideState, true)
}

func renderGuideRow(b *builder, variant, label string, state domain.GuideState, own bool) {
	exists := state != domain.GuideAbsent
	b.rowHeader(label, "", domain.GuideBadge[state])
	icons := []rowIcon{{id: "openGuide", variant: variant, icon: domain.IconFile, hint: "open", enabled: exists}}
	if own {
		icons = append(icons, rowIcon{id: "discardGuide", variant: variant, icon: domain.IconTrash, hint: "discard", enabled: exists})
	}
	b.iconRow(icons...)
	b.buttonRow(rowButton{id: "createGuide", variant: variant, label: domain.CreateGuideLabel, style: b.st.secondary, enabled: !exists})
}

func renderFixesRows(b *builder, m domain.PanelModel) {
	for _, f := range decodeFixesRows(m.FixesRows) {
		b.rowHeader(f.name, "", domain.FixesBadge[domain.FixesState(f.state)])
		b.iconRow(rowIcon{id: "discardFixes", variant: f.name, icon: domain.IconTrash, hint: "discard", enabled: !f.current})
		if f.current {
			b.note(domain.CurrentBranchTooltip)
		}
	}
	b.blank()
	b.button("discardAllFixes", "", domain.DiscardAllFixesLabel, b.st.secondary, true)
}

func renderInventoryRows(b *builder, m domain.PanelModel) {
	for _, r := range decodeInventoryRows(m.InventoryRows) {
		badge := ""
		switch {
		case r.current:
			badge = "current"
		case r.orphan:
			badge = "broken"
		}
		b.rowHeader(r.name, "", badge)
		if r.status != "" {
			b.note(r.status)
		}
		if !r.canDiscard() {
			continue
		}
		var btns []rowButton
		if r.saved {
			btns = append(btns, rowButton{id: "continueReview", variant: r.name, label: domain.ContinueLabel, style: b.st.primary, enabled: r.resumable})
		}
		discardLabel := domain.DiscardLabel
		if r.orphan {
			discardLabel = domain.DiscardLeftoverLabel
		}
		btns = append(btns, rowButton{id: "discardInventory", variant: r.name, label: discardLabel, style: b.st.secondary, enabled: true})
		b.buttonRow(btns...)
		if r.saved && !r.resumable {
			reason := domain.ContinueReviewDisabledActiveTooltip
			if r.orphan {
				reason = domain.ContinueReviewDisabledOrphanTooltip
			}
			b.note(reason)
		}
	}
}

// capFooter enforces FR-022: the footer (everything from footerStart on)
// never draws more than FooterCapPercent of the viewport's rows. When it
// overflows, ONE movable window plus ONE track replaces the old destructive
// cutoff — never a per-section scroll, because the range is calculated once
// for the combined footer. Unbounded viewports (vp.Rows <= 0, every
// non-golden domain-only test) are left untouched: there is no budget to
// enforce against.
func (b *builder) capFooter(footerStart int) {
	if b.vp.Rows <= 0 {
		return
	}
	budget := b.vp.Rows * domain.FooterCapPercent / 100
	// A 55% budget measured against the WHOLE viewport is meaningless once
	// the head above the footer (the draft block, the inventory, "no active
	// review" and its button — none of which this cap governs) has already
	// spent part of it: without this, the cap could claim more room than is
	// actually left, and the key bar drawn after View returns would be the
	// thing frame()'s own final truncation silently drops instead.
	if remaining := b.vp.Rows - footerStart - b.tailReserve; remaining < budget {
		budget = remaining
	}
	if budget < 0 {
		budget = 0
	}
	footerLen := len(b.lines) - footerStart
	if footerLen <= budget {
		return
	}
	visibleLines := budget - 1 // one shared scrollbar/status line for the whole footer
	if visibleLines < 1 {
		visibleLines = 1
	}
	maxOffset := footerLen - visibleLines
	offset := b.state.footerOffset
	if offset < 0 {
		offset = 0
	}
	if offset > maxOffset {
		offset = maxOffset
	}
	b.metrics.footerOffset = offset
	b.metrics.footerMax = maxOffset

	windowStart := footerStart + offset
	windowEnd := windowStart + visibleLines
	lines := append([]string{}, b.lines[:footerStart]...)
	lines = append(lines, b.lines[windowStart:windowEnd]...)
	above, below := offset, maxOffset-offset
	marker := b.st.note.Render(fmt.Sprintf("… footer %s: %d line(s) above, %d below — j/k or mouse wheel", footerScrollbar(offset, maxOffset), above, below))
	b.lines = append(lines, marker)

	kept := b.hm.hits[:0]
	for _, h := range b.hm.hits {
		if h.rect.Row < footerStart {
			kept = append(kept, h)
			continue
		}
		if h.rect.Row < windowStart || h.rect.Row >= windowEnd {
			continue
		}
		h.rect.Row -= offset
		kept = append(kept, h)
	}
	b.hm.hits = kept
}

// footerScrollbar is the one visual scroll track promised for the entire
// tools footer. It uses ASCII only so it remains meaningful in every terminal
// mode; its single thumb moves over the same offset that keyboard and wheel
// input update.
func footerScrollbar(offset, maxOffset int) string {
	const width = 10
	track := []byte("..........")
	thumb := 0
	if maxOffset > 0 {
		thumb = offset * (width - 1) / maxOffset
	}
	track[thumb] = '#'
	return "[" + string(track) + "]"
}

func identityLine(m domain.PanelModel) string {
	return m.Branch
}

// renderWhyBlock draws showWhy's own state (T094): present is exactly the
// text-plus-button this client always drew for HasWhy==true, unchanged
// byte for byte (so no golden fixture regresses — none of them exercise
// anything but present or the zero value today); failed is new vocabulary
// this client had no way to represent before (WhyFailedNote); absent and
// loading draw nothing, the same silence the old `if m.HasWhy` already drew
// for false. leadingBlank matches each call site's own pre-existing layout:
// review-walk had a blank line before the block, finish-conflict's walk
// branch did not.
func renderWhyBlock(b *builder, m domain.PanelModel, leadingBlank bool) {
	switch m.WhyState {
	case domain.WhyPresent:
		if leadingBlank {
			b.blank()
		}
		b.text(m.Why)
		b.button("showWhy", m.CurrentPath.Raw, domain.OpenInEditorLabel, b.st.link, true)
	case domain.WhyFailed:
		if leadingBlank {
			b.blank()
		}
		b.note(domain.WhyFailedNote)
	}
}

func renderReviewWalk(b *builder, m domain.PanelModel) {
	b.heading(identityLine(m))
	b.note(m.Note)
	b.text(fmt.Sprintf("Entry %d/%d: %s", m.Position, m.Total, m.CurrentPath.Display))
	renderWhyBlock(b, m, true)
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
		renderWhyBlock(b, m, false)
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
