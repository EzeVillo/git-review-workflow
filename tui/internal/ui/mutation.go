package ui

import (
	"context"
	"strings"
	"time"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	tea "github.com/charmbracelet/bubbletea"
)

// mutationRequest is what a confirmed (or non-confirming) activation is
// about to run: the domain action id plus whatever ActionParams it needs to
// build its argv (domain.BuildArgv). Kept as data, not a closure, so
// *ConfirmOverlay and SelectOverlay's OnPick results stay plain values a
// test can construct and inspect directly.
type mutationRequest struct {
	action string
	params domain.ActionParams
}

// silenceWindowMsg is the timer contracts/refresh.md's post-mutation grace
// window fires (host.SilenceWindow after a mutation's own End()). gen ties
// it to the exact mutation whose End() armed it — host.MutationLock.
// WindowClosed rejects a stale one, the same guard shape pollFloorMsg's own
// gen already uses in this file for the same reason.
type silenceWindowMsg struct{ gen int }

func silenceWindowCmd(gen int) tea.Cmd {
	return tea.Tick(host.SilenceWindow, func(time.Time) tea.Msg {
		return silenceWindowMsg{gen: gen}
	})
}

// mutationCmd is the ONE place a mutation's own process is spawned — a
// plain function returning a closure for bubbletea to run LATER, never a
// method on Model, so program_test.go's AST sweep (Update/handleKey/
// handleMouse must never call host.* directly) stays satisfied by
// construction, exactly like readCmd().
func mutationCmd(req mutationRequest, argv domain.Argv) tea.Cmd {
	return func() tea.Msg {
		result := host.InvokeReview(context.Background(), argv.Verb, argv.Args)
		return mutationDoneMsg{action: req.action, params: req.params, result: result}
	}
}

// currentStateToken builds a domain.StateToken from p — used both to
// CAPTURE a token (when a gesture opens a confirmation or picker, or right
// before a non-confirming mutation's own spawn) and to REVALIDATE one
// (T065, inside beginMutation).
func currentStateToken(p domain.PanelModel) domain.StateToken {
	if p.Situation == domain.SituationReview || p.Situation == domain.SituationFinishConflict {
		return domain.StateToken{
			Branch: p.Branch, HasBranch: true,
			Tip: p.Tip, HasTip: p.Tip != "",
			Situation: p.Situation,
		}
	}
	return domain.StateToken{Situation: p.Situation}
}

// beginMutation is where the lock actually lives: Begin() first — depth 1,
// a second mutation while one runs is discarded with a notice, never
// queued (contracts/refresh.md, User Story 5 escenario 6) — THEN, inside
// the lock and before the spawn, the StateToken is revalidated (T065): a
// stale token cancels the lock right back without ever spawning a process,
// since nothing ran that a silence window would need to wait out for.
func (m Model) beginMutation(req mutationRequest, token domain.StateToken) (Model, tea.Cmd) {
	if !m.lock.Begin() {
		m.statusLine = domain.MutationDiscardedNotice
		return m, nil
	}
	if !token.Matches(currentStateToken(m.Panel)) {
		m.lock.Cancel()
		m.statusLine = domain.StaleNotice
		return m, nil
	}
	argv, ok := domain.BuildArgv(req.action, req.params)
	if !ok {
		m.lock.Cancel()
		return m, nil
	}
	m.statusLine = ""
	return m, mutationCmd(req, argv)
}

// mutationFailed reports whether a mutation's result counts as a failure
// for status-line purposes: a non-zero exit, a timeout, or a spawn that
// never started.
func mutationFailed(r host.Result) bool {
	return r.TimedOut || r.SpawnFailed || r.ExitCode != 0
}

// flattenStderr joins non-empty, trimmed stderr lines with a single space —
// the same shape every one of the three IDE clients' toasts use for the
// same reason: a multi-line stderr block reads worse as a one-line status
// than as itself, but a status LINE cannot hold multiple lines at all.
func flattenStderr(stderr string) string {
	var parts []string
	for _, line := range strings.Split(stderr, "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			parts = append(parts, line)
		}
	}
	return strings.Join(parts, " ")
}

// genericFailureText is the fallback shown ONLY when the CLI died without
// any stderr at all (FR-024's "los fallbacks de error dicen qué no pasó, no
// qué comando falló" — with stderr present, nothing here is ever touched).
var genericFailureText = map[string]string{
	"finishReview":   "Could not finish the review.",
	"undoFinish":     "Could not undo the finish.",
	"resumeFinish":   "Could not continue the finish.",
	"abortReview":    "Could not cancel the review.",
	"saveReview":     "Could not save the review for later.",
	"continueReview": "Could not resume the review.",
	"setBase":        "Could not change the base branch.",
	"setRemote":      "Could not change the remote.",
	"next":           "Could not move to the next entry.",
	"prev":           "Could not move to the previous entry.",
	"startReview":    "Could not start the review.",
}

