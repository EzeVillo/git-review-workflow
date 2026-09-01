package ui

import (
	"os"
	"strconv"
	"strings"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
)

// paletteItem is one filterable row of the action list overlay.
type paletteItem struct {
	action string
	label  string
	key    string // "" when the action has no key of its own in the body.
}

// ActionList is the action palette (T084): this client's own `surface:
// action` — the equivalent of VS Code's command palette, JetBrains' Tools
// menu and Visual Studio's .vsct — and the ONE place FR-021's four
// panel_excluded ids (goToEntry, forgetReview, previewEditsStat,
// showCliLog) live. It filters as the reviewer types; it never confirms
// (contracts/tui-surface.md: "esta lista no confirma, elige") — picking a
// destructive action here runs through the SAME ConfirmMutation gate the
// body uses (mutation.go's activatePaletteAction, T085), never a second one.
type ActionList struct {
	Filter textinput.Model
	all    []paletteItem
	Cursor int
}

// keyForAction finds the key that already activates `action` in the body
// (only "refresh" has one today, per domain.KeymapActions' own doc) — the
// gate (e) of `keymap:` this overlay's own existence satisfies: an id here
// with a body key shows it; panel_excluded's four never have one, by
// construction of domain.PaletteActions never intersecting a bound key for
// them (keymap_test.go's TestPanelExcludedActionsHaveNoDirectKey covers the
// canonical side of the same fact).
func keyForAction(action string) string {
	for _, e := range domain.KeymapActions {
		if e.Action == action && len(e.Keys) > 0 {
			return e.Keys[0]
		}
	}
	for _, e := range domain.KeymapCursor {
		if e.Action == action && len(e.Keys) > 0 {
			return e.Keys[0]
		}
	}
	return ""
}

// NewActionList builds the palette for the CURRENT panel state — every
// action domain.PaletteActionsFor enables for this exact situation/busy/
// readonly combination, in its declared order.
func NewActionList(situation domain.Situation, busy, readonly bool) *ActionList {
	ti := textinput.New()
	ti.Placeholder = "Type to filter…"
	ti.Prompt = "> "
	ti.Focus()
	var items []paletteItem
	for _, a := range domain.PaletteActionsFor(situation, busy, readonly) {
		items = append(items, paletteItem{
			action: a.ID,
			label:  domain.PaletteLabel[a.ID],
			key:    keyForAction(a.ID),
		})
	}
	return &ActionList{Filter: ti, all: items}
}

// filtered narrows `all` to items whose label contains the filter text,
// case-insensitively — a plain substring match, not fuzzy: predictable
// beats clever for a list this short.
func (a *ActionList) filtered() []paletteItem {
	q := strings.ToLower(strings.TrimSpace(a.Filter.Value()))
	if q == "" {
		return a.all
	}
	var out []paletteItem
	for _, it := range a.all {
		if strings.Contains(strings.ToLower(it.label), q) {
			out = append(out, it)
		}
	}
	return out
}

func (a *ActionList) moveCursor(delta int) {
	items := a.filtered()
	if len(items) == 0 {
		a.Cursor = 0
		return
	}
	a.Cursor = ((a.Cursor+delta)%len(items) + len(items)) % len(items)
}

// HandleKey resolves one keypress against the open palette. picked=true
// means Enter chose the item at Cursor within the CURRENTLY filtered list.
// j/k are deliberately NOT movement here (unlike SelectOverlay): a
// filterable list needs its letters back for the filter box, so movement
// is up/down/ctrl+n/ctrl+p instead. Any key that is not one of those, Enter
// or Esc/ctrl+c is forwarded to the filter's own textinput.Update.
func (a *ActionList) HandleKey(msg tea.KeyMsg) (action string, picked, cancelled bool, cmd tea.Cmd) {
	switch msg.String() {
	case "esc", "ctrl+c":
		return "", false, true, nil
	case "enter":
		items := a.filtered()
		if len(items) == 0 {
			return "", false, false, nil
		}
		if a.Cursor < 0 || a.Cursor >= len(items) {
			a.Cursor = 0
		}
		return items[a.Cursor].action, true, false, nil
	case "down", "ctrl+n":
		a.moveCursor(1)
		return "", false, false, nil
	case "up", "ctrl+p":
		a.moveCursor(-1)
		return "", false, false, nil
	}
	before := a.Filter.Value()
	a.Filter, cmd = a.Filter.Update(msg)
	if a.Filter.Value() != before {
		// The filtered set just changed shape; a cursor left over from a
		// longer list would silently point at the wrong row (or past the
		// end) once it shrinks.
		a.Cursor = 0
	}
	return "", false, false, cmd
}

// Render draws the palette as the whole frame while it is open — the same
// full-replacement simplification ConfirmOverlay/SelectOverlay already
// document, for the same ANSI-safety reason.
func (a *ActionList) Render(vp Viewport) string {
	st := stylesFor(vp.Color)
	header := []string{st.heading.Render("Actions"), a.Filter.View(), ""}
	help := []string{"", st.keybar.Render("up/down") + ":move  " + st.keybar.Render("enter") + ":run  " + st.keybar.Render("esc") + ":close"}
	items := a.filtered()
	listStart, listEnd := 0, len(items)
	if vp.Rows > 0 {
		listRows := vp.Rows - len(header) - len(help)
		if listRows < 1 {
			listRows = 1
		}
		if len(items) > listRows {
			cursor := a.Cursor
			if cursor < 0 || cursor >= len(items) {
				cursor = 0
			}
			listStart = cursor - listRows + 1
			if listStart < 0 {
				listStart = 0
			}
			if maxStart := len(items) - listRows; listStart > maxStart {
				listStart = maxStart
			}
			listEnd = listStart + listRows
		}
	}
	lines := append([]string{}, header...)
	if len(items) == 0 {
		lines = append(lines, st.note.Render("(no matching action)"))
	}
	for i := listStart; i < listEnd; i++ {
		it := items[i]
		prefix := "  "
		style := st.secondary
		if i == a.Cursor {
			prefix = "> "
			style = st.primary
		}
		line := prefix + style.Render(it.label)
		if it.key != "" {
			line += "  " + st.keybar.Render(it.key)
		}
		lines = append(lines, line)
	}
	lines = append(lines, help...)
	return capOverlay(lines, vp)
}

