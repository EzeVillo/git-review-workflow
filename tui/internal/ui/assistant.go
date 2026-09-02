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
//	config --porcelain -- <branch>
//	config --porcelain [--local|--offline] [--delta] -- <branch>
//
// — walked as four SelectOverlay questions (branch, source, range, layout),
// each one offering ONLY what the CLI reports as viable for that exact
// combination (the `offer`/`candidate`/`delta` records, never a fixed list
// this client invents). All three probes are `config`, always class Read
// (never Network) — domain.ClassForVerb already classifies `config` that
// way regardless of args.
//
// The LAST question's answer runs startReview directly: no confirmation in
// between (T069's own gate — startReview is not confirms: true, and this
// file never calls ConfirmMutation for it), matching "the assistant already
// asks four questions" in confirms.go's own comment on why startReview is
// absent from ConfirmingIDs.

// assistantStepMsg carries one config probe's result back, tagged with the
// function that turns it into the NEXT question — the same "what to build
// next" pattern SelectOverlay.OnPick uses for a step that needs no probe.
type assistantStepMsg struct {
	activityGeneration int
	result             host.Result
	build              func(domain.ConfigPorcelainResult) SelectOverlay
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

// startAssistant is startReview's entry point (activateControl): the FIRST
// probe, unscoped, whose candidates seed the branch question.
func (m Model) startAssistant() (Model, tea.Cmd) {
	return m.beginAssistantProbe(configProbeCmd(nil, buildBranchStep(m.preferredStartSource)))
}

func (m Model) beginAssistantProbe(probe tea.Cmd) (Model, tea.Cmd) {
	m.activityGeneration++
	generation := m.activityGeneration
	m.progressOverlay = &ProgressOverlay{Text: domain.ReadOptionsProgress}
	m.selectOverlay = nil
	return m, func() tea.Msg {
		msg := probe().(assistantStepMsg)
		msg.activityGeneration = generation
		return msg
	}
}

// handleAssistantStep resolves one assistantStepMsg: a failed probe reports
// itself on the status line (same failureMessage this file's mutations use)
// and leaves the picker closed; a successful one builds and opens the next
// SelectOverlay.
func (m Model) handleAssistantStep(msg assistantStepMsg) (Model, tea.Cmd) {
	if msg.activityGeneration != 0 && msg.activityGeneration != m.activityGeneration {
		return m, nil
	}
	m.progressOverlay = nil
	if mutationFailed(msg.result) {
		m.statusLine = failureMessage("startReview", msg.result)
		m.selectOverlay = nil
		return m, nil
	}
	cfg := domain.ParseConfigPorcelain(msg.result.Stdout)
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
				return selectResult{cmd: configProbeCmd(
					[]string{"--", branch},
					buildSourceStep(branch, preferredSource, candidates),
				)}
			},
		}
	}
}

// buildSourceStep is question 2: where the tip comes from. Viability comes
// from the FIRST probe's candidates for this branch (does a remote row
// exist? a local one?) — the second, branch-scoped probe's own job is the
// `delta` records the range question needs, not re-answering "remote or
// local", which the unscoped probe already knows. reviewui.startsource
// (FR-061) only pre-positions the cursor; it never hides an option the CLI
// did not itself rule out.
func buildSourceStep(branch, preferredSource string, candidates []domain.CandidateBranch) func(domain.ConfigPorcelainResult) SelectOverlay {
	return func(cfg domain.ConfigPorcelainResult) SelectOverlay {
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
		deltas := cfg.Deltas
		return SelectOverlay{
			Title:  domain.StartAssistantSourceTitle,
			Items:  items,
			Cursor: cursor,
			OnPick: func(source string) selectResult {
				return selectResult{next: buildRangeStep(branch, source, deltas)}
			},
		}
	}
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
			return selectResult{cmd: configProbeCmd(
				sourceRangeProbeArgs(source, rng, branch),
				buildLayoutStep(branch, source, rng),
			)}
		},
	}
	return &overlay
}

// sourceRangeProbeArgs builds the THIRD probe's scoping flags — the same
// order IntentToArgs uses for the real `start` invocation (source flag,
// then --delta, then `-- branch`), so the offers it reports are for the
// EXACT combination the final start will run.
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
		offered := map[domain.OfferID]bool{}
		for _, o := range cfg.Offers {
			offered[o.ID] = true
		}
		var items []SelectItem
		if offered[domain.OfferWalk] {
			items = append(items, SelectItem{Label: domain.LayoutWalkLabel, Value: "walk"})
		}
		if offered[domain.OfferKeys] {
			items = append(items, SelectItem{Label: domain.LayoutKeysLabel, Value: "keys"})
		}
		if offered[domain.OfferStep] {
			items = append(items, SelectItem{Label: domain.LayoutStepLabel, Value: "step"})
		}
		if offered[domain.OfferWhole] {
			items = append(items, SelectItem{Label: domain.LayoutWholeLabel, Value: "whole"})
		}
		return SelectOverlay{
			Title: domain.StartAssistantLayoutTitle,
			Items: items,
			OnPick: func(layout string) selectResult {
				intent := domain.ReviewIntent{Branch: branch, Source: source, Range: rng, Layout: layout}
				req := mutationRequest{action: "startReview", params: domain.ActionParams{Intent: intent}}
				return selectResult{done: &req}
			},
		}
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
