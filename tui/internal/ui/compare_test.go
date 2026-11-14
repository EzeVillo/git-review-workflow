package ui

import (
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	tea "github.com/charmbracelet/bubbletea"
)

// TestBeginCompareReviewChainsToAConfirmWithTheRightArgv is T089's own
// gate for compareReview: two free-text questions (target, base), a fixed
// layout picker from the exact range offers, and
// the LAST step opens ConfirmMutation with the literal id "compareReview"
// (gate 2, T067/T085) rather than running the mutation directly the way
// startReview's own chain does.
func TestBeginCompareReviewChainsToAConfirmWithTheRightArgv(t *testing.T) {
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationNoReview}}
	m2, _ := m.beginCompareReview()
	if m2.textPrompt == nil {
		t.Fatal("beginCompareReview must open the first free-text question")
	}
	if m2.textPrompt.Title != "What do you want to review?" {
		t.Fatalf("unexpected first question: %q", m2.textPrompt.Title)
	}

	targetResult := m2.textPrompt.OnSubmit("feature/x")
	if targetResult.nextPrompt == nil {
		t.Fatal("submitting the target revision must open the second question")
	}
	if targetResult.nextPrompt.Title != "Compare against what?" {
		t.Fatalf("unexpected second question: %q", targetResult.nextPrompt.Title)
	}

	if targetResult.nextPrompt.Context != "Reviewing feature/x." {
		t.Fatalf("target context lost: %q", targetResult.nextPrompt.Context)
	}
	baseResult := targetResult.nextPrompt.OnSubmit("develop")
	if baseResult.probe == nil {
		t.Fatal("submitting the base revision must query exact comparison offers")
	}
	cfg := domain.ConfigPorcelainResult{Offers: []domain.ReadingOffer{
		{ID: domain.OfferWalk, Rank: "recommended"},
		{ID: domain.OfferKeys, Rank: "available"},
		{ID: domain.OfferStep, Rank: "available"},
		{ID: domain.OfferWhole, Rank: "available"},
	}}
	offer := compareLayoutStep("develop", "feature/x", currentStateToken(m.Panel), cfg.Offers)

	if offer.Notice != "Review feature/x against develop" {
		t.Fatalf("range summary lost: %q", offer.Notice)
	}
	if offer.Items[2].Detail != domain.CompareStepDetail {
		t.Fatal("step semantics must be visible")
	}
	stepResult := offer.OnPick("step")
	if stepResult.confirmNext == nil {
		t.Fatal("picking a layout must open the SAME confirm gate the body uses, not run directly")
	}
	if stepResult.done != nil {
		t.Fatal("compareReview must never run without going through ConfirmMutation first")
	}
	overlay := stepResult.confirmNext
	if overlay.ID != "compareReview" {
		t.Fatalf("confirm overlay id = %q, want compareReview", overlay.ID)
	}
	if overlay.Pending.action != "compareReview" {
		t.Fatalf("pending action = %q, want compareReview", overlay.Pending.action)
	}
	params := overlay.Pending.params
	if params.CompareLower != "develop" || params.CompareUpper != "feature/x" {
		t.Fatalf("params lower/upper = %q/%q, want develop/feature/x", params.CompareLower, params.CompareUpper)
	}
	if len(params.CompareLayout) != 1 || params.CompareLayout[0] != "--step" {
		t.Fatalf("CompareLayout = %v, want [--step]", params.CompareLayout)
	}

	argv, ok := domain.BuildArgv("compareReview", params)
	if !ok {
		t.Fatal("BuildArgv(compareReview) must succeed")
	}
	wantArgs := []string{"--step", "--", "develop", "feature/x"}
	if argv.Verb != "compare" || len(argv.Args) != len(wantArgs) {
		t.Fatalf("argv = %+v, want verb=compare args=%v", argv, wantArgs)
	}
	for i, a := range wantArgs {
		if argv.Args[i] != a {
			t.Fatalf("argv.Args[%d] = %q, want %q (full: %v)", i, argv.Args[i], a, argv.Args)
		}
	}
}