func failureMessage(action string, r host.Result) string {
	if r.TimedOut {
		return "That command timed out."
	}
	if text := flattenStderr(r.Stderr); text != "" {
		return text
	}
	if text, ok := genericFailureText[action]; ok {
		return text
	}
	return "Could not complete that action."
}

// pendingFinishOutcome is what a successful finishReview leaves for the
// NEXT readDoneMsg to resolve into a status-line message (T074): whether
// the fresh read shows finish-pending (the banner already says it — no
// message needed) or not (the "no-edits" residual the other three clients
// toast, since nothing else on screen would say it otherwise). source/onto
// are captured at the MOMENT finishReview was invoked, never re-derived
// later: by the time the fresh read lands, if the outcome IS "no-edits" the
// panel has already left the review situation and PanelModel.Source is gone
// with it (domain/project.go never populates Source outside
// SituationReview/SituationFinishConflict).
type pendingFinishOutcome struct {
	source string
	onto   bool
}

func (o pendingFinishOutcome) destination() string {
	if o.onto {
		return o.source
	}
	return "review-fixes/" + o.source
}

// mutationDoneMsg carries one CLI mutation's result back, tagged with WHAT
// was asked (action+params) rather than just the raw host.Result: deciding
// the status line, and undoFinish's --force follow-up, depends on what was
// requested — never on parsing the verb's own stdout (FR-013).
type mutationDoneMsg struct {
	action string
	params domain.ActionParams
	result host.Result
}

// handleMutationDone is the mutation cycle's own end: the lock's End()
// always happens (disparador 1 is never suppressed — contracts/refresh.md's
// table), then either a stronger confirmation is offered (undoFinish's
// --force retry, and ONLY after seeing THIS attempt's own stderr ask for
// it — never as a first choice, prohibition 8) or the status line is set
// from what happened, and finally the guaranteed immediate read plus the
// silence-window timer are both scheduled — SC-004's own mechanism, not
// re-implemented here.
func (m Model) handleMutationDone(msg mutationDoneMsg) (Model, tea.Cmd) {
	gen := m.lock.End()

	// Cleared UNCONDITIONALLY for every action but finishReview's own — the
	// lock's depth-1 guard only blocks a SECOND mutation while the first is
	// still running, and busy drops the instant End() runs above, so a
	// completely unrelated mutation (next/prev, say) can legitimately start
	// and finish before finishReview's own scheduled read ever lands. Left
	// alone, that unrelated success would resolve THIS finishReview's
	// pending outcome by accident.
	if msg.action != "finishReview" {
		m.pendingFinish = nil
	}

	if overlay, ok := undoFinishForceRetry(msg, m.Panel); ok {
		m.confirm = overlay
	} else if mutationFailed(msg.result) {
		m.statusLine = failureMessage(msg.action, msg.result)
	} else {
		m.statusLine = ""
		if msg.action == "finishReview" {
			outcome := pendingFinishOutcome{source: msg.params.Source, onto: msg.params.OntoSource}
			m.pendingFinish = &outcome
		}
	}

	m2, readCmd := m.scheduleRead()
	return m2, tea.Batch(readCmd, silenceWindowCmd(gen))
}

// undoFinishForceRetry recognizes the ONE case where a failed mutation
// opens a SECOND, stronger confirmation instead of just reporting the
// failure: a plain `finish --abort` that failed because the CLI's own
// stderr names --force as the way out (contracts/cli-invocation.md
// prohibition 8: --force is never the first choice). The retry request
// carries Force: true so, if accepted, beginMutation builds `finish --abort
// --force` — domain.BuildArgv's own doc on undoFinish.
func undoFinishForceRetry(msg mutationDoneMsg, panel domain.PanelModel) (*ConfirmOverlay, bool) {
	if msg.action != "undoFinish" || msg.params.Force {
		return nil, false
	}
	if !mutationFailed(msg.result) {
		return nil, false
	}
	text := flattenStderr(msg.result.Stderr)
	if text == "" || !strings.Contains(text, "--force") {
		return nil, false
	}
	overlay := ConfirmMutation(
		"undoFinish", text, domain.DiscardWorkAndUndoDetail, domain.DiscardWorkAndUndoLabel,
		currentStateToken(panel),
		mutationRequest{action: "undoFinish", params: domain.ActionParams{Force: true}},
	)
	return overlay, true
}

