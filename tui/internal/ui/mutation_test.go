package ui

import (
	"errors"
	"os/exec"
	"reflect"
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	tea "github.com/charmbracelet/bubbletea"
)

func reviewPanel() domain.PanelModel {
	return domain.PanelModel{
		Situation: domain.SituationReview,
		Mode:      domain.ModeWalk,
		Branch:    "review/feat-x",
		Source:    "feat-x",
		Tip:       "abc1234",
		Position:  2,
		Total:     5,
	}
}

// --- T071: abortReview/saveReview go through the ONE gate, and nothing
// else does; continueReview/resumeFinish do not (they are not confirms:
// true, and resumeFinish is the reverse of undo — nothing to confirm).

func TestBeginSaveOpensConfirmWithTheRightPendingRequest(t *testing.T) {
	m := Model{Panel: reviewPanel()}
	m2, cmd := m.beginSave()
	m = m2
	if cmd != nil {
		t.Fatal("opening a confirmation must not itself return a Cmd")
	}
	if m.confirm == nil {
		t.Fatal("beginSave must open the confirm overlay")
	}
	if m.confirm.ID != "saveReview" {
		t.Fatalf("confirm.ID = %q, want saveReview", m.confirm.ID)
	}
	if m.confirm.Pending.action != "saveReview" {
		t.Fatalf("pending action = %q, want saveReview", m.confirm.Pending.action)
	}
	if !strings.Contains(m.confirm.Title, "feat-x") {
		t.Errorf("confirm title %q should name the source branch", m.confirm.Title)
	}
}

func TestBeginAbortOpensConfirmInReviewAndFinishConflict(t *testing.T) {
	for _, sit := range []domain.Situation{domain.SituationReview, domain.SituationFinishConflict} {
		m := Model{Panel: domain.PanelModel{Situation: sit, Branch: "review/feat-x", Source: "feat-x"}}
		m2, _ := m.beginAbort()
		m = m2
		if m.confirm == nil {
			t.Fatalf("beginAbort must open the confirm overlay in situation %q", sit)
		}
		if m.confirm.ID != "abortReview" {
			t.Fatalf("confirm.ID = %q, want abortReview", m.confirm.ID)
		}
	}
}

func TestBeginAbortAndSaveAreNoOpsOutsideTheirSituations(t *testing.T) {
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationNoReview}}
	if m2, _ := m.beginSave(); m2.confirm != nil {
		t.Fatal("beginSave must not open outside situation review")
	}
	if m2, _ := m.beginAbort(); m2.confirm != nil {
		t.Fatal("beginAbort must not open outside review/finish-conflict")
	}
}

func TestBeginUndoFinishPicksTheRightDetailPerSituation(t *testing.T) {
	pending := Model{Panel: domain.PanelModel{Situation: domain.SituationFinishPending}}
	m2, _ := pending.beginUndoFinish()
	if got := m2.confirm.Detail; got != domain.UndoFinishConfirmDetailFinishPending {
		t.Errorf("finish-pending detail = %q, want the finish-pending copy", got)
	}
	conflict := Model{Panel: domain.PanelModel{Situation: domain.SituationFinishConflict}}
	m3, _ := conflict.beginUndoFinish()
	if got := m3.confirm.Detail; got != domain.UndoFinishConfirmDetailConflict {
		t.Errorf("finish-conflict detail = %q, want the conflict copy", got)
	}
}

// --- resumeFinish: never confirms, and --onto-source comes from the
// porcelain's own finish record, never a remembered value.

func TestResumeOntoComesFromThePorcelainFinishRecord(t *testing.T) {
	if resumeOnto(host.ReadResult{}) {
		t.Error("no status at all must not report onto")
	}
	noOnto := host.ReadResult{HasStatus: true, Status: domain.PorcelainResult{Finish: &domain.StatusFinishRecord{State: "conflict", Onto: false}}}
	if resumeOnto(noOnto) {
		t.Error("Onto: false in the porcelain must report false")
	}
	withOnto := host.ReadResult{HasStatus: true, Status: domain.PorcelainResult{Finish: &domain.StatusFinishRecord{State: "conflict", Onto: true}}}
	if !resumeOnto(withOnto) {
		t.Error("Onto: true in the porcelain must report true")
	}
}

func TestBeginResumeFinishOnlyRunsInFinishConflict(t *testing.T) {
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationReview, Branch: "review/x", Source: "x"}}
	if _, cmd := m.beginResumeFinish(); cmd != nil {
		t.Fatal("resumeFinish must be inert outside finish-conflict")
	}
	m2 := Model{Panel: domain.PanelModel{Situation: domain.SituationFinishConflict, Branch: "review/x", Source: "x", Tip: "t"}}
	after, cmd := m2.beginResumeFinish()
	if cmd == nil {
		t.Fatal("resumeFinish must run in finish-conflict")
	}
	if after.confirm != nil {
		t.Fatal("resumeFinish must never open a confirmation")
	}
}

// --- T073: next/prev disabled at the extremes, only inside a review.

