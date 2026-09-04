package ui

import (
	"os"
	"regexp"
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	tea "github.com/charmbracelet/bubbletea"
)

// TestStartReviewNeverPassesThroughConfirmMutation is T069's own gate,
// checked directly against the source rather than through the Node
// checker: startReview and startFromDraft are absent from
// domain.ConfirmingIDs on purpose (confirms.go's own comment — "the
// assistant already asks four questions, and start destroys nothing"), so
// neither id may ever appear as ConfirmMutation's first argument anywhere
// in this package.
func TestStartReviewNeverPassesThroughConfirmMutation(t *testing.T) {
	entries, err := os.ReadDir(".")
	if err != nil {
		t.Fatal(err)
	}
	pattern := regexp.MustCompile(`ConfirmMutation\(\s*"(startReview|startFromDraft)"`)
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".go") {
			continue
		}
		b, err := os.ReadFile(e.Name())
		if err != nil {
			t.Fatal(err)
		}
		if pattern.Match(b) {
			t.Fatalf("%s passes startReview/startFromDraft through ConfirmMutation — the assistant must never confirm (T069)", e.Name())
		}
	}
}

// TestStartAssistantFullHappyPathNeverConfirms walks the four questions by
// hand — branch, source, range, layout — feeding each step-builder a
// FABRICATED probe result (never a real CLI invocation: mutation.go's own
// mutationCmd/configProbeCmd closures are the only things allowed to spawn
// `git`, and this test never calls them) and checks that only the CLI's own
// `offer`/`candidate`/`delta` records decide what each question offers.
func TestStartAssistantFullHappyPathNeverConfirms(t *testing.T) {
	probe1Candidates := []domain.CandidateBranch{
		{Name: "feat-x", Origin: "remote"},
		{Name: "feat-x", Origin: "local", Current: true},
	}
	branchStep := buildBranchStep("local")(domain.ConfigPorcelainResult{Candidates: probe1Candidates})
	if branchStep.Title != domain.StartAssistantBranchTitle {
		t.Fatalf("branch step title = %q", branchStep.Title)
	}
	if len(branchStep.Items) != 1 || branchStep.Items[0].Value != "feat-x" {
		t.Fatalf("branch items = %+v, want one collapsed feat-x entry", branchStep.Items)
	}
	pick1 := branchStep.OnPick("feat-x")
	if pick1.next == nil || pick1.probe != nil || pick1.cmd != nil || pick1.done != nil {
		t.Fatal("picking the branch must open the source question without probing")
	}

	sourceStep := *pick1.next
	if sourceStep.Title != domain.StartAssistantSourceTitle {
		t.Fatalf("source step title = %q", sourceStep.Title)
	}
	if len(sourceStep.Items) != 3 {
		t.Fatalf("got %d source items, want 3 (remote+local+offline, both origins exist)", len(sourceStep.Items))
	}
	if sourceStep.Items[sourceStep.Cursor].Value != "local" {
		t.Errorf("reviewui.startsource=local should pre-position the cursor there, got %q", sourceStep.Items[sourceStep.Cursor].Value)
	}
	pick2 := sourceStep.OnPick("local")
	if pick2.probe == nil {
		t.Fatal("picking a source must run the source-scoped delta probe")
	}
	if pick2.next != nil || pick2.cmd != nil || pick2.done != nil {
		t.Fatal("the source step must only run its probe")
	}

	rangeStep := *buildRangeStep("feat-x", "local", []domain.DeltaRecord{{Name: "feat-x", Tip: "abc1234", Origin: "local"}})
	if rangeStep.Title != domain.StartAssistantRangeTitle {
		t.Fatalf("range step title = %q", rangeStep.Title)
	}
	if len(rangeStep.Items) != 2 {
		t.Fatalf("got %d range items, want 2 (full + delta, since a local delta marker exists)", len(rangeStep.Items))
	}
	pick3 := rangeStep.OnPick("delta")
	if pick3.probe == nil || pick3.cmd != nil {
		t.Fatal("picking a range must run the third, scoped probe")
	}

	layoutStep := buildLayoutStep("feat-x", "local", "delta")(domain.ConfigPorcelainResult{
		Offers: []domain.ReadingOffer{
			{ID: domain.OfferWalk, Rank: "recommended"},
			{ID: domain.OfferWhole, Rank: "available"},
		},
	})
	if layoutStep.Title != domain.StartLayoutTitle("feat-x") {
		t.Fatalf("layout step title = %q", layoutStep.Title)
	}
	if len(layoutStep.Items) != 2 {
		t.Fatalf("got %d layout items, want 2 (walk+whole, exactly the reported offers)", len(layoutStep.Items))
	}
	final := layoutStep.OnPick("walk")
	if final.done == nil {
		t.Fatal("the LAST question must finish the flow")
	}
	if final.done.action != "startReview" {
		t.Fatalf("final action = %q, want startReview", final.done.action)
	}
	want := domain.ReviewIntent{Branch: "feat-x", Source: "local", Range: "delta", Layout: "walk"}
	if final.done.params.Intent != want {
		t.Fatalf("final intent = %+v, want %+v", final.done.params.Intent, want)
	}
}