// handleActionListKey routes a KeyMsg to the open ActionList instead of the
// normal focus/activate resolution (Update checks m.actionList != nil
// BEFORE calling handleKey, same as confirm/selectOverlay). Picking an
// entry closes the palette FIRST, then dispatches through
// activatePaletteAction (T085) — so a destructive pick's own ConfirmMutation
// call opens on top of an already-closed palette, never stacked underneath
// it.
func (m Model) handleActionListKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	action, picked, cancelled, cmd := m.actionList.HandleKey(msg)
	if cancelled {
		m.actionList = nil
		return m, nil
	}
	if !picked {
		return m, cmd
	}
	m.actionList = nil
	return m.activatePaletteAction(action)
}

// --- goToEntry: a picker APART from the palette (T086) ----------------------

type entryPickerRowView struct {
	position     int
	raw, display string
}

func decodeEntryPickerRows(joined string) []entryPickerRowView {
	rows := domain.FooterRows(joined)
	out := make([]entryPickerRowView, 0, len(rows))
	for _, r := range rows {
		if len(r) < 3 {
			continue
		}
		pos, _ := strconv.Atoi(r[0])
		out = append(out, entryPickerRowView{position: pos, raw: r[1], display: r[2]})
	}
	return out
}

// GoToEntryTitle is the entry picker's own heading — not a `strings:`
// entry, since none of the other three clients declare an equivalent title
// for pickEntry.ts's own QuickPick (research.md/contracts/tui-surface.md
// name no such string).
const goToEntryTitle = "Go to entry"

// openEntryPicker builds goToEntry's own overlay (T086): entries, not
// actions — a SEPARATE type from ActionList, per contracts/tui-surface.md
// ("un picker aparte, no la misma lista"). Picking an item OPENS it and
// nothing else: no next/prev runs, so the CLI's own cursor never moves
// (User Story 3, escenario 5).
func (m Model) openEntryPicker() Model {
	rows := decodeEntryPickerRows(m.Panel.EntryPickerRows)
	if len(rows) == 0 {
		return m
	}
	items := make([]SelectItem, 0, len(rows))
	for _, r := range rows {
		items = append(items, SelectItem{Label: r.display, Value: r.raw})
	}
	mode := m.Panel.Mode
	overlay := SelectOverlay{
		Title: goToEntryTitle,
		Items: items,
		OnPick: func(raw string) selectResult {
			dir, _ := os.Getwd()
			if mode == domain.ModeStep {
				return selectResult{cmd: execCmd(host.DiffCommitCmd(raw, dir))}
			}
			display := raw
			for _, r := range rows {
				if r.raw == raw {
					display = r.display
					break
				}
			}
			cmd, reason, ok := host.OpenInEditorCmd(display, dir)
			if !ok {
				return selectResult{status: reason}
			}
			return selectResult{cmd: execCmd(cmd)}
		},
	}
	m.selectOverlay = &overlay
	return m
}

// --- showCliLog / previewEditsStat: a read-only text overlay (T087/T088) ---

// TextOverlay is a read-only, non-confirming full-frame overlay for a
// block of text a gesture asked for directly: the invocation log
// (showCliLog) or a diffstat (previewEditsStat's "es texto, o sea
// nativa"). It is the THIRD layer of the copy rule — label, then context,
// then technical detail always one gesture away — and per contracts/
// tui-surface.md the argv NEVER appears in the first two layers, only
// here.
type TextOverlay struct {
	Title string
	Body  string
}

func (o *TextOverlay) HandleKey(key string) (closed bool) {
	switch key {
	case "esc", "enter", "q", "ctrl+c":
		return true
	}
	return false
}

func (o *TextOverlay) Render(vp Viewport) string {
	st := stylesFor(vp.Color)
	lines := []string{st.heading.Render(o.Title), ""}
	if o.Body == "" {
		lines = append(lines, st.note.Render("(nothing to show)"))
	} else {
		lines = append(lines, strings.Split(strings.TrimRight(o.Body, "\n"), "\n")...)
	}
	lines = append(lines, "", st.keybar.Render("esc")+":close")
	return capOverlay(lines, vp)
}

// capOverlay is the wrap-then-cap step every full-frame overlay in this
// package shares (ConfirmOverlay/SelectOverlay's own Render already do
// this inline; palette.go factors it out since it now has three).
func capOverlay(lines []string, vp Viewport) string {
	if vp.Cols > 0 {
		var wrapped []string
		for _, l := range lines {
			wrapped = append(wrapped, wrapLine(l, vp.Cols)...)
		}
		lines = wrapped
	}
	if vp.Rows > 0 && len(lines) > vp.Rows {
		lines = lines[:vp.Rows]
	}
	return strings.Join(lines, "\n")
}
