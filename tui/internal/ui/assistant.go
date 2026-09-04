package ui

import (
	"context"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	tea "github.com/charmbracelet/bubbletea"
)

// The start assistant: contracts/cli-invocation.md's three config probes —
//
//	config --porcelain
//	config --porcelain [--local|--offline] -- <branch>
//	config --porcelain [--local|--offline] [--delta] -- <branch>
//
// — walked as up to four SelectOverlay questions (branch, source, optional
// range, layout),
// each one offering ONLY what the CLI reports as viable for that exact
// combination (the `offer`/`candidate`/`delta` records, never a fixed list
// this client invents). All three probes are `config`, always class Read
// (never Network) — domain.ClassForVerb already classifies `config` that
// way regardless of args.
//
// The LAST question's answer runs startReview directly: no confirmation in
// between (T069's own gate — startReview is not confirms: true, and this
// file never calls ConfirmMutation for it), matching the multi-step intent
// choice in confirms.go's own comment on why startReview is absent from
// ConfirmingIDs.

// assistantStepMsg carries one config probe's result back, tagged with the
// function that turns it into the NEXT question — the same "what to build
// next" pattern SelectOverlay.OnPick uses for a step that needs no probe.
type assistantStepMsg struct {
	assistantGeneration int
	result              host.Result
	build               func(domain.ConfigPorcelainResult) SelectOverlay
	advance             func(domain.ConfigPorcelainResult) selectResult
}

// configProbeCmd runs one `config --porcelain <extra...>` probe. Always
// class Read (domain.ClassForVerb("config", ...)) — cli-invocation.md's own
// words: "Siempre class == Read (nunca red)".
func configProbeCmd(extra []string, build func(domain.ConfigPorcelainResult) SelectOverlay) tea.Cmd {
	args := append([]string{"--porcelain"}, extra...)
	return func() tea.Msg {
		res := host.InvokeReview(context.Background(), "config", args)
		return assistantStepMsg{result: res, build: build}
	}
}

func configAdvanceCmd(extra []string, advance func(domain.ConfigPorcelainResult) selectResult) tea.Cmd {
	args := append([]string{"--porcelain"}, extra...)
	return func() tea.Msg {
		res := host.InvokeReview(context.Background(), "config", args)
		return assistantStepMsg{result: res, advance: advance}
	}
}

// startAssistant is startReview's entry point (activateControl): the FIRST
// probe, unscoped, whose candidates seed the branch question.
func (m Model) startAssistant() (Model, tea.Cmd) {
	return m.beginAssistantProbe(configAdvanceCmd(nil, buildBranchResult(m.preferredStartSource)))
}

func (m Model) beginAssistantProbe(probe tea.Cmd) (Model, tea.Cmd) {
	m.assistantGeneration++
	generation := m.assistantGeneration
	m.progressOverlay = &ProgressOverlay{Text: domain.ReadOptionsProgress}
	m.selectOverlay = nil
	return m, func() tea.Msg {
		msg := probe().(assistantStepMsg)
		msg.assistantGeneration = generation
		return msg
	}
}

// handleAssistantStep resolves one assistantStepMsg: a failed probe reports
// itself on the status line (same failureMessage this file's mutations use)
// and leaves the picker closed; a successful one builds and opens the next
// SelectOverlay.
func (m Model) handleAssistantStep(msg assistantStepMsg) (Model, tea.Cmd) {
	if msg.assistantGeneration != 0 && msg.assistantGeneration != m.assistantGeneration {
		return m, nil
	}
	m.progressOverlay = nil
	if mutationFailed(msg.result) {
		m.statusLine = failureMessage("startReview", msg.result)
		m.selectOverlay = nil
		return m, nil
	}
	cfg := domain.ParseConfigPorcelain(msg.result.Stdout)
	if msg.advance != nil {
		return m.applySelectResult(msg.advance(cfg))
	}
	overlay := msg.build(cfg)
	m.selectOverlay = &overlay
	return m, nil
}

// buildBranchStep is question 1: which branch, from the unscoped probe's
// `candidate` records (the exact same universe setBase's picker reads,
// per branchItems' own comment).
func buildBranchStep(preferredSource string) func(domain.ConfigPorcelainResult) SelectOverlay {
	return func(cfg domain.ConfigPorcelainResult) SelectOverlay {
		candidates := cfg.Candidates
		return SelectOverlay{
			Title: domain.StartAssistantBranchTitle,
			Items: branchItems(domain.BranchPickerItems(candidates)),
			OnPick: func(branch string) selectResult {
				next := buildSourceStep(branch, preferredSource, candidates)
				return selectResult{next: &next}
			},
		}
	}
}