func TestRangeQuestionIsSkippedWhenNoDeltaExists(t *testing.T) {
	result := buildRangeResult("feat-x", "remote", nil)
	if result.next != nil {
		t.Fatal("without a delta marker, the assistant must not ask a one-option range question")
	}
	if result.probe == nil {
		t.Fatal("without delta, the assistant must continue to the full-range layout probe")
	}
}

func TestLayoutOffersHonorRankFallbackAndDraftRows(t *testing.T) {
	step := buildLayoutStep("feat-x", "remote", "full")(domain.ConfigPorcelainResult{Offers: []domain.ReadingOffer{
		{ID: domain.OfferWhole, Rank: "available"},
		{ID: domain.OfferDraft, Rank: "available"},
		{ID: domain.OfferWalk, Rank: "recommended"},
		{ID: domain.OfferKeys, Rank: "available"},
	}})
	if step.Title != domain.StartLayoutTitle("feat-x") {
		t.Fatalf("layout title = %q, want the branch named at the commit point", step.Title)
	}
	if len(step.Items) != 4 {
		t.Fatalf("layout items = %+v, want every CLI offer", step.Items)
	}
	wantValues := []string{"walk", "keys", "draft", "whole"}
	for i, want := range wantValues {
		if step.Items[i].Value != want {
			t.Fatalf("layout item %d = %+v, want value %q", i, step.Items[i], want)
		}
	}
	if !strings.Contains(step.Items[0].Label, "recommended") {
		t.Fatalf("recommended offer lost its rank in %+v", step.Items[0])
	}

	fallback := buildLayoutStep("feat-x", "remote", "full")(domain.ConfigPorcelainResult{})
	if len(fallback.Items) != 2 || fallback.Items[0].Value != "step" || fallback.Items[1].Value != "whole" {
		t.Fatalf("empty offers fallback = %+v, want step then whole", fallback.Items)
	}
}

func TestDraftLayoutOffersCreateResumeOrUpdateWithoutStartingAReview(t *testing.T) {
	for _, tc := range []struct {
		offer        domain.OfferID
		wantMutation bool
	}{
		{domain.OfferDraft, true},
		{domain.OfferDraftResume, false},
		{domain.OfferDraftUpdate, true},
	} {
		step := buildLayoutStep("feat-x", "offline", "delta")(domain.ConfigPorcelainResult{Offers: []domain.ReadingOffer{{ID: tc.offer, Rank: "available"}}})
		picked := step.OnPick(string(tc.offer))
		if tc.wantMutation {
			if picked.done == nil || picked.done.argv == nil || picked.done.argv.Verb != "walkthrough" {
				t.Fatalf("%s pick = %+v, want walkthrough draft mutation", tc.offer, picked.done)
			}
			if picked.done.action != "draftFlow" || picked.done.argv.Args[0] != "draft" || picked.done.argv.Args[1] != "--porcelain" {
				t.Fatalf("%s request = %+v", tc.offer, picked.done)
			}
			if picked.done.draftFlow == nil || picked.done.draftFlow.update != (tc.offer == domain.OfferDraftUpdate) {
				t.Fatalf("%s continuation = %+v", tc.offer, picked.done.draftFlow)
			}
		} else if picked.done != nil || picked.probe != nil || picked.next != nil || picked.cmd != nil {
			t.Fatalf("resume must close the assistant without recreating the draft: %+v", picked)
		}
	}
}

// TestSourceStepOffersOnlyWhatCandidatesReport — a branch that only exists
// locally must not offer "remote".
func TestSourceStepOffersOnlyWhatCandidatesReport(t *testing.T) {
	localOnly := []domain.CandidateBranch{{Name: "feat-x", Origin: "local"}}
	step := buildSourceStep("feat-x", "", localOnly)
	for _, it := range step.Items {
		if it.Value == "remote" {
			t.Fatal("a branch with no remote candidate row must not offer 'remote'")
		}
	}
	if len(step.Items) != 2 {
		t.Fatalf("got %d items, want 2 (local + offline)", len(step.Items))
	}
}

