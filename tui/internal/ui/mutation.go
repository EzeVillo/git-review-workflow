package ui

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
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
//
// argv: pre-built, for the footer's row-only controls (createGuide,
// discardGuide, discardDraft, discardFixes, discardAllFixes) — these are
// not among the 26 product actions BuildArgv's own doc calls a closed list
// (actions.go's "row controls with their own CLI call, not among the 27"),
// so beginMutation uses this instead of BuildArgv(action, params) when it is
// set. action still travels for genericFailureText and mutationDoneMsg's own
// bookkeeping either way.
type mutationRequest struct {
	action          string
	params          domain.ActionParams
	argv            *domain.Argv
	successOpenPath string
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
func mutationCmd(req mutationRequest, argv domain.Argv, activityGeneration int) tea.Cmd {
	return func() tea.Msg {
		result := host.InvokeReview(context.Background(), argv.Verb, argv.Args)
		return mutationDoneMsg{action: req.action, params: req.params, result: result, activityGeneration: activityGeneration, successOpenPath: req.successOpenPath}
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
	var argv domain.Argv
	if req.argv != nil {
		argv = *req.argv
	} else {
		a, ok := domain.BuildArgv(req.action, req.params)
		if !ok {
			m.lock.Cancel()
			return m, nil
		}
		argv = a
	}
	m.statusLine = ""
	var activityCmd tea.Cmd
	m, activityCmd = m.startActivity(activityMutation, domain.ProgressText(req.action, req.params), true)
	return m, tea.Batch(mutationCmd(req, argv, m.activity.generation), activityCmd)
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
	"startFromDraft": "Could not start the review.",
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

// matchesPending reports whether the accepted repository-wide list result
// still contains the pending finish for this exact source. Another review's
// pending record is real global UI state, but not this outcome's result.
func (o pendingFinishOutcome) matchesPending(result host.ReadResult) bool {
	if result.Situation != domain.SituationFinishPending || !result.HasList {
		return false
	}
	for _, branch := range result.Branches {
		if branch.Finish != nil && branch.Finish.State == "pending" && domain.SourceOf(branch) == o.source {
			return true
		}
	}
	return false
}

// mutationDoneMsg carries one CLI mutation's result back, tagged with WHAT
// was asked (action+params) rather than just the raw host.Result: deciding
// the status line, and undoFinish's --force follow-up, depends on what was
// requested — never on parsing the verb's own stdout (FR-013).
type mutationDoneMsg struct {
	action             string
	params             domain.ActionParams
	result             host.Result
	activityGeneration int
	successOpenPath    string
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
	if msg.activityGeneration != 0 {
		m = m.clearActivity(msg.activityGeneration)
	}
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
		if msg.successOpenPath != "" {
			m.pendingOpenPath = msg.successOpenPath
		}
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
	case "copyCliInstall":
		return m.beginCopyCliInstall()
	case "installCli", "openSupport":
		return m.beginOpenExternal(id, variant)
	case "copyDraftPrompt":
		return m.beginCopyDraftPrompt(variant)
	case "startFromDraft":
		return m.beginStartFromDraft(variant)
	case "openDraft", "openWalkthrough", "openGuide":
		return m.beginOpenReportedPath(id, variant)
	case "copyWalkthroughPrompt":
		return m.beginCopyWalkthroughPrompt()
	case "openEntry":
		return m.beginOpenEntry()
	case "openChange":
		return m.beginOpenChange()
	case "showWhy":
		return m.beginShowWhy(variant)
	case "outOfRangeHelp":
		return m.beginOutOfRangeHelp()
	case "compareReview":
		return m.beginCompareReview()
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
	case "cleanReview":
		return m.beginCleanReview()
	case "continueReview":
		return m.beginContinueReview(variant)
	case "discardInventory":
		return m.beginDiscardInventory(variant)
	case "discardDraft":
		return m.beginDiscardDraft(variant)
	case "discardGuide":
		return m.beginDiscardGuide(variant)
	case "createGuide":
		return m.beginCreateGuide(variant)
	case "discardFixes":
		return m.beginDiscardFixes(variant)
	case "discardAllFixes":
		return m.beginDiscardAllFixes()
	case "walkthroughBuild":
		return m.beginWalkthroughBuild()
	case "walkthroughInit":
		return m.beginWalkthroughInit()
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
	req := mutationRequest{action: "saveReview", params: domain.ActionParams{Source: m.Panel.Source}}
	m.confirm = ConfirmMutation("saveReview", title, domain.SaveReviewConfirmDetail, domain.SaveForLaterLabel, currentStateToken(m.Panel), req)
	return m, nil
}

func (m Model) beginAbort() (Model, tea.Cmd) {
	if m.Panel.Situation != domain.SituationReview && m.Panel.Situation != domain.SituationFinishConflict {
		return m, nil
	}
	title := interpolate(domain.AbortReviewConfirmTitle, "{source}", m.Panel.Source)
	req := mutationRequest{action: "abortReview", params: domain.ActionParams{Source: m.Panel.Source}}
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

// startFromDraftRequest constructs the start invocation from the selected
// fresh draft's OWN porcelain fields. Its source/range are records of how the
// draft was made, not values inferred from the currently checked-out branch.
func startFromDraftRequest(d draftRowView) mutationRequest {
	intent := domain.ReviewIntent{
		Branch: d.src,
		Source: d.source,
		Range:  d.rrange,
		Layout: "walk",
	}
	argv := domain.Argv{Verb: "start", Args: domain.StartFromDraftArgs(intent)}
	return mutationRequest{action: "startFromDraft", params: domain.ActionParams{Intent: intent}, argv: &argv}
}

// beginStartFromDraft starts only a CURRENT, complete draft: a variant is the
// draft's raw source identifier, so re-resolving it against the fresh rows
// protects against a moved or replaced footer row. This is a start, not a
// destructive action, and therefore enters the existing mutation lock without
// a confirmation overlay.
func (m Model) beginStartFromDraft(src string) (Model, tea.Cmd) {
	if m.Panel.Situation != domain.SituationNoReview {
		return m, nil
	}
	draft, ok := findDraftRow(decodeDraftRows(m.Panel.FreshDraftRows), src)
	if !ok || !draft.startable() {
		return m, nil
	}
	return m.beginMutation(startFromDraftRequest(draft), currentStateToken(m.Panel))
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

// --- the footer's mutations (Phase 7, T081-T082) ---------------------------
//
// Every row-targeted handler below re-reads its target from m.Panel's own
// footer fields BY THE SAME NAME the control's Variant carries — never by
// remembering a position — so a row that moved between the gesture and the
// confirmation still names the one the reviewer actually meant.

// beginCleanReview: finish-pending's "Done, clean up" (`clean --keep-fixes
// <source>`). No row to resolve — the pending finish is the repository's
// own, from PanelModel.Source/FinishDestination (project.go's own doc on
// why Source is reused here instead of re-deriving it).
func (m Model) beginCleanReview() (Model, tea.Cmd) {
	if m.Panel.Situation != domain.SituationFinishPending || m.Panel.Source == "" {
		return m, nil
	}
	source := m.Panel.Source
	title := interpolate(domain.CleanReviewConfirmTitle, "{source}", source)
	detail := interpolate(domain.CleanReviewConfirmDetail, "{destination}", m.Panel.FinishDestination)
	hk := domain.HousekeepingAction{Kind: domain.CleanKeepFixes, Source: source}
	req := mutationRequest{action: "cleanReview", params: domain.ActionParams{Housekeeping: hk}}
	m.confirm = ConfirmMutation("cleanReview", title, detail, domain.DoneLabel, currentStateToken(m.Panel), req)
	return m, nil
}

// beginContinueReview resumes the saved review named by variant.
func (m Model) beginContinueReview(name string) (Model, tea.Cmd) {
	row, ok := findInventoryRow(decodeInventoryRows(m.Panel.InventoryRows), name)
	if !ok || !row.saved || !row.resumable {
		return m, nil
	}
	source := domain.SourceOf(domain.BranchRecord{Name: row.name})
	title := interpolate(domain.ContinueReviewConfirmTitle, "{source}", source)
	req := mutationRequest{action: "continueReview", params: domain.ActionParams{Source: source}}
	detail := interpolate(domain.ContinueReviewConfirmDetail, "{source}", source)
	m.confirm = ConfirmMutation("continueReview", title, detail, domain.ContinueLabel, currentStateToken(m.Panel), req)
	return m, nil
}

// beginDiscardInventory deletes the review named by variant: `forget
// --saved <source>` for a paused one, `clean <source>` for a leftover
// active/broken one — the same split panelModel.ts's toPanelReviews and
// forgetReview.ts's discardInventoryReview make.
func (m Model) beginDiscardInventory(name string) (Model, tea.Cmd) {
	row, ok := findInventoryRow(decodeInventoryRows(m.Panel.InventoryRows), name)
	if !ok || !row.canDiscard() {
		return m, nil
	}
	source := domain.SourceOf(domain.BranchRecord{Name: row.name})
	var title, detail string
	var kind domain.HousekeepingKind
	if row.saved {
		title = interpolate(domain.DiscardSavedReviewConfirmTitle, "{source}", source)
		detail = domain.DiscardSavedReviewConfirmDetail
		kind = domain.ForgetSavedOne
	} else {
		title = interpolate(domain.DiscardOneReviewConfirmTitle, "{source}", source)
		detail = domain.DiscardOneReviewConfirmDetail
		kind = domain.CleanOne
	}
	hk := domain.HousekeepingAction{Kind: kind, Source: source}
	req := mutationRequest{action: "discardInventory", params: domain.ActionParams{Housekeeping: hk}}
	m.confirm = ConfirmMutation("discardInventory", title, detail, domain.DiscardLabel, currentStateToken(m.Panel), req)
	return m, nil
}

// beginDiscardDraft deletes the loose draft named by variant (`forget
// --draft <src>`), fresh or spent alike — a spent row keeps this control
// exactly because a review being over does not make its written-out reading
// order disappear on its own (CLAUDE.md: forget is the one verb that does).
func (m Model) beginDiscardDraft(src string) (Model, tea.Cmd) {
	d, ok := findDraftRow(decodeDraftRows(m.Panel.FreshDraftRows), src)
	if !ok {
		d, ok = findDraftRow(decodeDraftRows(m.Panel.SpentDraftRows), src)
	}
	if !ok {
		return m, nil
	}
	title := interpolate(domain.DiscardDraftConfirmTitle, "{source}", src)
	detail := interpolate(domain.DiscardDraftConfirmDetail, "{path}", d.path)
	argv := domain.Argv{
		Verb: domain.VerbForHousekeeping(domain.ForgetDraftOne),
		Args: domain.ArgsForHousekeeping(domain.HousekeepingAction{Kind: domain.ForgetDraftOne, Source: src}),
	}
	req := mutationRequest{action: "discardDraft", params: domain.ActionParams{Source: src}, argv: &argv}
	m.confirm = ConfirmMutation("discardDraft", title, detail, domain.DiscardConfirmLabel, currentStateToken(m.Panel), req)
	return m, nil
}

// beginDiscardGuide deletes the REVIEWER'S OWN guide (`walkthrough guide
// --delete`) — variant is always "own": guide_rows.controls declares
// discardGuide only_in_row: own, and noReviewControls never emits it for
// "team" (the shared guide is a tracked file; the CLI itself refuses
// --delete --team).
func (m Model) beginDiscardGuide(variant string) (Model, tea.Cmd) {
	if variant != "own" || m.Panel.OwnGuideState == domain.GuideAbsent {
		return m, nil
	}
	detail := interpolate(domain.DiscardGuideConfirmDetail, "{path}", m.Panel.OwnGuideRow)
	argv := domain.Argv{Verb: "walkthrough", Args: domain.DiscardGuideArgs()}
	req := mutationRequest{action: "discardGuide", argv: &argv}
	m.confirm = ConfirmMutation("discardGuide", domain.DiscardGuideConfirmTitle, detail, domain.DiscardConfirmLabel, currentStateToken(m.Panel), req)
	return m, nil
}

// beginCreateGuide asks the CLI to create the (empty) guide named by variant
// ("team"/"own") — not confirms: true in the canonical (RequiresConfirmation
// says so), so this goes straight to beginMutation, no overlay at all.
func (m Model) beginCreateGuide(variant string) (Model, tea.Cmd) {
	req, ok := createGuideRequest(m.Panel, variant)
	if !ok {
		return m, nil
	}
	return m.beginMutation(req, currentStateToken(m.Panel))
}

func createGuideRequest(panel domain.PanelModel, variant string) (mutationRequest, bool) {
	var path string
	var team bool
	switch variant {
	case "team":
		if panel.TeamGuideState != domain.GuideAbsent {
			return mutationRequest{}, false
		}
		path, team = panel.TeamGuideRow, true
	case "own":
		if panel.OwnGuideState != domain.GuideAbsent {
			return mutationRequest{}, false
		}
		path = panel.OwnGuideRow
	default:
		return mutationRequest{}, false
	}
	argv := domain.Argv{Verb: "walkthrough", Args: domain.CreateGuideArgs(team)}
	return mutationRequest{
		action: "createGuide", params: domain.ActionParams{Team: team}, argv: &argv,
		successOpenPath: path,
	}, true
}

// beginDiscardFixes deletes ONE review-fixes/* branch (`clean --fixes-only
// <source>`) — never the row it is currently standing on
// (fixes_rows.controls' disabled_when: current; noReviewControls already
// disables the control there, this is the same guard repeated for a
// gesture that bypasses focus entirely, the same defensive shape
// beginCursor already uses for n/p at the extremes).
func (m Model) beginDiscardFixes(name string) (Model, tea.Cmd) {
	row, ok := findFixesRow(decodeFixesRows(m.Panel.FixesRows), name)
	if !ok || row.current {
		return m, nil
	}
	source := domain.FixesSourceOf(row.name)
	title := interpolate(domain.DiscardFixesConfirmTitle, "{source}", source)
	detail := domain.DiscardFixesConfirmDetail(domain.FixesState(row.state), row.session)
	argv := domain.Argv{
		Verb: domain.VerbForHousekeeping(domain.CleanFixesOne),
		Args: domain.ArgsForHousekeeping(domain.HousekeepingAction{Kind: domain.CleanFixesOne, Source: source}),
	}
	req := mutationRequest{action: "discardFixes", argv: &argv}
	m.confirm = ConfirmMutation("discardFixes", title, detail, domain.DiscardLabel, currentStateToken(m.Panel), req)
	return m, nil
}

// beginDiscardAllFixes runs `clean --fixes-only` with NO branch — always,
// even with a stale read: the argv cannot depend on a datum re-read on
// every refresh (fixes_rows' own comment on why this is safe: clean's own
// scoping never touches a live review/*), so there is nothing here to
// re-resolve against m.Panel at all.
func (m Model) beginDiscardAllFixes() (Model, tea.Cmd) {
	argv := domain.Argv{
		Verb: domain.VerbForHousekeeping(domain.CleanFixesOneAll),
		Args: domain.ArgsForHousekeeping(domain.HousekeepingAction{Kind: domain.CleanFixesOneAll}),
	}
	req := mutationRequest{action: "discardAllFixes", argv: &argv}
	m.confirm = ConfirmMutation("discardAllFixes", domain.DiscardAllFixesConfirmTitle, domain.DiscardAllFixesConfirmDetail, domain.DeleteAllLabel, currentStateToken(m.Panel), req)
	return m, nil
}

// beginWalkthroughBuild: `walkthrough build`, a plain yes/no confirm (unlike
// its sibling walkthroughInit below).
func (m Model) beginWalkthroughBuild() (Model, tea.Cmd) {
	req := mutationRequest{action: "walkthroughBuild"}
	m.confirm = ConfirmMutation("walkthroughBuild", domain.WalkthroughBuildConfirmTitle, domain.WalkthroughBuildConfirmDetail, domain.WalkthroughBuildLabel, currentStateToken(m.Panel), req)
	return m, nil
}

// beginWalkthroughInit is confirms.go's ONE declared exception to the
// single confirmation gate: it never calls ConfirmMutation. With nothing to
// preserve (no record at all, or the file is absent) or nothing worth
// asking about (superseded — the CLI starts over on its own for a merged
// PR's leftover file), `init` just runs; only a genuinely reconcilable file
// (in-sync/stale/unknown) opens the two-course SelectOverlay picker
// (walkthrough_row.init_choice) — a CHOICE, not a confirmation, which is
// exactly why this is the one id confirms.go excuses from the gate.
func (m Model) beginWalkthroughInit() (Model, tea.Cmd) {
	reconcilable := m.Panel.HasWalkthroughRow &&
		m.Panel.WalkthroughState != domain.WalkthroughAbsent &&
		m.Panel.WalkthroughState != domain.WalkthroughSuperseded
	if !reconcilable {
		req := mutationRequest{action: "walkthroughInit", params: domain.ActionParams{WalkthroughForce: false}}
		return m.beginMutation(req, currentStateToken(m.Panel))
	}
	overlay := SelectOverlay{
		Title: domain.WalkthroughInitChoiceTitle,
		Items: []SelectItem{
			{Label: domain.WalkthroughUpdateLabel, Detail: domain.WalkthroughUpdateDetail, Value: "update"},
			{Label: domain.WalkthroughStartOverLabel, Detail: domain.WalkthroughStartOverDetail, Value: "force"},
		},
		OnPick: func(v string) selectResult {
			req := mutationRequest{action: "walkthroughInit", params: domain.ActionParams{WalkthroughForce: v == "force"}}
			return selectResult{done: &req}
		},
	}
	m.selectOverlay = &overlay
	return m, nil
}

// handleConfirmKey routes a KeyMsg to the open ConfirmOverlay instead of the
// normal focus/activate resolution — Update checks m.confirm != nil BEFORE
// calling handleKey, so the base panel's own controls are inert while this
// is open, which is what makes a full-frame Render() an honest substitute
// for a real overlay.
// --- the four delegated actions (Phase 8, T089) -----------------------------
//
// openEntry/openChange/previewEdits hand the terminal to a real child
// process via tea.ExecProcess — the equivalent in this client of the
// `watched: on_save` the canonical declares for the walkthrough and the
// guides (research.md Decisión 12): the reviewer could have edited and
// saved inside it, so returning always schedules a refresh.

// execDoneMsg is what every tea.ExecProcess callback in this package
// returns. A normal child exit remains non-fatal (":cq" in vim and diff
// tool exit codes are common), while a launch failure is surfaced because
// the delegated surface never appeared. completion acknowledges work that
// succeeded before delegation, such as creating a guide.
type execDoneMsg struct {
	err        error
	completion string
}

type createdGuideOpenMsg struct {
	path   string
	cmd    *exec.Cmd
	reason string
	ok     bool
}

func createdGuideOpenCmd(path string) tea.Cmd {
	return func() tea.Msg {
		dir, _ := os.Getwd()
		cmd, reason, ok := host.OpenInEditorCmd(path, dir)
		return createdGuideOpenMsg{path: path, cmd: cmd, reason: reason, ok: ok}
	}
}

func execCmd(cmd *exec.Cmd) tea.Cmd {
	return tea.ExecProcess(cmd, func(err error) tea.Msg { return execDoneMsg{err: err} })
}

func execCmdWithCompletion(cmd *exec.Cmd, completion string) tea.Cmd {
	return tea.ExecProcess(cmd, func(err error) tea.Msg {
		return execDoneMsg{err: err, completion: completion}
	})
}

func (m Model) handleExecDone(msg execDoneMsg) (Model, tea.Cmd) {
	if msg.completion != "" {
		m.statusLine = msg.completion
	}
	if msg.err != nil {
		var exitErr *exec.ExitError
		if !errors.As(msg.err, &exitErr) {
			m.statusLine = domain.DelegatedLaunchFailed(msg.completion, msg.err.Error())
		}
	}
	return m.scheduleRead()
}

// beginOpenEntry: $EDITOR on the CURRENT walk entry's DISPLAY path (CLAUDE.md:
// Raw never reaches a tool). Only meaningful in walk mode — ControlsFor
// never draws openEntry outside it.
func (m Model) beginOpenEntry() (Model, tea.Cmd) {
	dir, _ := os.Getwd()
	cmd, reason, ok := host.OpenInEditorCmd(m.Panel.CurrentPath.Display, dir)
	if !ok {
		m.statusLine = reason
		return m, nil
	}
	return m, execCmd(cmd)
}

// beginOpenChange: the current entry's own diff — a single file in walk
// mode, the whole commit in step mode (openChange's own two shapes,
// contracts/cli-invocation.md).
func (m Model) beginOpenChange() (Model, tea.Cmd) {
	dir, _ := os.Getwd()
	var cmd *exec.Cmd
	switch m.Panel.Mode {
	case domain.ModeStep:
		cmd = host.DiffCommitCmd(m.Panel.CurrentSHA, dir)
	default:
		cmd = host.DiffPathCmd(m.Panel.CurrentPath.Display, dir)
	}
	return m, execCmd(cmd)
}

// beginPreviewEdits runs `git review preview` with an inherited terminal and
// records its completion through the central interactive-review policy.
func (m Model) beginPreviewEdits() (Model, tea.Cmd) {
	dir, _ := os.Getwd()
	invocation := host.InteractiveReviewCmd("preview", nil, dir)
	return m, tea.ExecProcess(invocation.Cmd, func(err error) tea.Msg {
		invocation.Complete(err)
		return execDoneMsg{err: err}
	})
}

// The browser-only controls deliberately resolve a small closed set here.
// Their variants are UI identifiers, never a URL supplied by the terminal or
// by porcelain, so no activation can cause an arbitrary external launch.
const installOptionsURL = "https://github.com/EzeVillo/git-review-workflow#readme"

func externalURLForControl(id domain.ControlID, variant string) (string, bool) {
	switch id {
	case "installCli":
		return installOptionsURL, true
	case "openSupport":
		switch variant {
		case "star":
			return domain.SupportStarURL, true
		case "bug":
			return domain.SupportBugURL, true
		}
	}
	return "", false
}

func (m Model) beginOpenExternal(id domain.ControlID, variant string) (Model, tea.Cmd) {
	url, ok := externalURLForControl(id, variant)
	if !ok {
		return m, nil
	}
	return m, execCmd(host.OpenURLCmd(url))
}

// walkthroughPath reads the path the latest porcelain config record reported.
// PanelModel keeps the branch this walkthrough annotates for display, not a
// locally assembled filesystem path, so this preserves the CLI's authority
// over where an existing walkthrough lives.
func (m Model) walkthroughPath() (string, bool) {
	if !m.Panel.HasWalkthroughRow || m.Panel.WalkthroughState == domain.WalkthroughAbsent {
		return "", false
	}
	if !m.lastRead.HasConfig || m.lastRead.Config.Walkthrough == nil {
		return "", false
	}
	w := m.lastRead.Config.Walkthrough
	if w.State == domain.WalkthroughAbsent || w.Path == "" {
		return "", false
	}
	return w.Path, true
}

// reportedEditorPath resolves an enabled row control's raw identifier to the
// path porcelain reported for it. The raw source/kind selects the row; only
// the reported display path reaches $EDITOR.
func (m Model) reportedEditorPath(id domain.ControlID, variant string) (string, bool) {
	switch id {
	case "openDraft":
		draft, ok := findDraftRow(decodeDraftRows(m.Panel.FreshDraftRows), variant)
		if !ok {
			draft, ok = findDraftRow(decodeDraftRows(m.Panel.SpentDraftRows), variant)
		}
		if !ok || draft.path == "" {
			return "", false
		}
		return draft.path, true
	case "openWalkthrough":
		return m.walkthroughPath()
	case "openGuide":
		if !m.Panel.HasGuideRows {
			return "", false
		}
		switch variant {
		case "team":
			if m.Panel.TeamGuideState != domain.GuideAbsent && m.Panel.TeamGuideRow != "" {
				return m.Panel.TeamGuideRow, true
			}
		case "own":
			if m.Panel.OwnGuideState != domain.GuideAbsent && m.Panel.OwnGuideRow != "" {
				return m.Panel.OwnGuideRow, true
			}
		}
	}
	return "", false
}

func (m Model) beginOpenReportedPath(id domain.ControlID, variant string) (Model, tea.Cmd) {
	display, ok := m.reportedEditorPath(id, variant)
	if !ok {
		return m, nil
	}
	dir, _ := os.Getwd()
	cmd, reason, ok := host.OpenInEditorCmd(display, dir)
	if !ok {
		m.statusLine = reason
		return m, nil
	}
	return m, execCmd(cmd)
}

// --- copyCliInstall / copyDraftPrompt / copyWalkthroughPrompt: OSC 52 -----
//
// Huecos §5's own note: the design resolves OSC 52 for the CLI install
// command and the two agent pointers (draft and walkthrough). Neither
// control's acknowledgement ever claims to have copied (FR-068) — the status
// line names what IS true (the line is drawn, selectable) instead.

const copiedNothingToConfirm = "The command is on the line above — select it, or press m to select with the mouse."

func (m Model) beginCopyCliInstall() (Model, tea.Cmd) {
	kind := domain.CliInstall
	if domain.LayoutSituationFor(m.Panel) == domain.LayoutCliOutdated {
		kind = domain.CliUpdate
	}
	host.CopyOSC52(domain.NpmCommandFor(kind))
	m.statusLine = copiedNothingToConfirm
	return m, nil
}

func (m Model) beginCopyDraftPrompt(src string) (Model, tea.Cmd) {
	d, ok := findDraftRow(decodeDraftRows(m.Panel.FreshDraftRows), src)
	if !ok {
		d, ok = findDraftRow(decodeDraftRows(m.Panel.SpentDraftRows), src)
	}
	if !ok {
		return m, nil
	}
	host.CopyOSC52(domain.DraftAgentPromptBefore + d.path + domain.DraftAgentPromptAfter)
	m.statusLine = copiedNothingToConfirm
	return m, nil
}

func (m Model) beginCopyWalkthroughPrompt() (Model, tea.Cmd) {
	path, ok := m.walkthroughPath()
	if !ok {
		return m, nil
	}
	host.CopyOSC52(domain.WalkthroughAgentPromptBefore + path + domain.WalkthroughAgentPromptAfter)
	m.statusLine = copiedNothingToConfirm
	return m, nil
}

// --- showCliLog / previewEditsStat: a read-only text overlay (T087/T088) ---

// textActionDoneMsg carries a read-only `git review` invocation's result
// back to be shown in a TextOverlay — never captured into m.statusLine,
// which is one line: a diffstat needs more than that.
type textActionDoneMsg struct {
	title  string
	result host.Result
}

func textActionCmd(title string, argv domain.Argv) tea.Cmd {
	return func() tea.Msg {
		result := host.InvokeReview(context.Background(), argv.Verb, argv.Args)
		return textActionDoneMsg{title: title, result: result}
	}
}

// textOverlayBody formats a read-only invocation's result: stdout on
// success, the same failure vocabulary the mutation cycle uses otherwise
// (FR-024's "qué no pasó, no qué comando falló" applies here just as much).
func textOverlayBody(action string, r host.Result) string {
	if mutationFailed(r) {
		return failureMessage(action, r)
	}
	return strings.TrimRight(r.Stdout, "\n")
}

// beginPreviewEditsStat: `preview --stat` is TEXT, so it is native
// (contracts/tui-surface.md: "previewEditsStat es --stat, o sea texto:
// nativa" — unlike previewEdits itself, a full diff, where the difftool
// wins).
func (m Model) beginPreviewEditsStat() (Model, tea.Cmd) {
	argv, _ := domain.BuildArgv("previewEditsStat", domain.ActionParams{})
	return m, textActionCmd("Preview edits (summary)", argv)
}

func (m Model) beginShowWhy(rawPath string) (Model, tea.Cmd) {
	if rawPath == "" {
		return m, nil
	}
	argv, _ := domain.BuildArgv("showWhy", domain.ActionParams{Source: rawPath})
	return m, textActionCmd("Why this entry", argv)
}

const outOfRangeHelpFallback = "Run 'git review status' in a terminal for the diagnosis and recovery command."

func (m Model) beginOutOfRangeHelp() (Model, tea.Cmd) {
	body := strings.TrimSpace(m.Panel.Stderr)
	if body == "" {
		body = outOfRangeHelpFallback
	}
	m.textOverlay = &TextOverlay{Title: domain.HowToFixItLabel, Body: body}
	return m, nil
}

// formatLogEntry is one showCliLog row: the exact argv (this overlay is
// the ONLY place one is ever drawn, contracts/tui-surface.md's own rule on
// tooltips not being the place for one), the directory, the duration and
// how it ended.
func formatLogEntry(e host.LogEntry) string {
	line := strings.Join(e.Argv, " ") + "  (" + e.Cwd + ", " + e.Duration.Round(time.Millisecond).String() + ")"
	switch {
	case e.TimedOut:
		line += " -- timed out"
	case e.SpawnFailed:
		line += " -- could not start"
	case e.ExitCode != 0:
		line += fmt.Sprintf(" -- exit %d", e.ExitCode)
	}
	if text := flattenStderr(e.Stderr); text != "" {
		line += "\n  " + text
	}
	return line
}

func (m Model) beginShowCliLog() (Model, tea.Cmd) {
	entries := host.InvocationLog()
	var lines []string
	for _, e := range entries {
		lines = append(lines, formatLogEntry(e))
	}
	m.textOverlay = &TextOverlay{Title: "CLI log", Body: strings.Join(lines, "\n")}
	return m, nil
}

// --- the action palette's own dispatch (T084/T085) --------------------------
//
// activatePaletteAction is the ONE place a picked palette entry resolves —
// reusing activateControl/activateBoundAction WHEREVER one already exists,
// which is what T085's own gate rests on: a destructive id picked from
// here reaches the exact same ConfirmMutation call site pressing its body
// control (or bound key) would, because it IS that same call site, not a
// second one this function introduces.
func (m Model) activatePaletteAction(action string) (Model, tea.Cmd) {
	switch action {
	case "refresh":
		return m.scheduleRead()
	case "finishReview", "saveReview", "abortReview":
		return m.activateBoundAction(action)
	case "next", "prev":
		return m.beginCursor(action)
	case "goToEntry":
		return m.openEntryPicker(), nil
	case "showCliLog":
		return m.beginShowCliLog()
	case "previewEditsStat":
		return m.beginPreviewEditsStat()
	case "showWhy":
		return m.beginShowWhy(m.Panel.CurrentPath.Raw)
	case "openEntry":
		return m.beginOpenEntry()
	case "openChange":
		return m.beginOpenChange()
	case "previewEdits":
		return m.beginPreviewEdits()
	}
	// Everything else that already has a body control (setBase, cleanReview,
	// walkthroughInit, discardInventory's own row form is picker-only and
	// stays out of this list, …) shares activateControl's own switch: no
	// second ConfirmMutation call site is introduced for any of them.
	return m.activateControl(domain.ControlID(action), "")
}

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