func TestBeginCursorRespectsAtFirstAtLast(t *testing.T) {
	mid := Model{Panel: domain.PanelModel{Situation: domain.SituationReview, Branch: "review/x", Source: "x", Tip: "t", AtFirst: false, AtLast: false}}
	if _, cmd := mid.beginCursor("next"); cmd == nil {
		t.Error("next must run when not at last")
	}
	if _, cmd := mid.beginCursor("prev"); cmd == nil {
		t.Error("prev must run when not at first")
	}

	atLast := Model{Panel: domain.PanelModel{Situation: domain.SituationReview, AtLast: true}}
	if _, cmd := atLast.beginCursor("next"); cmd != nil {
		t.Error("next must be a no-op at the last entry")
	}
	atFirst := Model{Panel: domain.PanelModel{Situation: domain.SituationReview, AtFirst: true}}
	if _, cmd := atFirst.beginCursor("prev"); cmd != nil {
		t.Error("prev must be a no-op at the first entry")
	}
}

func TestBeginCursorOnlyRunsInsideAReview(t *testing.T) {
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationFinishConflict}}
	if _, cmd := m.beginCursor("next"); cmd != nil {
		t.Error("the cursor must not move outside situation review, finish-conflict included (User Story 3, escenario 4)")
	}
}

// --- T072: setBase degrades to no_base_candidates; setRemote is inert with
// nothing to offer.

func TestBeginSetBaseDegradesWithNoCandidates(t *testing.T) {
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationNoReview}}
	m2, cmd := m.beginSetBase()
	if cmd != nil {
		t.Fatal("no candidates must not return a Cmd")
	}
	got := m2
	if got.selectOverlay != nil {
		t.Fatal("no candidates must not open a picker")
	}
	if got.statusLine != domain.NoBaseCandidates {
		t.Errorf("statusLine = %q, want NoBaseCandidates", got.statusLine)
	}
}

func TestBeginSetBaseOffersEveryCandidateAndPicksName(t *testing.T) {
	m := Model{lastRead: host.ReadResult{
		HasConfig: true,
		Config: domain.ConfigPorcelainResult{
			Candidates: []domain.CandidateBranch{{Name: "develop", Origin: "local"}, {Name: "main", Origin: "remote"}},
		},
	}}
	m2, _ := m.beginSetBase()
	got := m2
	if got.selectOverlay == nil {
		t.Fatal("setBase must open a picker when candidates exist")
	}
	if len(got.selectOverlay.Items) != 2 {
		t.Fatalf("got %d items, want 2", len(got.selectOverlay.Items))
	}
	result := got.selectOverlay.OnPick("develop")
	if result.done == nil {
		t.Fatal("picking a branch must finish the flow")
	}
	if result.done.action != "setBase" || result.done.params.Name != "develop" {
		t.Fatalf("done request = %+v, want setBase with Name=develop", result.done)
	}
}

func TestBeginSetRemoteIsInertWithNoRemotes(t *testing.T) {
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationNoReview}}
	m2, cmd := m.beginSetRemote()
	if cmd != nil || m2.selectOverlay != nil {
		t.Fatal("setRemote with no remotes must be a no-op, not an empty picker")
	}
}

// --- T070: finishReview's destination picker, and the finish-pending
// banner not repeating what its own controls already say.

func TestBeginFinishOffersTheTwoDestinationsAndPicksOntoSource(t *testing.T) {
	m := Model{Panel: reviewPanel()}
	m2, _ := m.beginFinish()
	got := m2
	if got.selectOverlay == nil {
		t.Fatal("beginFinish must open the destination picker")
	}
	if len(got.selectOverlay.Items) != 2 {
		t.Fatalf("got %d destination options, want 2", len(got.selectOverlay.Items))
	}
	fixes := got.selectOverlay.OnPick("fixes")
	if fixes.done == nil || fixes.done.action != "finishReview" || fixes.done.params.OntoSource {
		t.Fatalf("fixes pick = %+v, want finishReview with OntoSource=false", fixes.done)
	}
	if fixes.done.params.Source != "feat-x" {
		t.Errorf("fixes pick Source = %q, want feat-x", fixes.done.params.Source)
	}
	onto := got.selectOverlay.OnPick("onto")
	if onto.done == nil || !onto.done.params.OntoSource {
		t.Fatalf("onto pick = %+v, want OntoSource=true", onto.done)
	}
}

func TestBeginFinishRefusesReadonlyOrOutsideReview(t *testing.T) {
	readonly := Model{Panel: domain.PanelModel{Situation: domain.SituationReview, Readonly: true}}
	if m2, _ := readonly.beginFinish(); m2.selectOverlay != nil {
		t.Error("finish must refuse a read-only compare review")
	}
	notReview := Model{Panel: domain.PanelModel{Situation: domain.SituationNoReview}}
	if m2, _ := notReview.beginFinish(); m2.selectOverlay != nil {
		t.Error("finish must refuse outside situation review")
	}
}

// --- T070: undoFinish's --force retry, offered ONLY after the CLI's own
// stderr from a plain attempt names it, and never as the first choice.

