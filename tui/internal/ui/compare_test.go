package ui

import (
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	tea "github.com/charmbracelet/bubbletea"
)

// TestBeginCompareReviewChainsToAConfirmWithTheRightArgv is T089's own
// gate for compareReview: two free-text questions (lower, upper), a fixed
// four-item layout picker (no `offer` filtering — cli-invocation.md), and
// the LAST step opens ConfirmMutation with the literal id "compareReview"
// (gate 2, T067/T085) rather than running the mutation directly the way
// startReview's own chain does.
func TestBeginCompareReviewChainsToAConfirmWithTheRightArgv(t *testing.T) {
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationNoReview}}
	m2, _ := m.beginCompareReview()
	if m2.textPrompt == nil {
		t.Fatal("beginCompareReview must open the first free-text question")
	}
	if m2.textPrompt.Title != domain.CompareLowerTitle {
		t.Fatalf("first question title = %q, want %q", m2.textPrompt.Title, domain.CompareLowerTitle)
	}

	lowerResult := m2.textPrompt.OnSubmit("develop")
	if lowerResult.nextPrompt == nil {
		t.Fatal("submitting the lower revision must open the SECOND free-text question")
	}
	if lowerResult.nextPrompt.Title != domain.CompareUpperTitle {
		t.Fatalf("second question title = %q, want %q", lowerResult.nextPrompt.Title, domain.CompareUpperTitle)
	}

	upperResult := lowerResult.nextPrompt.OnSubmit("feature/x")
	if upperResult.next == nil {
		t.Fatal("submitting the upper revision must open the layout picker")
	}
	if len(upperResult.next.Items) != 4 {
		t.Fatalf("layout picker has %d items, want 4 (no offer filtering for compare)", len(upperResult.next.Items))
	}

	stepResult := upperResult.next.OnPick("step")
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
