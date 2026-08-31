package ui

import (
	"strings"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
)

// TextPrompt is a single free-text question — compareReview's own lower/
// upper revision names are the only user (T089): unlike everything else
// this client asks, a commit-ish can be anything, so there is no `offer`
// record to build a fixed list of candidates from (contracts/
// cli-invocation.md: compare has none), and the CLI's own rejection of a
// bad name is the validation, not this overlay.
type TextPrompt struct {
	Title string
	Input textinput.Model
	// OnSubmit is called with the TRIMMED value once Enter is pressed on a
	// non-empty input.
	OnSubmit func(value string) selectResult
}

// NewTextPrompt builds a focused, ready-to-type prompt.
func NewTextPrompt(title, placeholder string, onSubmit func(string) selectResult) *TextPrompt {
	ti := textinput.New()
	ti.Placeholder = placeholder
	ti.Focus()
	return &TextPrompt{Title: title, Input: ti, OnSubmit: onSubmit}
}

// HandleKey resolves one keypress. submitted=true means Enter was pressed
// on a non-empty value and result carries what comes next; cancelled=true
// means Esc/ctrl+c abandoned the whole chain — the same "closing it is the
// same as cancelling" shape every other overlay in this package uses.
func (p *TextPrompt) HandleKey(msg tea.KeyMsg) (result selectResult, submitted, cancelled bool, cmd tea.Cmd) {
	switch msg.String() {
	case "esc", "ctrl+c":
		return selectResult{}, false, true, nil
	case "enter":
		v := strings.TrimSpace(p.Input.Value())
		if v == "" {
			return selectResult{}, false, false, nil
		}
		return p.OnSubmit(v), true, false, nil
	}
	p.Input, cmd = p.Input.Update(msg)
	return selectResult{}, false, false, cmd
}

// Render draws the prompt as the whole frame while it is open — the same
// full-replacement simplification every overlay in this package documents.
func (p *TextPrompt) Render(vp Viewport) string {
	st := stylesFor(vp.Color)
	lines := []string{
		st.heading.Render(p.Title), "",
		p.Input.View(), "",
		st.keybar.Render("enter") + ":next  " + st.keybar.Render("esc") + ":cancel",
	}
	return capOverlay(lines, vp)
}

// handleTextPromptKey routes a KeyMsg to the open TextPrompt instead of the
// normal focus/activate resolution (Update checks m.textPrompt != nil
// BEFORE calling handleKey, same as every other overlay).
func (m Model) handleTextPromptKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	result, submitted, cancelled, cmd := m.textPrompt.HandleKey(msg)
	if cancelled {
		m.textPrompt = nil
		return m, nil
	}
	if !submitted {
		return m, cmd
	}
	return m.applySelectResult(result)
}

// --- compareReview: two free-text questions, a fixed layout picker, then
// the SAME confirming door the body uses (T089/T093) --------------------
//
// compareReview is confirms:true in the canonical (the row control that
// draws it, panel_layout's own compare section, carries confirms: true) —
// unlike startReview's own four-question chain, which ends by running
// straight through with no confirmation. The reason the two differ:
// startReview only ever runs from no-review, where there is nothing yet to
// lose; compareReview is offered from EVERY situation, including inside an
// active review, and checking out its comparison branch can leave unsaved
// edits harder to get back to.

// compareLayoutFlags mirrors IntentToArgs' own layout switch (start and
// compare share the exact same flag vocabulary — cli-invocation.md's
// "flags de layout" — with no `offer` filtering: compare lists all four
// unconditionally, and the CLI's own rejection of --keys on a review
// without a walkthrough is the validation, not this client).
func compareLayoutFlags(layout string) []string {
	switch layout {
	case "keys":
		return []string{"--keys"}
	case "step":
		return []string{"--step"}
	case "whole":
		return []string{"--no-walk"}
	default:
		return nil // walk: no flag, the default layout.
	}
}

// beginCompareReview opens the FIRST of compareReview's two free-text
// questions. token is captured HERE, at the gesture that opened the whole
// chain — T065's own revalidation happens once, inside beginMutation, right
// before the eventual spawn, never re-captured at any step in between.
func (m Model) beginCompareReview() (Model, tea.Cmd) {
	token := currentStateToken(m.Panel)
	m.textPrompt = NewTextPrompt(domain.CompareLowerTitle, domain.RevisionPlaceholder, func(lower string) selectResult {
		return selectResult{nextPrompt: NewTextPrompt(domain.CompareUpperTitle, domain.RevisionPlaceholder, func(upper string) selectResult {
			return selectResult{next: compareLayoutStep(lower, upper, token)}
		})}
	})
	return m, nil
}

// compareLayoutStep is the chain's last question: the SAME four labels
// startReview's own layout step uses, listed unconditionally. Picking one
// does NOT run the mutation directly (unlike startReview) — it opens
// ConfirmMutation, the compareReview id's own literal first argument (gate
// 2, T067/T085): a destructive-enough pick from this chain passes through
// the exact same door the body's Compare revisions button would.
func compareLayoutStep(lower, upper string, token domain.StateToken) *SelectOverlay {
	overlay := SelectOverlay{
		Title: domain.StartAssistantLayoutTitle,
		Items: []SelectItem{
			{Label: domain.LayoutWalkLabel, Value: "walk"},
			{Label: domain.LayoutKeysLabel, Value: "keys"},
			{Label: domain.LayoutStepLabel, Value: "step"},
			{Label: domain.LayoutWholeLabel, Value: "whole"},
		},
		OnPick: func(layout string) selectResult {
			params := domain.ActionParams{
				CompareLayout: compareLayoutFlags(layout),
				CompareLower:  lower,
				CompareUpper:  upper,
			}
			req := mutationRequest{action: "compareReview", params: params}
			title := interpolate(domain.CompareReviewConfirmTitle, "{lower}", lower, "{upper}", upper)
			overlay := ConfirmMutation("compareReview", title, domain.CompareReviewConfirmDetail, domain.CompareRevisionsLabel, token, req)
			return selectResult{confirmNext: overlay}
		},
	}
	return &overlay
}