func TestUndoFinishForceRetryOnlyAfterStderrNamesForce(t *testing.T) {
	panel := domain.PanelModel{Situation: domain.SituationFinishPending}
	plainFail := mutationDoneMsg{
		action: "undoFinish",
		params: domain.ActionParams{},
		result: host.Result{ExitCode: 1, Stderr: "error: review-fixes/x has changes since the finish; rerun with --force to discard them."},
	}
	overlay, ok := undoFinishForceRetry(plainFail, panel)
	if !ok {
		t.Fatal("a plain --abort failure naming --force must offer the retry")
	}
	if overlay.ID != "undoFinish" {
		t.Errorf("retry overlay ID = %q, want undoFinish", overlay.ID)
	}
	if !overlay.Pending.params.Force {
		t.Fatal("the retry's own pending request must carry Force: true")
	}
	if overlay.Pending.action != "undoFinish" {
		t.Fatalf("retry pending action = %q, want undoFinish", overlay.Pending.action)
	}

	// A failure that does NOT mention --force must not offer it.
	otherFail := mutationDoneMsg{action: "undoFinish", result: host.Result{ExitCode: 1, Stderr: "error: no finish to abort"}}
	if _, ok := undoFinishForceRetry(otherFail, panel); ok {
		t.Fatal("a failure that never names --force must not offer the retry")
	}

	// The retry's OWN failure (Force already true) must not offer itself again.
	alreadyForced := mutationDoneMsg{action: "undoFinish", params: domain.ActionParams{Force: true}, result: host.Result{ExitCode: 1, Stderr: "error: still could not undo, try --force"}}
	if _, ok := undoFinishForceRetry(alreadyForced, panel); ok {
		t.Fatal("--force must never be offered a second time as its own retry")
	}

	// A SUCCESSFUL attempt must never offer the retry.
	success := mutationDoneMsg{action: "undoFinish", result: host.Result{ExitCode: 0}}
	if _, ok := undoFinishForceRetry(success, panel); ok {
		t.Fatal("a successful attempt must never offer --force")
	}
}

// --- T074: the status line is decided by what was ASKED, comes from
// stdout on success (never forwarded verbatim) and from stderr on failure
// (never from stdout).

func TestStatusLineOnFailureComesFromStderrNeverStdout(t *testing.T) {
	msg := mutationDoneMsg{
		action: "saveReview",
		result: host.Result{ExitCode: 1, Stdout: "should never be shown", Stderr: "error: working tree has uncommitted changes"},
	}
	got := failureMessage(msg.action, msg.result)
	if got != "error: working tree has uncommitted changes" {
		t.Errorf("failureMessage = %q, want the stderr text", got)
	}
	if strings.Contains(got, "should never be shown") {
		t.Fatal("failureMessage must never read stdout")
	}
}

func TestFinishReadyStatusLineIsNotTheVerbsRawStdout(t *testing.T) {
	// finishReview's own success message never even inspects stdout — it is
	// derived from the FRESH read's situation (never the mutation's own
	// human stdout, FR-013) and phrased in the TUI's own words, not
	// forwarded verbatim (contracts/cli-invocation.md prohibition 5).
	outcome := pendingFinishOutcome{source: "feat-x", onto: false}
	got := outcome.destination() + domain.FinishReadySuffix
	rawCLIStdout := "review-fixes/feat-x ready with your edits staged — review and commit"
	if got == rawCLIStdout {
		t.Fatal("the status line must not equal the CLI's raw stdout verbatim")
	}
	if got != "review-fixes/feat-x is ready." {
		t.Errorf("got %q", got)
	}
}

// --- T081/T082: the footer's mutations. Every handler below is reached in
// the real program only through activateControl, dispatched from a control
// noReviewControls (controls.go) built from the SAME footer rows these
// tests hand-build with domain.FooterField — TestEveryDeclaredControl...
// (reachability_keyboard_test.go) already proves the control ids/variants
// are reachable and resolve to the right (id, variant) pair; these tests
// prove what happens once activated: the right row gets found, the right
// HousekeepingKind/argv gets built, and the confirmation copy names the
// right thing.

func TestBeginCleanReviewOpensConfirmWithKeepFixes(t *testing.T) {
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationFinishPending, Source: "feat-x", FinishDestination: "review-fixes/feat-x"}}
	m2, cmd := m.beginCleanReview()
	if cmd != nil {
		t.Fatal("opening a confirmation must not itself return a Cmd")
	}
	if m2.confirm == nil {
		t.Fatal("beginCleanReview must open the confirm overlay")
	}
	if m2.confirm.ID != "cleanReview" {
		t.Fatalf("confirm.ID = %q, want cleanReview", m2.confirm.ID)
	}
	hk := m2.confirm.Pending.params.Housekeeping
	if hk.Kind != domain.CleanKeepFixes || hk.Source != "feat-x" {
		t.Fatalf("Housekeeping = %+v, want {CleanKeepFixes feat-x}", hk)
	}
	if !strings.Contains(m2.confirm.Detail, "review-fixes/feat-x") {
		t.Errorf("detail %q should name the finish destination", m2.confirm.Detail)
	}
	rendered := m2.View()
	for _, want := range []string{
		"Keep your edits & remove Undo?",
		"Your edits stay on review-fixes/feat-x — commit and push them from Source Control. What goes away is the option to undo this finish.",
		"[ Keep edits & remove Undo ]  (y / enter)",
	} {
		if !strings.Contains(rendered, want) {
			t.Fatalf("clean-review confirmation did not render %q:\n%s", want, rendered)
		}
	}
}

func TestBeginCleanReviewNoOpOutsideFinishPending(t *testing.T) {
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationNoReview, Source: "feat-x"}}
	if m2, _ := m.beginCleanReview(); m2.confirm != nil {
		t.Fatal("beginCleanReview must not open outside finish-pending")
	}
}