// --- per-control entry points -----------------------------------------------
//
// Everything below is what IntentActivate/IntentBoundAction in program.go
// dispatches to. None of them is named Update/handleKey/handleMouse, so
// program_test.go's AST sweep never inspects their bodies — the same
// exemption readCmd() already relies on.

// activateControl is what IntentActivate resolves to for a body control
// (Enter on the focused row, or a click — once Phase 8 wires clicks to the
// same activation).
func (m Model) activateControl(id domain.ControlID, variant string) (Model, tea.Cmd) {
	switch id {
	case "undoFinish":
		return m.beginUndoFinish()
	case "resumeFinish":
		return m.beginResumeFinish()
	case "setBase":
		return m.beginSetBase()
	case "setRemote":
		return m.beginSetRemote()
	case "startReview":
		return m.startAssistant()
	case "next":
		return m.beginCursor("next")
	case "prev":
		return m.beginCursor("prev")
	}
	return m, nil
}

// activateBoundAction is what IntentBoundAction resolves to for a
// dedicated key outside the focus ring — finishReview/saveReview/
// abortReview are `surface: both` in the canonical (a title-bar action in
// the three IDE clients) but panel_layout: never draws them as a body row,
// so a terminal without a title bar exposes them the way it exposes
// refresh: a reserved key, shown in the key bar only when the current
// situation allows it (keys.go's KeyBarFor).
func (m Model) activateBoundAction(action string) (Model, tea.Cmd) {
	switch action {
	case "finishReview":
		return m.beginFinish()
	case "saveReview":
		return m.beginSave()
	case "abortReview":
		return m.beginAbort()
	}
	return m, nil
}

// beginUndoFinish, beginSave and beginAbort each call ConfirmMutation
// DIRECTLY with a literal id — never through a shared wrapper that would
// forward a variable — because gate 2 (T067, scripts/check-client-product-
// surface.mjs) reads the FIRST ARGUMENT of the call site as source text: a
// wrapper taking `action string` would hide every one of these ids from
// that regex, the same hole an `includes` scan already proved unsafe for
// (confirms.go's own comment on why VS Code's gate reads the call site and
// not a name search).
func (m Model) beginUndoFinish() (Model, tea.Cmd) {
	if m.Panel.Situation != domain.SituationFinishPending && m.Panel.Situation != domain.SituationFinishConflict {
		return m, nil
	}
	detail := domain.UndoFinishConfirmDetailFinishPending
	if m.Panel.Situation == domain.SituationFinishConflict {
		detail = domain.UndoFinishConfirmDetailConflict
	}
	req := mutationRequest{action: "undoFinish", params: domain.ActionParams{}}
	m.confirm = ConfirmMutation("undoFinish", domain.UndoFinishConfirmTitleFinishPending, detail, domain.UndoFinishLabel, currentStateToken(m.Panel), req)
	return m, nil
}

// resumeOnto derives resumeFinish's --onto-source flag from the porcelain's
// OWN `finish` record (contracts/cli-invocation.md's own note), never from
// a value remembered from the ORIGINAL finish attempt: this process can
// restart between the conflict and the resume, and an in-memory value would
// silently send the edits to the wrong place then.
func resumeOnto(r host.ReadResult) bool {
	return r.HasStatus && r.Status.Finish != nil && r.Status.Finish.Onto
}

func (m Model) beginResumeFinish() (Model, tea.Cmd) {
	if m.Panel.Situation != domain.SituationFinishConflict {
		return m, nil
	}
	params := domain.ActionParams{OntoSource: resumeOnto(m.lastRead)}
	return m.beginMutation(mutationRequest{action: "resumeFinish", params: params}, currentStateToken(m.Panel))
}

func (m Model) beginSave() (Model, tea.Cmd) {
	if m.Panel.Situation != domain.SituationReview {
		return m, nil
	}
	title := interpolate(domain.SaveReviewConfirmTitle, "{source}", m.Panel.Source)
	req := mutationRequest{action: "saveReview", params: domain.ActionParams{}}
	m.confirm = ConfirmMutation("saveReview", title, domain.SaveReviewConfirmDetail, domain.SaveForLaterLabel, currentStateToken(m.Panel), req)
	return m, nil
}

func (m Model) beginAbort() (Model, tea.Cmd) {
	if m.Panel.Situation != domain.SituationReview && m.Panel.Situation != domain.SituationFinishConflict {
		return m, nil
	}
	title := interpolate(domain.AbortReviewConfirmTitle, "{source}", m.Panel.Source)
	req := mutationRequest{action: "abortReview", params: domain.ActionParams{}}
	m.confirm = ConfirmMutation("abortReview", title, domain.AbortReviewConfirmDetail, domain.CancelReviewLabel, currentStateToken(m.Panel), req)
	return m, nil
}

