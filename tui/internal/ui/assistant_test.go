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
	if pick1.cmd == nil || pick1.next != nil || pick1.done != nil {
		t.Fatal("picking the branch must run the second probe, and nothing else")
	}

	sourceStep := buildSourceStep("feat-x", "local", probe1Candidates)(domain.ConfigPorcelainResult{
		Deltas: []domain.DeltaRecord{{Name: "feat-x", Tip: "abc1234", Origin: "local"}},
	})
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
	if pick2.next == nil {
		t.Fatal("picking a source must build the range step directly — no probe needed, the deltas are already known")
	}
	if pick2.cmd != nil || pick2.done != nil {
		t.Fatal("the source step must not run a probe or finish the flow")
	}

	rangeStep := *pick2.next
	if rangeStep.Title != domain.StartAssistantRangeTitle {
		t.Fatalf("range step title = %q", rangeStep.Title)
	}
	if len(rangeStep.Items) != 2 {
		t.Fatalf("got %d range items, want 2 (full + delta, since a local delta marker exists)", len(rangeStep.Items))
	}
	pick3 := rangeStep.OnPick("delta")
	if pick3.cmd == nil {
		t.Fatal("picking a range must run the third, scoped probe")
	}

	layoutStep := buildLayoutStep("feat-x", "local", "delta")(domain.ConfigPorcelainResult{
		Offers: []domain.ReadingOffer{
			{ID: domain.OfferWalk, Rank: "recommended"},
			{ID: domain.OfferWhole, Rank: "available"},
		},
	})
	if layoutStep.Title != domain.StartAssistantLayoutTitle {
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

// TestRangeStepOffersOnlyFullWhenNoDeltaExists — the "full" option is
// always there; "delta" only when the CLI actually reported a marker for
// the chosen source.
func TestRangeStepOffersOnlyFullWhenNoDeltaExists(t *testing.T) {
	step := buildRangeStep("feat-x", "remote", nil)
	if len(step.Items) != 1 || step.Items[0].Value != "full" {
		t.Fatalf("items = %+v, want only 'full' with no delta records", step.Items)
	}
}

// TestSourceStepOffersOnlyWhatCandidatesReport — a branch that only exists
// locally must not offer "remote".
func TestSourceStepOffersOnlyWhatCandidatesReport(t *testing.T) {
	localOnly := []domain.CandidateBranch{{Name: "feat-x", Origin: "local"}}
	step := buildSourceStep("feat-x", "", localOnly)(domain.ConfigPorcelainResult{})
	for _, it := range step.Items {
		if it.Value == "remote" {
			t.Fatal("a branch with no remote candidate row must not offer 'remote'")
		}
	}
	if len(step.Items) != 2 {
		t.Fatalf("got %d items, want 2 (local + offline)", len(step.Items))
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
}

func TestAssistantKeepsProgressBetweenQuestions(t *testing.T) {
	overlay := buildBranchStep("")(domain.ConfigPorcelainResult{Candidates: []domain.CandidateBranch{{Name: "feature/x", Origin: "local"}}})
	m := Model{
		Panel:         domain.PanelModel{Situation: domain.SituationNoReview},
		selectOverlay: &overlay,
	}
	updated, cmd := m.handleSelectKey(tea.KeyMsg{Type: tea.KeyEnter})
	after := updated.(Model)
	if cmd == nil || after.progressOverlay == nil || after.selectOverlay != nil {
		t.Fatalf("between-question state: cmd=%v progress=%v select=%v", cmd != nil, after.progressOverlay != nil, after.selectOverlay != nil)
	}
}

func TestStaleAssistantProbeCannotReplaceTheCurrentProgress(t *testing.T) {
	m := Model{activityGeneration: 2, progressOverlay: &ProgressOverlay{Text: domain.ReadOptionsProgress}}
	updated, _ := m.handleAssistantStep(assistantStepMsg{
		activityGeneration: 1,
		result:             host.Result{ExitCode: 0},
		build: func(domain.ConfigPorcelainResult) SelectOverlay {
			return SelectOverlay{Title: "stale"}
		},
	})
	if updated.progressOverlay == nil || updated.selectOverlay != nil {
		t.Fatal("a stale assistant result replaced the current progress surface")
	}
}