func buildBranchResult(preferredSource string) func(domain.ConfigPorcelainResult) selectResult {
	return func(cfg domain.ConfigPorcelainResult) selectResult {
		overlay := buildBranchStep(preferredSource)(cfg)
		if len(overlay.Items) == 0 {
			return selectResult{status: domain.NoBranchesForReview}
		}
		return selectResult{next: &overlay}
	}
}

// buildSourceStep is question 2: where the tip comes from. Viability comes
// from the FIRST probe's candidates for this branch (does a remote row
// exist? a local one?). No branch-scoped probe runs until this choice is
// made: without a source, validating the default remote tip would reject a
// perfectly valid local-only branch before the reviewer can choose Local or
// Offline. The selected source scopes the second probe, whose `delta` records
// seed the range question. reviewui.startsource (FR-061) only pre-positions
// the cursor; it never hides an option the CLI did not itself rule out.
func buildSourceStep(branch, preferredSource string, candidates []domain.CandidateBranch) SelectOverlay {
	var hasRemote, hasLocal bool
	for _, c := range candidates {
		if c.Name != branch {
			continue
		}
		switch c.Origin {
		case "remote":
			hasRemote = true
		case "local":
			hasLocal = true
		}
	}
	var items []SelectItem
	if hasRemote {
		items = append(items, SelectItem{Label: domain.SourceRemoteLabel, Value: "remote"})
	}
	if hasLocal {
		items = append(items, SelectItem{Label: domain.SourceLocalLabel, Value: "local"})
		items = append(items, SelectItem{Label: domain.SourceOfflineLabel, Value: "offline"})
	}
	cursor := 0
	for i, it := range items {
		if it.Value == preferredSource {
			cursor = i
		}
	}
	return SelectOverlay{
		Title:  domain.StartAssistantSourceTitle,
		Items:  items,
		Cursor: cursor,
		OnPick: func(source string) selectResult {
			return selectResult{probe: configAdvanceCmd(
				sourceRangeProbeArgs(source, "full", branch),
				func(cfg domain.ConfigPorcelainResult) selectResult {
					return buildRangeResult(branch, source, cfg.Deltas)
				},
			)}
		},
	}
}

func buildRangeResult(branch, source string, deltas []domain.DeltaRecord) selectResult {
	if _, ok := domain.DeltaForSource(deltas, source); !ok {
		return selectResult{probe: configProbeCmd(
			sourceRangeProbeArgs(source, "full", branch),
			buildLayoutStep(branch, source, "full"),
		)}
	}
	return selectResult{next: buildRangeStep(branch, source, deltas)}
}

// buildRangeStep is question 3: full or delta. No new probe — the second
// probe already reported every `delta` marker this branch has, and
// domain.DeltaForSource picks the one that applies to the chosen source.
func buildRangeStep(branch, source string, deltas []domain.DeltaRecord) *SelectOverlay {
	items := []SelectItem{{Label: domain.RangeFullLabel, Value: "full"}}
	if _, ok := domain.DeltaForSource(deltas, source); ok {
		items = append(items, SelectItem{Label: domain.RangeDeltaLabel, Value: "delta"})
	}
	overlay := SelectOverlay{
		Title: domain.StartAssistantRangeTitle,
		Items: items,
		OnPick: func(rng string) selectResult {
			return selectResult{probe: configProbeCmd(
				sourceRangeProbeArgs(source, rng, branch),
				buildLayoutStep(branch, source, rng),
			)}
		},
	}
	return &overlay
}

// sourceRangeProbeArgs builds the branch-scoped probes' flags in config's
// documented order (source flag, then --delta, then `-- branch`). The second probe passes full because it
// only needs source-specific delta records; the third passes the chosen range
// so its offers describe the exact combination the final start will run.
func sourceRangeProbeArgs(source, rng, branch string) []string {
	var args []string
	switch source {
	case "local":
		args = append(args, "--local")
	case "offline":
		args = append(args, "--offline")
	}
	if rng == "delta" {
		args = append(args, "--delta")
	}
	args = append(args, "--", branch)
	return args
}