// TestLocalOnlyBranchAsksForSourceBeforeProbingBranch protects the ordering
// shared by the editor clients: choosing a branch is not enough context to
// validate a remote tip. A local-only branch must reach the source question
// before any branch-scoped config probe can fail against origin.
func TestLocalOnlyBranchAsksForSourceBeforeProbingBranch(t *testing.T) {
	localOnly := []domain.CandidateBranch{{Name: "feat/local-only", Origin: "local"}}
	branchStep := buildBranchStep("")(domain.ConfigPorcelainResult{Candidates: localOnly})

	afterBranch := branchStep.OnPick("feat/local-only")
	if afterBranch.next == nil {
		t.Fatal("choosing a branch must open the source question immediately")
	}
	if afterBranch.probe != nil {
		t.Fatal("choosing a branch must not probe it before the source is known")
	}
	if len(afterBranch.next.Items) != 2 || afterBranch.next.Items[0].Value != "local" || afterBranch.next.Items[1].Value != "offline" {
		t.Fatalf("source items = %+v, want local and offline for a local-only branch", afterBranch.next.Items)
	}

	afterSource := afterBranch.next.OnPick("local")
	if afterSource.probe == nil {
		t.Fatal("choosing the source must run the first branch-scoped probe")
	}
}

func TestStartAssistantStopsCleanlyWhenThereAreNoBranches(t *testing.T) {
	result := buildBranchResult("")(domain.ConfigPorcelainResult{})
	if result.next != nil || result.probe != nil || result.done != nil {
		t.Fatalf("empty branch result opened a dead-end flow: %+v", result)
	}
	if result.status != domain.NoBranchesForReview {
		t.Fatalf("empty branch status = %q, want %q", result.status, domain.NoBranchesForReview)
	}
}

// TestSelectOverlayDoneNeverOpensConfirm: finishing a picker flow
// (handleSelectKey's result.done branch) runs beginMutation DIRECTLY —
// there is no code path from a SelectOverlay to ConfirmMutation at all.
func TestSelectOverlayDoneNeverOpensConfirm(t *testing.T) {
	req := mutationRequest{action: "startReview", params: domain.ActionParams{
		Intent: domain.ReviewIntent{Branch: "x", Source: "remote", Range: "full", Layout: "walk"},
	}}
	overlay := &SelectOverlay{
		Items:  []SelectItem{{Label: "x", Value: "x"}},
		OnPick: func(string) selectResult { return selectResult{done: &req} },
	}
	m := Model{selectOverlay: overlay}
	newM, cmd := m.handleSelectKey(tea.KeyMsg{Type: tea.KeyEnter})
	got, ok := newM.(Model)
	if !ok {
		t.Fatal("handleSelectKey must return a Model")
	}
	if got.confirm != nil {
		t.Fatal("finishing a select flow must never open the confirm overlay")
	}
	if got.selectOverlay != nil {
		t.Fatal("finishing a select flow must close the picker")
	}
	if cmd == nil {
		t.Fatal("a finished pick must dispatch the mutation")
	}
}

// TestSelectOverlayEscCancelsTheWholeFlow: Esc closes the picker without
// running anything — the same "closing it is a plain cancel" shape
// ConfirmOverlay uses.
func TestSelectOverlayEscCancelsTheWholeFlow(t *testing.T) {
	overlay := &SelectOverlay{Items: []SelectItem{{Label: "x", Value: "x"}}}
	m := Model{selectOverlay: overlay}
	newM, cmd := m.handleSelectKey(tea.KeyMsg{Type: tea.KeyEsc})
	got := newM.(Model)
	if got.selectOverlay != nil {
		t.Fatal("Esc must close the picker")
	}
	if cmd != nil {
		t.Fatal("cancelling must not dispatch anything")
	}
}

// TestHandleAssistantStepReportsAProbeFailureOnTheStatusLine — a failed
// config probe (spawn failure, non-zero exit) reports itself and leaves no
// picker open, rather than opening one built from empty/garbage stdout.
func TestHandleAssistantStepReportsAProbeFailureOnTheStatusLine(t *testing.T) {
	m := Model{selectOverlay: &SelectOverlay{}}
	newM, cmd := m.handleAssistantStep(assistantStepMsg{
		result: host.Result{ExitCode: 1, Stderr: "error: not a git repository"},
		build:  buildBranchStep(""),
	})
	if newM.selectOverlay != nil {
		t.Fatal("a failed probe must not leave a picker open")
	}
	if newM.statusLine == "" {
		t.Fatal("a failed probe must say something on the status line")
	}
	if cmd != nil {
		t.Fatal("a failed probe schedules nothing further")
	}
}