func TestBeginContinueReviewResolvesTheNamedRowAndOpensConfirm(t *testing.T) {
	m := Model{Panel: domain.PanelModel{
		InventoryRows:  domain.FooterField("review-saved/feature", "1", "0", "0", "1", "walk"),
		InventoryCount: 1,
	}}
	m2, cmd := m.beginContinueReview("review-saved/feature")
	if cmd != nil {
		t.Fatal("opening a confirmation must not itself return a Cmd")
	}
	if m2.confirm == nil {
		t.Fatal("beginContinueReview must open the confirm overlay for a resumable row")
	}
	if m2.confirm.Pending.action != "continueReview" || m2.confirm.Pending.params.Source != "feature" {
		t.Fatalf("pending = %+v, want continueReview with Source=feature", m2.confirm.Pending)
	}
}

func TestContinueDetailInterpolatesTheSavedSource(t *testing.T) {
	m := Model{Panel: domain.PanelModel{
		Situation:     domain.SituationNoReview,
		InventoryRows: domain.FooterField("review-saved/feature/search", "1", "0", "0", "1", "walk"),
	}}
	after, _ := m.beginContinueReview("review-saved/feature/search")
	if after.confirm == nil {
		t.Fatal("continue did not open its confirmation")
	}
	if strings.Contains(after.confirm.Detail, "{source}") || !strings.Contains(after.confirm.Detail, "review/feature/search") {
		t.Fatalf("continue detail was not interpolated: %q", after.confirm.Detail)
	}
}

func TestMutationActivityShowsProgressThenVisibleDirtyTreeFailure(t *testing.T) {
	m := Model{
		Viewport: Viewport{Cols: 80, Rows: 24},
		Panel: domain.PanelModel{
			Situation:     domain.SituationNoReview,
			HasReviews:    true,
			InventoryRows: domain.FooterField("review-saved/feature/search", "1", "0", "0", "1", "walk"),
		},
	}
	confirming, _ := m.beginContinueReview("review-saved/feature/search")
	startedModel, cmd := confirming.handleConfirmKey(tea.KeyMsg{Type: tea.KeyEnter})
	started := startedModel.(Model)
	if cmd == nil || !started.presentationPanel().Busy {
		t.Fatalf("accepted continue did not start visible activity: cmd=%v busy=%v", cmd != nil, started.presentationPanel().Busy)
	}
	shownModel, _ := started.Update(activityVisibleMsg{generation: started.activity.generation})
	shown := shownModel.(Model)
	if !strings.Contains(shown.View(), "Continuing the review of feature/search…") {
		t.Fatalf("progress is not visible:\n%s", shown.View())
	}

	failedModel, _ := shown.Update(mutationDoneMsg{
		action:             "continueReview",
		activityGeneration: shown.activity.generation,
		result:             host.Result{ExitCode: 1, Stderr: "error: you have local changes; commit or stash them first\n"},
	})
	failed := failedModel.(Model)
	if !strings.Contains(failed.View(), "error: you have local changes; commit or stash them first") {
		t.Fatalf("dirty-tree failure is not visible:\n%s", failed.View())
	}
	readingModel, _ := failed.Update(activityVisibleMsg{generation: failed.activity.generation})
	reading := readingModel.(Model)
	presented := reading.presentationPanel().StatusLine
	if !strings.Contains(presented, "error: you have local changes; commit or stash them first") || !strings.Contains(presented, domain.WaitingText) {
		t.Fatalf("refresh hid the mutation failure instead of showing both states:\n%s", reading.View())
	}
}

func TestDelegatedLaunchFailureIsVisibleButExitStatusIsNonFatal(t *testing.T) {
	failedModel, _ := (Model{}).Update(execDoneMsg{err: errors.New("executable disappeared"), completion: "Created .review/guide.md."})
	failed := failedModel.(Model)
	if !strings.Contains(failed.statusLine, "Created .review/guide.md.") || !strings.Contains(failed.statusLine, "Could not launch") {
		t.Fatalf("delegated launch failure was not acknowledged: %q", failed.statusLine)
	}

	exitedModel, _ := (Model{}).Update(execDoneMsg{err: &exec.ExitError{}, completion: "Created .review/guide.md."})
	exited := exitedModel.(Model)
	if exited.statusLine != "Created .review/guide.md." {
		t.Fatalf("ordinary editor exit became a failure: %q", exited.statusLine)
	}
}

func TestBeginContinueReviewNoOpWhenNotResumableOrUnknown(t *testing.T) {
	notResumable := Model{Panel: domain.PanelModel{
		InventoryRows: domain.FooterField("review-saved/feature", "1", "0", "0", "0", "walk"),
	}}
	if m2, _ := notResumable.beginContinueReview("review-saved/feature"); m2.confirm != nil {
		t.Fatal("a non-resumable saved row must not open a confirmation")
	}
	if m2, _ := notResumable.beginContinueReview("does-not-exist"); m2.confirm != nil {
		t.Fatal("an unknown row name must not open a confirmation")
	}
}

