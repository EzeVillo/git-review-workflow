package ui

import (
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
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

func TestFinishPendingBannerNamesNoOtherCommand(t *testing.T) {
	// The old banner named `finish --abort` and `clean --keep-fixes` in
	// prose, duplicating what its own two controls already say (CLAUDE.md
	// § "El próximo paso se dice sólo si está FUERA del panel"). Its
	// replacement copy must not repeat either.
	for _, forbidden := range []string{"finish --abort", "clean --keep-fixes", "--keep-fixes"} {
		if strings.Contains(domain.FinishPendingLine1, forbidden) || strings.Contains(domain.FinishPendingLine2, forbidden) {
			t.Errorf("finish-pending banner copy mentions %q, which its own controls already say", forbidden)
		}
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