// buildLayoutStep is question 4, the last one: walk/keys/step/whole, filtered
// to the THIRD probe's own `offer` records — never a fixed list. Answering
// it is the wizard's only DONE step: the resulting mutationRequest runs
// startReview with no confirmation in between (T069's gate).
func buildLayoutStep(branch, source, rng string) func(domain.ConfigPorcelainResult) SelectOverlay {
	return func(cfg domain.ConfigPorcelainResult) SelectOverlay {
		return buildLayoutOverlay(domain.ReviewIntent{Branch: branch, Source: source, Range: rng}, cfg.Offers)
	}
}

type layoutOfferMeta struct {
	label, detail string
}

var layoutOfferOrder = []domain.OfferID{
	domain.OfferWalk, domain.OfferKeys, domain.OfferDraft,
	domain.OfferDraftResume, domain.OfferDraftUpdate,
	domain.OfferStep, domain.OfferWhole,
}

var layoutOfferCopy = map[domain.OfferID]layoutOfferMeta{
	domain.OfferWalk:        {label: domain.LayoutWalkLabel},
	domain.OfferKeys:        {label: domain.LayoutKeysLabel},
	domain.OfferDraft:       {label: domain.LayoutDraftLabel, detail: domain.LayoutDraftDetail},
	domain.OfferDraftResume: {label: domain.LayoutDraftResumeLabel, detail: domain.LayoutDraftResumeDetail},
	domain.OfferDraftUpdate: {label: domain.LayoutDraftUpdateLabel, detail: domain.LayoutDraftUpdateDetail},
	domain.OfferStep:        {label: domain.LayoutStepLabel},
	domain.OfferWhole:       {label: domain.LayoutWholeLabel},
}

func effectiveLayoutOffers(offers []domain.ReadingOffer) []domain.ReadingOffer {
	if len(offers) == 0 {
		return []domain.ReadingOffer{
			{ID: domain.OfferStep, Rank: "available"},
			{ID: domain.OfferWhole, Rank: "available"},
		}
	}
	return offers
}

func buildLayoutOverlay(intent domain.ReviewIntent, offers []domain.ReadingOffer) SelectOverlay {
	effective := effectiveLayoutOffers(offers)
	byID := make(map[domain.OfferID]string, len(effective))
	for _, offer := range effective {
		byID[offer.ID] = offer.Rank
	}
	var ordered []domain.OfferID
	for _, rank := range []string{"recommended", "available"} {
		for _, id := range layoutOfferOrder {
			if byID[id] == rank {
				ordered = append(ordered, id)
			}
		}
	}
	items := make([]SelectItem, 0, len(ordered))
	for _, id := range ordered {
		copy := layoutOfferCopy[id]
		if byID[id] == "recommended" {
			copy.label += " (recommended)"
		}
		items = append(items, SelectItem{Label: copy.label, Detail: copy.detail, Value: string(id)})
	}
	return SelectOverlay{
		Title: domain.StartLayoutTitle(intent.Branch),
		Items: items,
		OnPick: func(value string) selectResult {
			id := domain.OfferID(value)
			switch id {
			case domain.OfferDraftResume:
				return selectResult{}
			case domain.OfferDraft, domain.OfferDraftUpdate:
				req := draftFlowRequest(intent, offers, id == domain.OfferDraftUpdate)
				return selectResult{done: &req}
			default:
				intent.Layout = value
				req := mutationRequest{action: "startReview", params: domain.ActionParams{Intent: intent}}
				return selectResult{done: &req}
			}
		},
	}
}

func draftFlowRequest(intent domain.ReviewIntent, offers []domain.ReadingOffer, update bool) mutationRequest {
	argv := domain.Argv{Verb: "walkthrough", Args: domain.DraftWriteArgs(intent)}
	return mutationRequest{
		action:       "draftFlow",
		params:       domain.ActionParams{Intent: intent},
		argv:         &argv,
		progressText: domain.DraftWritingProgress(intent.Branch),
		draftFlow:    &draftFlowContinuation{intent: intent, offers: offers, update: update},
	}
}

// handleSelectKey routes a KeyMsg to the open SelectOverlay instead of the
// normal focus/activate resolution (Update checks m.selectOverlay != nil
// BEFORE calling handleKey, same as the confirm overlay). Picking the LAST
// question's answer (result.done != nil) runs the mutation straight through
// beginMutation — no confirmation gate, by construction, since nothing in
// this file ever calls ConfirmMutation.
func (m Model) handleSelectKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	value, picked, cancelled := m.selectOverlay.HandleKey(msg.String())
	if cancelled {
		m.selectOverlay = nil
		return m, nil
	}
	if !picked {
		return m, nil
	}
	return m.applySelectResult(m.selectOverlay.OnPick(value))
}
