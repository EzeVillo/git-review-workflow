package ui

import (
	"context"
	"strings"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
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
	Title   string
	Context string
	Input   textinput.Model
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
	}
	if p.Context != "" {
		lines = append(lines, p.Context, "")
	}
	lines = append(lines,
		p.Input.View(), "",
		st.keybar.Render("enter")+":next  "+st.keybar.Render("esc")+":cancel",
	)
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

// --- Compare: two revisions, an exact-range offer probe, then a layout picker.
// The final reading choice uses
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
// "flags de layout"). Viability comes from the exact-range config probe.
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

func compareProbe(args []string, advance func(string) selectResult) tea.Cmd {
	return func() tea.Msg {
		return assistantStepMsg{result: host.InvokeReview(context.Background(), "compare", args), compareAdvance: advance}
	}
}

func releasePreparedComparison(token string) {
	if token != "" {
		host.InvokeReview(context.Background(), "compare", []string{"--release", "--", token})
	}
}

func releasePreparedComparisonCmd(token string) tea.Cmd {
	if token == "" {
		return nil
	}
	return func() tea.Msg { releasePreparedComparison(token); return nil }
}

func (m Model) beginCompareReview() (Model, tea.Cmd) {
	token := currentStateToken(m.Panel)
	return m.beginAssistantProbe(compareProbe([]string{"--sources", "--porcelain"}, func(stdout string) selectResult {
		return compareTargetStep(stdout, token)
	}))
}

func compareTargetStep(stdout string, token domain.StateToken) selectResult {
	var names []string
	sources := make(map[string][]SelectItem)
	for _, line := range strings.Split(stdout, "\n") {
		fields := strings.Split(strings.TrimSuffix(line, "\r"), "\t")
		if len(fields) != 5 || fields[0] != "compare-source" {
			continue
		}
		name, kind, remote, value := fields[1], fields[2], fields[3], fields[4]
		var label string
		switch kind {
		case "local":
			label = domain.CompareSourceLocal
		case "remote":
			label = strings.ReplaceAll(domain.CompareSourceRemote, "{remote}", remote)
		case "cached":
			label = strings.ReplaceAll(domain.CompareSourceCached, "{remote}", remote)
		default:
			continue
		}
		if len(sources[name]) == 0 {
			names = append(names, name)
		}
		sources[name] = append(sources[name], SelectItem{Label: label, Value: value})
	}
	return compareRevisionStep(domain.CompareTargetTitle, "", names, sources, func(upper string) selectResult {
		return compareRevisionStep(domain.CompareBaseTitle, domain.CompareBasePromptText(upper), names, sources, func(lower string) selectResult {
			if stdout == "" {
				return selectResult{probe: configProbeCmd([]string{"--compare", "--", lower, upper}, func(cfg domain.ConfigPorcelainResult) SelectOverlay {
					return *compareLayoutStep(lower, upper, token, cfg.Offers, "")
				})}
			}
			progress := ""
			if strings.HasPrefix(lower, "fetch:") || strings.HasPrefix(upper, "fetch:") {
				progress = domain.ComparePrepareProgress
			}
			return selectResult{probe: compareProbe([]string{"--prepare", "--porcelain", "--", lower, upper}, func(report string) selectResult {
				for _, line := range strings.Split(report, "\n") {
					if prepared, ok := strings.CutPrefix(strings.TrimSpace(line), "comparison-prepared\t"); ok && prepared != "" {
						return selectResult{next: compareLayoutStep(lower, upper, token, domain.ParseConfigPorcelain(report).Offers, prepared)}
					}
				}
				return selectResult{status: domain.CompareFailed}
			}), probeProgress: progress}
		})
	})
}

func compareRevisionStep(title, context string, names []string, sources map[string][]SelectItem, next func(string) selectResult) selectResult {
	choose := func(name string) selectResult {
		if len(sources[name]) == 0 {
			return next(name)
		}
		return selectResult{next: &SelectOverlay{
			Title: strings.ReplaceAll(domain.CompareSourceTitle, "{branch}", name), Items: sources[name], scroll: true, OnPick: next,
		}}
	}
	typeRevision := func() selectResult {
		prompt := NewTextPrompt(title, domain.CompareRevisionPrompt, choose)
		prompt.Context = context
		return selectResult{nextPrompt: prompt}
	}
	if len(names) == 0 {
		return typeRevision()
	}
	items := make([]SelectItem, 0, len(names)+1)
	items = append(items, SelectItem{Label: domain.CompareUseAsTyped})
	for _, name := range names {
		items = append(items, SelectItem{Label: name, Value: name})
	}
	return selectResult{next: &SelectOverlay{Title: title, Notice: context, Items: items, scroll: true, OnPick: func(name string) selectResult {
		if name == "" {
			return typeRevision()
		}
		return choose(name)
	}}}
}

// compareLayoutStep projects CLI offers through the shared Start labels. Picking a reading layout
// does NOT run the mutation directly (unlike startReview) — it opens
// ConfirmMutation, the compareReview id's own literal first argument (gate
// 2, T067/T085): a destructive-enough pick from this chain passes through
// the exact same door the body's Compare revisions button would.
func compareLayoutStep(lower, upper string, token domain.StateToken, offers []domain.ReadingOffer, prepared string) *SelectOverlay {
	var preparedFlag []string
	if prepared != "" {
		preparedFlag = []string{"--prepared=" + prepared}
	}
	intent := domain.ReviewIntent{Source: "compare", Range: "full"}
	items := buildLayoutOverlay(intent, offers).Items
	for i := range items {
		switch items[i].Value {
		case "draft":
			items[i].Detail = domain.CompareDraftDetail
		case "draft-update":
			items[i].Detail = domain.CompareDraftUpdateDetail
		case "walk":
			items[i].Detail = domain.CompareWalkDetail
		case "keys":
			items[i].Detail = domain.CompareKeysDetail
		case "step":
			items[i].Detail = domain.CompareStepDetail
		case "whole":
			items[i].Detail = domain.CompareWholeDetail
		}
	}
	overlay := SelectOverlay{
		Title:    domain.CompareLayoutTitle,
		Notice:   domain.ComparisonSummary(lower, upper),
		Items:    items,
		onCancel: releasePreparedComparisonCmd(prepared),
		OnPick: func(layout string) selectResult {
			if layout == "draft-resume" {
				return selectResult{cmd: releasePreparedComparisonCmd(prepared)}
			}
			if layout == "draft" || layout == "draft-update" {
				req := draftFlowRequest(intent, offers, layout == "draft-update")
				args := append([]string{"draft", "--porcelain", "--compare"}, preparedFlag...)
				req.argv = &domain.Argv{Verb: "walkthrough", Args: append(args, "--", lower, upper)}
				req.comparePrepared = prepared
				return selectResult{done: &req}
			}
			params := domain.ActionParams{
				CompareLayout: append(compareLayoutFlags(layout), preparedFlag...),
				CompareLower:  lower,
				CompareUpper:  upper,
			}
			req := mutationRequest{action: "compareReview", params: params, comparePrepared: prepared}
			title := domain.ComparisonSummary(lower, upper) + "?"
			overlay := ConfirmMutation("compareReview", title, domain.CompareReviewConfirmDetail, domain.CompareRevisionsLabel, token, req)
			return selectResult{confirmNext: overlay}
		},
	}
	return &overlay
}