func TestStartAssistantShowsProgressBeforeTheFirstProbeReturns(t *testing.T) {
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationNoReview}, Viewport: Viewport{Cols: 80, Rows: 24}}
	after, cmd := m.startAssistant()
	if cmd == nil {
		t.Fatal("start assistant must run its config probe")
	}
	if after.progressOverlay == nil || !strings.Contains(after.View(), domain.ReadOptionsProgress) {
		t.Fatalf("assistant did not replace the base panel with progress:\n%s", after.View())
	}
	if !strings.Contains(after.View(), "q:quit") || !strings.Contains(after.View(), "::actions") {
		t.Fatalf("assistant progress hid its safe key bar:\n%s", after.View())
	}
}

func TestAssistantProgressKeepsOnlySafeKeysAvailable(t *testing.T) {
	m := Model{
		Panel:           fixtureFor(domain.LayoutNoReview),
		progressOverlay: &ProgressOverlay{Text: domain.ReadOptionsProgress},
	}
	quitModel, quitCmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'q'}})
	if quitCmd == nil || quitModel.(Model).progressOverlay == nil {
		t.Fatal("quit was swallowed by assistant progress")
	}
	paletteModel, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{':'}})
	if paletteModel.(Model).actionList == nil {
		t.Fatal("action palette was swallowed by assistant progress")
	}
	mouseModel, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'m'}})
	if !mouseModel.(Model).Panel.MouseEnabled {
		t.Fatal("mouse toggle was swallowed by assistant progress")
	}
	bodyModel, bodyCmd := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	if bodyCmd != nil || bodyModel.(Model).progressOverlay == nil {
		t.Fatal("assistant progress allowed a hidden body control")
	}
}

func TestAssistantOnlyShowsProgressWhenAQuestionNeedsAProbe(t *testing.T) {
	overlay := buildBranchStep("")(domain.ConfigPorcelainResult{Candidates: []domain.CandidateBranch{{Name: "feature/x", Origin: "local"}}})
	m := Model{
		Panel:         domain.PanelModel{Situation: domain.SituationNoReview},
		selectOverlay: &overlay,
	}
	updated, cmd := m.handleSelectKey(tea.KeyMsg{Type: tea.KeyEnter})
	after := updated.(Model)
	if cmd != nil || after.progressOverlay != nil || after.selectOverlay == nil || after.selectOverlay.Title != domain.StartAssistantSourceTitle {
		t.Fatalf("branch-to-source state: cmd=%v progress=%v select=%v", cmd != nil, after.progressOverlay != nil, after.selectOverlay != nil)
	}

	updated, cmd = after.handleSelectKey(tea.KeyMsg{Type: tea.KeyEnter})
	after = updated.(Model)
	if cmd == nil || after.progressOverlay == nil || after.selectOverlay != nil {
		t.Fatalf("source-probe state: cmd=%v progress=%v select=%v", cmd != nil, after.progressOverlay != nil, after.selectOverlay != nil)
	}
}

func TestStaleAssistantProbeCannotReplaceTheCurrentProgress(t *testing.T) {
	m := Model{assistantGeneration: 2, progressOverlay: &ProgressOverlay{Text: domain.ReadOptionsProgress}}
	updated, _ := m.handleAssistantStep(assistantStepMsg{
		assistantGeneration: 1,
		result:              host.Result{ExitCode: 0},
		build: func(domain.ConfigPorcelainResult) SelectOverlay {
			return SelectOverlay{Title: "stale"}
		},
	})
	if updated.progressOverlay == nil || updated.selectOverlay != nil {
		t.Fatal("a stale assistant result replaced the current progress surface")
	}
}

func TestRefreshCannotInvalidateAnAssistantProbe(t *testing.T) {
	probe := func() tea.Msg {
		return assistantStepMsg{
			result: host.Result{ExitCode: 0},
			build: func(domain.ConfigPorcelainResult) SelectOverlay {
				return SelectOverlay{Title: "current"}
			},
		}
	}
	m, probeCmd := (Model{}).beginAssistantProbe(probe)
	refreshing, _ := m.scheduleRead()
	msg := probeCmd().(assistantStepMsg)
	updated, _ := refreshing.handleAssistantStep(msg)
	if updated.progressOverlay != nil || updated.selectOverlay == nil || updated.selectOverlay.Title != "current" {
		t.Fatalf("refresh invalidated the active assistant probe: progress=%v select=%+v", updated.progressOverlay != nil, updated.selectOverlay)
	}
}