func TestBeginDiscardInventoryPicksForgetVsCleanBySavedBit(t *testing.T) {
	saved := Model{Panel: domain.PanelModel{
		InventoryRows: domain.FooterField("review-saved/feature", "1", "0", "0", "1", "walk"),
	}}
	m2, _ := saved.beginDiscardInventory("review-saved/feature")
	if m2.confirm == nil {
		t.Fatal("a saved row must open the confirm overlay")
	}
	hk := m2.confirm.Pending.params.Housekeeping
	if hk.Kind != domain.ForgetSavedOne || hk.Source != "feature" {
		t.Fatalf("saved row Housekeeping = %+v, want {ForgetSavedOne feature}", hk)
	}

	orphan := Model{Panel: domain.PanelModel{
		InventoryRows: domain.FooterField("review/broken", "0", "1", "0", "0", "broken"),
	}}
	m3, _ := orphan.beginDiscardInventory("review/broken")
	if m3.confirm == nil {
		t.Fatal("an orphan (unsaved, broken) row must also open the confirm overlay")
	}
	hk2 := m3.confirm.Pending.params.Housekeeping
	if hk2.Kind != domain.CleanOne || hk2.Source != "broken" {
		t.Fatalf("orphan row Housekeeping = %+v, want {CleanOne broken}", hk2)
	}
}

func TestBeginDiscardInventoryNoOpWhenNeitherSavedNorOrphan(t *testing.T) {
	m := Model{Panel: domain.PanelModel{
		InventoryRows: domain.FooterField("review/active", "0", "0", "1", "0", "walk . 1/3"),
	}}
	if m2, _ := m.beginDiscardInventory("review/active"); m2.confirm != nil {
		t.Fatal("a plain active review row (not saved, not orphan) must not offer a discard")
	}
}

func TestBeginDiscardDraftFindsRowInFreshOrSpentAndBuildsForgetArgv(t *testing.T) {
	m := Model{Panel: domain.PanelModel{
		FreshDraftRows: domain.FooterField("feat-y", "/gitdir/review-walkthrough/feat-y.md", "remote", "full", "1", "3"),
		SpentDraftRows: domain.FooterField("feat-z", "/gitdir/review-walkthrough/feat-z.md", "local", "delta", "4", "4"),
	}}
	fresh, _ := m.beginDiscardDraft("feat-y")
	if fresh.confirm == nil {
		t.Fatal("a fresh draft row must open the confirm overlay")
	}
	if fresh.confirm.Pending.argv == nil || fresh.confirm.Pending.argv.Verb != "forget" {
		t.Fatalf("fresh draft argv = %+v, want verb forget", fresh.confirm.Pending.argv)
	}
	if got := fresh.confirm.Pending.argv.Args; len(got) != 2 || got[0] != "--draft" || got[1] != "feat-y" {
		t.Errorf("fresh draft args = %v, want [--draft feat-y]", got)
	}
	if !strings.Contains(fresh.confirm.Title, "feat-y") {
		t.Errorf("title %q should name the source", fresh.confirm.Title)
	}
	if !strings.Contains(fresh.confirm.Detail, "/gitdir/review-walkthrough/feat-y.md") {
		t.Errorf("detail %q should name the draft's own path", fresh.confirm.Detail)
	}

	// A spent draft keeps discardDraft (draft_controls' own comment: it only
	// loses the two LABELLED controls, not the icons).
	spent, _ := m.beginDiscardDraft("feat-z")
	if spent.confirm == nil {
		t.Fatal("a spent draft row must also open the confirm overlay")
	}
}

func TestBeginDiscardDraftNoOpWhenRowNotFound(t *testing.T) {
	m := Model{Panel: domain.PanelModel{}}
	if m2, _ := m.beginDiscardDraft("nope"); m2.confirm != nil {
		t.Fatal("an unknown draft src must not open a confirmation")
	}
}

func TestBeginDiscardGuideOnlyEverActsOnOwn(t *testing.T) {
	m := Model{Panel: domain.PanelModel{
		HasGuideRows:   true,
		TeamGuideState: domain.GuideInForce,
		OwnGuideState:  domain.GuideInForce,
		OwnGuideRow:    "/gitdir/review-walkthrough-guide.md",
	}}
	if m2, _ := m.beginDiscardGuide("team"); m2.confirm != nil {
		t.Fatal("discardGuide must never act on the team row: the CLI itself refuses --delete --team")
	}
	own, _ := m.beginDiscardGuide("own")
	if own.confirm == nil {
		t.Fatal("discardGuide must open the confirm overlay for the own row when it exists")
	}
	if own.confirm.Pending.argv == nil || own.confirm.Pending.argv.Verb != "walkthrough" {
		t.Fatalf("argv = %+v, want verb walkthrough", own.confirm.Pending.argv)
	}
	if got := own.confirm.Pending.argv.Args; len(got) != 2 || got[0] != "guide" || got[1] != "--delete" {
		t.Errorf("args = %v, want [guide --delete]", got)
	}
	if !strings.Contains(own.confirm.Detail, "/gitdir/review-walkthrough-guide.md") {
		t.Errorf("detail %q should name the guide's own path", own.confirm.Detail)
	}
}

func TestBeginDiscardGuideNoOpWhenAbsent(t *testing.T) {
	m := Model{Panel: domain.PanelModel{HasGuideRows: true, OwnGuideState: domain.GuideAbsent}}
	if m2, _ := m.beginDiscardGuide("own"); m2.confirm != nil {
		t.Fatal("an absent own guide has nothing to discard")
	}
}

