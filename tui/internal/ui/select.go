package ui

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

// SelectItem is one option a SelectOverlay offers.
type SelectItem struct {
	Label string
	// Detail: an optional second line drawn under the label — the start
	// assistant's finish-destination step uses it to spell out what each
	// choice actually does (contracts/cli-invocation.md's own QuickPick
	// mirror in the other three clients).
	Detail string
	Value  string
}

// selectResult is what answering one SelectOverlay question leads to:
// either another question (multi-step flows), a Cmd that must run first
// (a fresh config probe, before the NEXT question can even be built), or
// the finished mutationRequest once the LAST question has been answered.
// At most one of the three is ever set.
type selectResult struct {
	next *SelectOverlay
	cmd  tea.Cmd
	done *mutationRequest
	// status: set the status line directly and close the picker, with no
	// mutation and nothing further to run — goToEntry's own "no editor is
	// configured" (T086/T089) is the only user today.
	status string
	// nextPrompt / confirmNext: the two OTHER overlay kinds a chain can step
	// into — compareReview's own free-text lower/upper questions (T089) are
	// the only user of nextPrompt, and its own confirms:true gate (canonical)
	// is the only user of confirmNext: the LAST step of that chain opens the
	// SAME ConfirmMutation gate the body would, never runs the mutation
	// directly the way startReview's own chain (done) does.
	nextPrompt  *TextPrompt
	confirmNext *ConfirmOverlay
}

// applySelectResult is the ONE place a selectResult (from either a
// SelectOverlay.OnPick or a TextPrompt.OnSubmit — the two step kinds a
// picker chain can produce) resolves into the next Model state: at most one
// of next/nextPrompt/confirmNext ever ends up open, done runs a mutation
// with no confirmation (startReview's own shape), and cmd is whatever must
// run before the NEXT question can even be built (a fresh config probe).
func (m Model) applySelectResult(r selectResult) (Model, tea.Cmd) {
	m.selectOverlay = r.next
	m.textPrompt = r.nextPrompt
	m.confirm = r.confirmNext
	if r.status != "" {
		m.statusLine = r.status
	}
	if r.done != nil {
		return m.beginMutation(*r.done, currentStateToken(m.Panel))
	}
	return m, r.cmd
}

// SelectOverlay is a MULTI-STEP, NON-CONFIRMING chooser (tasks.md T069:
// "una serie de pantallas/overlays de SELECCIÓN, no de confirmación"). It
// backs the start assistant's four questions (assistant.go) and the
// setBase/setRemote/finish-destination pickers — every one of them "which
// one of these", never "yes or no".
//
// It is deliberately NOT domain.ConfirmChoice-shaped and never constructs a
// ConfirmOverlay: contracts/tui-surface.md says it outright — "esta lista
// no confirma: elige". Folding a picker into the confirmation gate would
// need a genuine yes/no question, which choosing among options is not.
// Gate 2/3 (scripts/check-client-product-surface.mjs) are scoped to
// ConfirmMutation/ConfirmOverlay by name, so this type sits outside their
// sweep by construction, not by exemption — and none of startReview/
// startFromDraft/setBase/setRemote/finishReview (the ids every picker here
// ultimately runs) are confirms: true in the canonical, so none of these
// flows is SUPPOSED to end at a confirmation at all.
type SelectOverlay struct {
	Title  string
	Items  []SelectItem
	Cursor int
	// OnPick is called with the CHOSEN item's Value once Enter picks it.
	OnPick func(value string) selectResult
}

// HandleKey resolves one keypress against the open picker. picked=true
// means Enter chose the item at Cursor; cancelled=true means the whole flow
// was abandoned (Esc/q/ctrl+c) — same "closing it is the same as
// cancelling" shape ConfirmOverlay uses.
func (o *SelectOverlay) HandleKey(key string) (value string, picked bool, cancelled bool) {
	switch key {
	case "j", "down":
		if len(o.Items) > 0 {
			o.Cursor = (o.Cursor + 1) % len(o.Items)
		}
	case "k", "up":
		if len(o.Items) > 0 {
			o.Cursor = (o.Cursor - 1 + len(o.Items)) % len(o.Items)
		}
	case "enter":
		if len(o.Items) > 0 {
			return o.Items[o.Cursor].Value, true, false
		}
	case "esc", "ctrl+c", "q":
		return "", false, true
	}
	return "", false, false
}

// Render draws the picker as the whole frame while it is open — the same
// full-replacement simplification ConfirmOverlay.Render documents, for the
// same ANSI-safety reason.
func (o *SelectOverlay) Render(vp Viewport) string {
	st := stylesFor(vp.Color)
	var lines []string
	lines = append(lines, st.heading.Render(o.Title), "")
	if len(o.Items) == 0 {
		lines = append(lines, st.note.Render("(nothing to choose from)"))
	}
	for i, it := range o.Items {
		prefix := "  "
		style := st.secondary
		if i == o.Cursor {
			prefix = "> "
			style = st.primary
		}
		lines = append(lines, prefix+style.Render(it.Label))
		if it.Detail != "" {
			lines = append(lines, "    "+st.note.Render(it.Detail))
		}
	}
	lines = append(lines, "", st.keybar.Render("j/k")+":move  "+st.keybar.Render("enter")+":pick  "+st.keybar.Render("esc")+":cancel")
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