func (m Model) beginFinish() (Model, tea.Cmd) {
	if m.Panel.Situation != domain.SituationReview || m.Panel.Readonly {
		return m, nil
	}
	source := m.Panel.Source
	overlay := SelectOverlay{
		Title: domain.FinishDestinationTitle,
		Items: []SelectItem{
			{Label: domain.FinishDestinationBranchLabel, Detail: domain.FinishDestinationBranchDetail, Value: "fixes"},
			{Label: domain.FinishDestinationOntoLabel, Detail: domain.FinishDestinationOntoDetail, Value: "onto"},
		},
		OnPick: func(v string) selectResult {
			req := mutationRequest{action: "finishReview", params: domain.ActionParams{OntoSource: v == "onto", Source: source}}
			return selectResult{done: &req}
		},
	}
	m.selectOverlay = &overlay
	return m, nil
}

// beginCursor wires next/prev to the review cursor (T073): only inside a
// review that actually has one (hasReviewCursor in keys.go already keeps
// n/p from resolving anywhere else), and disabled at the extremes exactly
// like the body's own icon buttons (controls.go: Enabled: !m.AtFirst /
// !m.AtLast) — Enter on a disabled control never reaches here at all
// (keys.go's activateFocused), but n/p bypass focus entirely, so the same
// guard is repeated here.
func (m Model) beginCursor(action string) (Model, tea.Cmd) {
	if m.Panel.Situation != domain.SituationReview {
		return m, nil
	}
	if action == "next" && m.Panel.AtLast {
		return m, nil
	}
	if action == "prev" && m.Panel.AtFirst {
		return m, nil
	}
	return m.beginMutation(mutationRequest{action: action}, currentStateToken(m.Panel))
}

func (m Model) beginSetBase() (Model, tea.Cmd) {
	if !m.lastRead.HasConfig || len(m.lastRead.Config.Candidates) == 0 {
		m.statusLine = domain.NoBaseCandidates
		return m, nil
	}
	overlay := SelectOverlay{
		Title: domain.SetBaseTitle,
		Items: branchItems(domain.BranchPickerItems(m.lastRead.Config.Candidates)),
		OnPick: func(name string) selectResult {
			req := mutationRequest{action: "setBase", params: domain.ActionParams{Name: name}}
			return selectResult{done: &req}
		},
	}
	m.selectOverlay = &overlay
	return m, nil
}

func (m Model) beginSetRemote() (Model, tea.Cmd) {
	if !m.lastRead.HasConfig || len(m.lastRead.Config.Remotes) == 0 {
		return m, nil
	}
	items := make([]SelectItem, 0, len(m.lastRead.Config.Remotes))
	for _, r := range m.lastRead.Config.Remotes {
		items = append(items, SelectItem{Label: r.Name, Value: r.Name})
	}
	overlay := SelectOverlay{
		Title: domain.SetRemoteTitle,
		Items: items,
		OnPick: func(name string) selectResult {
			req := mutationRequest{action: "setRemote", params: domain.ActionParams{Name: name}}
			return selectResult{done: &req}
		},
	}
	m.selectOverlay = &overlay
	return m, nil
}

// branchItems adapts BranchPickerItems' collapsed candidates into
// SelectItems, shared by the start assistant's branch step and setBase's
// picker (contracts/cli-invocation.md: the same `candidate` records serve
// both questions — bin/git-review-lib.sh's candidate_branches emits "every
// branch eligible to start a review on", which is the same universe a base
// is picked from).
func branchItems(candidates []domain.CandidateBranch) []SelectItem {
	items := make([]SelectItem, 0, len(candidates))
	for _, c := range candidates {
		items = append(items, SelectItem{Label: c.Name, Value: c.Name})
	}
	return items
}

// handleConfirmKey routes a KeyMsg to the open ConfirmOverlay instead of the
// normal focus/activate resolution — Update checks m.confirm != nil BEFORE
// calling handleKey, so the base panel's own controls are inert while this
// is open, which is what makes a full-frame Render() an honest substitute
// for a real overlay.
func (m Model) handleConfirmKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	choice, resolved := m.confirm.HandleKey(msg.String())
	if !resolved {
		return m, nil
	}
	overlay := m.confirm
	m.confirm = nil
	if choice != domain.ConfirmAccepted {
		return m, nil
	}
	return m.beginMutation(overlay.Pending, overlay.Token)
}