func TestBeginCreateGuideRunsOnlyWhenAbsentAndNeverConfirms(t *testing.T) {
	m := Model{Panel: domain.PanelModel{TeamGuideState: domain.GuideAbsent, OwnGuideState: domain.GuideInForce}}
	team, cmd := m.beginCreateGuide("team")
	if cmd == nil {
		t.Fatal("creating an absent team guide must run")
	}
	if team.confirm != nil {
		t.Fatal("createGuide must never confirm: it is not confirms: true in the canonical")
	}
	if _, cmd2 := m.beginCreateGuide("own"); cmd2 != nil {
		t.Fatal("createGuide on an already-existing own guide must be a no-op")
	}
	if _, cmd3 := m.beginCreateGuide("bogus"); cmd3 != nil {
		t.Fatal("an unrecognized variant must be a no-op")
	}
}

func TestCreateGuideRequestCarriesTheReportedPathToOpenAfterRefresh(t *testing.T) {
	panel := domain.PanelModel{
		HasGuideRows:   true,
		TeamGuideState: domain.GuideAbsent,
		TeamGuideRow:   "C:/repo/.review/walkthrough-guide.md",
		OwnGuideState:  domain.GuideAbsent,
		OwnGuideRow:    "C:/gitdir/review-walkthrough-guide.md",
	}
	for _, tc := range []struct{ variant, want string }{
		{"team", panel.TeamGuideRow},
		{"own", panel.OwnGuideRow},
	} {
		req, ok := createGuideRequest(panel, tc.variant)
		if !ok || req.successOpenPath != tc.want {
			t.Fatalf("createGuideRequest(%q) path = %q, %v; want %q", tc.variant, req.successOpenPath, ok, tc.want)
		}
	}
}

func TestCreatedGuideWithoutEditorIsAcknowledgedAfterAcceptedRead(t *testing.T) {
	t.Setenv("EDITOR", "")
	path := "C:/repo/.review/walkthrough-guide.md"
	m := Model{
		Viewport:        Viewport{Cols: 80, Rows: 24},
		Panel:           domain.PanelModel{Situation: domain.SituationNoReview},
		readGeneration:  1,
		pendingOpenPath: path,
	}
	updated, cmd := m.Update(readDoneMsg{generation: 1, result: host.ReadResult{Situation: domain.SituationNoReview}})
	if cmd == nil {
		t.Fatal("accepted read must resolve the editor outside Update")
	}
	resolved, child := updated.(Model).Update(cmd())
	after := resolved.(Model)
	if child != nil {
		t.Fatal("missing editor must not dispatch a child after guide creation")
	}
	if after.pendingOpenPath != "" || !strings.Contains(after.View(), domain.GuideCreated(path)) {
		t.Fatalf("created-guide acknowledgement is not visible:\n%s", after.View())
	}
}

func TestBeginDiscardFixesSkipsTheCurrentBranch(t *testing.T) {
	m := Model{Panel: domain.PanelModel{
		FixesRows: domain.FooterField("review-fixes/old-one", "merged", "0", "0") + "\n" +
			domain.FooterField("review-fixes/here", "empty", "1", "1"),
	}}
	other, _ := m.beginDiscardFixes("review-fixes/old-one")
	if other.confirm == nil {
		t.Fatal("a non-current fixes branch must open the confirm overlay")
	}
	if other.confirm.Pending.argv == nil || other.confirm.Pending.argv.Verb != "clean" {
		t.Fatalf("argv = %+v, want verb clean", other.confirm.Pending.argv)
	}
	if got := other.confirm.Pending.argv.Args; len(got) != 2 || got[0] != "--fixes-only" || got[1] != "old-one" {
		t.Errorf("args = %v, want [--fixes-only old-one]", got)
	}
	if m2, _ := m.beginDiscardFixes("review-fixes/here"); m2.confirm != nil {
		t.Fatal("the branch currently checked out must never offer discardFixes (disabled_when: current)")
	}
}

func TestBeginDiscardFixesDetailNamesTheOpenSessionWhenPresent(t *testing.T) {
	withSession := Model{Panel: domain.PanelModel{
		FixesRows: domain.FooterField("review-fixes/open", "unmerged", "1", "0"),
	}}
	m2, _ := withSession.beginDiscardFixes("review-fixes/open")
	if m2.confirm == nil || !strings.Contains(m2.confirm.Detail, "undo the finish") {
		t.Fatalf("detail %q must mention the still-open finish's undo", m2.confirm.Detail)
	}

	noSession := Model{Panel: domain.PanelModel{
		FixesRows: domain.FooterField("review-fixes/closed", "unmerged", "0", "0"),
	}}
	m3, _ := noSession.beginDiscardFixes("review-fixes/closed")
	if m3.confirm == nil || strings.Contains(m3.confirm.Detail, "undo the finish") {
		t.Fatalf("detail %q must not mention undoing a finish that has no open session", m3.confirm.Detail)
	}
}