// TestCompareLayoutFlagsMatchIntentToArgsVocabulary: the four layout flags
// compare uses are the exact same vocabulary IntentToArgs uses for start
// (research.md: "flags de layout" is shared), so a layout picked here never
// invents a flag the CLI does not already understand from `start`.
func TestCompareLayoutFlagsMatchIntentToArgsVocabulary(t *testing.T) {
	cases := map[string][]string{
		"walk":  nil,
		"keys":  {"--keys"},
		"step":  {"--step"},
		"whole": {"--no-walk"},
	}
	for layout, want := range cases {
		got := compareLayoutFlags(layout)
		if len(got) != len(want) {
			t.Fatalf("compareLayoutFlags(%q) = %v, want %v", layout, got, want)
		}
		for i := range want {
			if got[i] != want[i] {
				t.Fatalf("compareLayoutFlags(%q) = %v, want %v", layout, got, want)
			}
		}
	}
}

// TestTextPromptCancelClosesWithoutSubmitting mirrors every other overlay's
// own "closing it is the same as cancelling" shape.
func TestTextPromptCancelClosesWithoutSubmitting(t *testing.T) {
	called := false
	p := NewTextPrompt("t", "placeholder", func(string) selectResult {
		called = true
		return selectResult{}
	})
	m := Model{textPrompt: p}
	m2, _ := m.handleTextPromptKey(tea.KeyMsg{Type: tea.KeyEsc})
	got := m2.(Model)
	if got.textPrompt != nil {
		t.Fatal("esc must close the prompt")
	}
	if called {
		t.Fatal("esc must never call OnSubmit")
	}
}

// TestTextPromptEmptyValueDoesNotSubmit: Enter on an empty input is a
// no-op, not a submission with an empty string — compareReview has no
// sensible "" revision to send the CLI.
func TestTextPromptEmptyValueDoesNotSubmit(t *testing.T) {
	called := false
	p := NewTextPrompt("t", "placeholder", func(string) selectResult {
		called = true
		return selectResult{}
	})
	_, submitted, cancelled, _ := p.HandleKey(tea.KeyMsg{Type: tea.KeyEnter})
	if submitted || cancelled || called {
		t.Fatalf("Enter on an empty input must be inert: submitted=%v cancelled=%v called=%v", submitted, cancelled, called)
	}
}

func TestComparisonOffersAndDraftContinuation(t *testing.T) {
	id := "compare/0123456789012345678901234567890123456789"
	row := "draft\t" + id + "\t/repo/.git/order.md\t2\t2\tcompare\tfull\tfresh"
	title := "draft-title\t" + id + "\tmain → release"
	cfg := domain.ParseConfigPorcelain(title + "\n" + row)
	if len(cfg.Drafts) != 1 || cfg.Drafts[0].Title != "main → release" || cfg.Drafts[0].Source != domain.DraftSourceCompare {
		t.Fatalf("draft context lost: %+v", cfg.Drafts)
	}
	panel := domain.PanelModel{Situation: domain.SituationNoReview, NoBaseConfigured: true, FreshDraftRows: domain.FooterField(id, "/draft.md", "compare", "full", "2", "2", "main → release")}
	haveStart, haveCompare := false, false
	for _, control := range ControlsFor(panel) {
		if control.ID == "startFromDraft" && control.Variant == id && control.Enabled {
			haveStart = true
		}
		if control.ID == "compareReview" && control.Enabled {
			haveCompare = true
		}
	}
	if !haveStart || !haveCompare {
		t.Fatalf("setup hides comparison continuation: %+v", ControlsFor(panel))
	}
	req := startFromDraftRequest(draftRowView{src: id, source: "compare", rrange: "full"}, "keys")
	if req.argv == nil || req.argv.Verb != "compare" || len(req.argv.Args) != 4 || req.argv.Args[0] != "--keys" || req.argv.Args[1] != "--draft" || req.argv.Args[3] != id {
		t.Fatalf("draft starts another review: %+v", req.argv)
	}
	offers := []domain.ReadingOffer{{ID: domain.OfferDraft, Rank: "available"}, {ID: domain.OfferWhole, Rank: "available"}}
	overlay := compareLayoutStep("a", "b", domain.StateToken{}, offers)
	if len(overlay.Items) != 2 || overlay.Items[0].Value != "draft" || overlay.Items[1].Value != "whole" {
		t.Fatalf("invented unsupported layouts: %+v", overlay.Items)
	}
	result := overlay.OnPick("draft")
	if result.confirmNext != nil || result.done == nil || result.done.argv == nil || result.done.argv.Verb != "walkthrough" {
		t.Fatalf("draft must prepare reading order without a confirmation: %+v", result)
	}
	args := result.done.argv.Args
	if len(args) != 6 || args[2] != "--compare" || args[4] != "a" || args[5] != "b" {
		t.Fatalf("wrong range: %v", args)
	}
}