func TestBeginDiscardAllFixesArgvNeverDependsOnPanelState(t *testing.T) {
	m := Model{Panel: domain.PanelModel{FixesRows: "this-must-never-be-read"}}
	m2, _ := m.beginDiscardAllFixes()
	if m2.confirm == nil {
		t.Fatal("discardAllFixes must open the confirm overlay")
	}
	if m2.confirm.Pending.argv == nil || m2.confirm.Pending.argv.Verb != "clean" {
		t.Fatalf("argv = %+v, want verb clean", m2.confirm.Pending.argv)
	}
	if got := m2.confirm.Pending.argv.Args; len(got) != 1 || got[0] != "--fixes-only" {
		t.Errorf("args = %v, want [--fixes-only] with no branch, regardless of what FixesRows carries", got)
	}
}

func TestBeginWalkthroughBuildOpensAPlainConfirm(t *testing.T) {
	m := Model{}
	m2, cmd := m.beginWalkthroughBuild()
	if cmd != nil {
		t.Fatal("opening a confirmation must not itself return a Cmd")
	}
	if m2.confirm == nil || m2.confirm.ID != "walkthroughBuild" {
		t.Fatal("beginWalkthroughBuild must open the confirm overlay")
	}
	if m2.confirm.Pending.action != "walkthroughBuild" {
		t.Fatalf("pending action = %q, want walkthroughBuild", m2.confirm.Pending.action)
	}
}

// TestBeginWalkthroughInitRunsDirectlyWhenNothingToReconcile covers
// walkthroughInit's declared exception (confirms.go) from the OTHER side:
// with nothing worth reconciling it runs straight through beginMutation,
// opening neither the yes/no confirm NOR the picker.
func TestBeginWalkthroughInitRunsDirectlyWhenNothingToReconcile(t *testing.T) {
	for _, state := range []domain.WalkthroughState{domain.WalkthroughAbsent, domain.WalkthroughSuperseded} {
		m := Model{Panel: domain.PanelModel{HasWalkthroughRow: true, WalkthroughState: state}}
		m2, cmd := m.beginWalkthroughInit()
		if m2.confirm != nil {
			t.Fatalf("%v: walkthroughInit must never open the yes/no confirm", state)
		}
		if m2.selectOverlay != nil {
			t.Fatalf("%v: nothing to reconcile must not open the picker either", state)
		}
		if cmd == nil {
			t.Fatalf("%v: walkthroughInit must run directly when there is nothing to reconcile", state)
		}
	}
	none := Model{Panel: domain.PanelModel{HasWalkthroughRow: false}}
	if _, cmd := none.beginWalkthroughInit(); cmd == nil {
		t.Fatal("with no walkthrough record at all, init must run directly, same as absent")
	}
}

func TestBeginWalkthroughInitOpensThePickerWhenReconcilable(t *testing.T) {
	for _, state := range []domain.WalkthroughState{domain.WalkthroughInSync, domain.WalkthroughStale, domain.WalkthroughUnknownState} {
		m := Model{Panel: domain.PanelModel{HasWalkthroughRow: true, WalkthroughState: state}}
		m2, cmd := m.beginWalkthroughInit()
		if cmd != nil {
			t.Fatalf("%v: opening the picker must not itself return a Cmd", state)
		}
		if m2.confirm != nil {
			t.Fatalf("%v: this path is a choice, not a yes/no confirm", state)
		}
		if m2.selectOverlay == nil {
			t.Fatalf("%v: a reconcilable walkthrough must open the Update/Start over picker", state)
		}
		if len(m2.selectOverlay.Items) != 2 {
			t.Fatalf("%v: expected 2 items (Update/Start over), got %d", state, len(m2.selectOverlay.Items))
		}
		update := m2.selectOverlay.OnPick("update")
		if update.done == nil || update.done.params.WalkthroughForce {
			t.Fatalf("%v: Update must run with WalkthroughForce=false", state)
		}
		force := m2.selectOverlay.OnPick("force")
		if force.done == nil || !force.done.params.WalkthroughForce {
			t.Fatalf("%v: Start over must run with WalkthroughForce=true", state)
		}
	}
}

func TestHandleMutationDoneSetsPendingFinishOnlyOnSuccess(t *testing.T) {
	m := Model{}
	m.lock.Begin()
	m2, _ := m.handleMutationDone(mutationDoneMsg{
		action: "finishReview",
		params: domain.ActionParams{Source: "feat-x", OntoSource: true},
		result: host.Result{ExitCode: 0},
	})
	got := m2
	if got.pendingFinish == nil {
		t.Fatal("a successful finishReview must arm pendingFinish")
	}
	if got.pendingFinish.source != "feat-x" || !got.pendingFinish.onto {
		t.Errorf("pendingFinish = %+v, want source=feat-x onto=true", got.pendingFinish)
	}

	m3 := Model{}
	m3.lock.Begin()
	m4, _ := m3.handleMutationDone(mutationDoneMsg{
		action: "finishReview",
		result: host.Result{ExitCode: 1, Stderr: "error: could not apply review changes"},
	})
	if m4.pendingFinish != nil {
		t.Fatal("a FAILED finishReview must not arm pendingFinish")
	}
}

func TestSuccessfulDraftBuildContinuesWithAConfigProbe(t *testing.T) {
	intent := domain.ReviewIntent{Branch: "feature/x", Source: "local", Range: "delta", Layout: "walk"}
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationNoReview}}
	m.lock.Begin()
	after, cmd := m.handleMutationDone(mutationDoneMsg{
		action:     "startFromDraft",
		result:     host.Result{ExitCode: 0},
		draftStart: &intent,
	})
	if cmd == nil {
		t.Fatal("a green draft build must continue with config --porcelain")
	}
	if after.progressOverlay == nil {
		t.Fatal("the config probe must replace the panel with progress")
	}
	if after.lock.Busy() {
		t.Fatal("the build's mutation lock must be released before the read-only config probe")
	}
}

func TestFailedDraftBuildStopsBeforeConfigOrStart(t *testing.T) {
	intent := domain.ReviewIntent{Branch: "feature/x", Source: "remote", Range: "full", Layout: "walk"}
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationNoReview}}
	m.lock.Begin()
	after, _ := m.handleMutationDone(mutationDoneMsg{
		action:     "startFromDraft",
		result:     host.Result{ExitCode: 1, Stderr: "error: reading order drifted"},
		draftStart: &intent,
	})
	if after.progressOverlay != nil {
		t.Fatal("a rejected draft must not continue to config")
	}
	if after.statusLine != "error: reading order drifted" {
		t.Fatalf("status = %q, want the CLI's validation error", after.statusLine)
	}
}

func TestDraftConfigOffersKeysBeforeStarting(t *testing.T) {
	raw := `feature/\303\261o`
	intent := domain.ReviewIntent{Branch: raw, Source: "offline", Range: "delta", Layout: "walk"}
	m := Model{Panel: domain.PanelModel{
		Situation:      domain.SituationNoReview,
		FreshDraftRows: domain.FooterField(raw, "C:/draft.md", "offline", "delta", "4", "4"),
	}}
	after, cmd := m.handleDraftConfigDone(draftConfigDoneMsg{
		intent: intent,
		result: host.Result{ExitCode: 0, Stdout: "offer\twalk\trecommended\noffer\tkeys\tavailable\n"},
	})
	if cmd != nil || after.selectOverlay == nil {
		t.Fatalf("keys-capable draft must pause for the layout choice: cmd=%v overlay=%v", cmd != nil, after.selectOverlay != nil)
	}
	if len(after.selectOverlay.Items) != 2 {
		t.Fatalf("keys picker items = %+v, want full walkthrough and keys only", after.selectOverlay.Items)
	}
	picked := after.selectOverlay.OnPick("keys")
	if picked.done == nil || picked.done.argv == nil || picked.done.argv.Verb != "start" {
		t.Fatalf("keys pick = %+v, want final start request", picked.done)
	}
	if got, want := picked.done.argv.Args, []string{"--keys", "--delta", "--offline", "--", raw}; !reflect.DeepEqual(got, want) {
		t.Fatalf("keys start args = %#v, want %#v", got, want)
	}
}

func TestDraftConfigWithoutKeysStartsWalkImmediately(t *testing.T) {
	intent := domain.ReviewIntent{Branch: "feature/x", Source: "remote", Range: "full", Layout: "walk"}
	m := Model{Panel: domain.PanelModel{
		Situation:      domain.SituationNoReview,
		FreshDraftRows: domain.FooterField("feature/x", "C:/draft.md", "remote", "full", "2", "2"),
	}}
	after, cmd := m.handleDraftConfigDone(draftConfigDoneMsg{
		intent: intent,
		result: host.Result{ExitCode: 0, Stdout: "offer\twalk\trecommended\n"},
	})
	if cmd == nil || !after.lock.Busy() {
		t.Fatal("a draft without keys must proceed directly to start")
	}
	if after.selectOverlay != nil || after.confirm != nil {
		t.Fatal("a draft without keys must not add another question or confirmation")
	}
}

func TestDraftFlowFailureReturnsToTheLayoutChoice(t *testing.T) {
	intent := domain.ReviewIntent{Branch: "feature/x", Source: "remote", Range: "full"}
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationNoReview}}
	m.lock.Begin()
	after, cmd := m.handleMutationDone(mutationDoneMsg{
		action: "draftFlow",
		result: host.Result{ExitCode: 1, Stderr: "error: could not write the draft"},
		draftFlow: &draftFlowContinuation{
			intent: intent,
			offers: []domain.ReadingOffer{{ID: domain.OfferDraft, Rank: "available"}, {ID: domain.OfferWhole, Rank: "available"}},
		},
	})
	if cmd == nil {
		t.Fatal("a failed local mutation must still schedule its refresh")
	}
	if after.selectOverlay == nil || after.selectOverlay.Title != domain.StartLayoutTitle("feature/x") {
		t.Fatal("a failed draft creation must return to the same layout choice")
	}
	if after.statusLine != "error: could not write the draft" {
		t.Fatalf("failure status = %q", after.statusLine)
	}
	if !strings.Contains(after.selectOverlay.Render(Viewport{Cols: 80, Rows: 24}), "error: could not write the draft") {
		t.Fatal("returning to the layout picker hid the draft creation error")
	}
}

func TestDraftUpdateUsesMergedCountsForTheStatusLine(t *testing.T) {
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationNoReview}}
	m.lock.Begin()
	after, _ := m.handleMutationDone(mutationDoneMsg{
		action:    "draftFlow",
		result:    host.Result{ExitCode: 0, Stdout: "merged\t4\t2\t1\n"},
		draftFlow: &draftFlowContinuation{update: true},
	})
	if after.statusLine != "Reading order updated: 4 kept, 2 added, 1 no longer in the PR." {
		t.Fatalf("update status = %q", after.statusLine)
	}
}
