package ui

import (
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	tea "github.com/charmbracelet/bubbletea"
)

func TestConfirmOverlayHandleKeyAcceptAndCancel(t *testing.T) {
	o := &ConfirmOverlay{ID: "abortReview"}
	if _, resolved := o.HandleKey("j"); resolved {
		t.Fatal("an unrelated key must not resolve at all")
	}
	if choice, resolved := o.HandleKey("y"); !resolved || choice != domain.ConfirmAccepted {
		t.Fatalf("'y' must accept, got choice=%v resolved=%v", choice, resolved)
	}
	if choice, resolved := o.HandleKey("enter"); !resolved || choice != domain.ConfirmAccepted {
		t.Fatalf("'enter' must also accept, got choice=%v resolved=%v", choice, resolved)
	}
	if choice, resolved := o.HandleKey("esc"); !resolved || choice != domain.ConfirmCancelled {
		t.Fatalf("'esc' must cancel, got choice=%v resolved=%v", choice, resolved)
	}
	if choice, resolved := o.HandleKey("n"); !resolved || choice != domain.ConfirmCancelled {
		t.Fatalf("'n' must cancel, got choice=%v resolved=%v", choice, resolved)
	}
}

// TestStateTokenRevalidatedInsideTheLockBlocksAStaleMutation is T065's own
// gate: the token captured when the confirmation opened is revalidated
// AGAIN, inside the lock, right before the spawn. A state change while the
// overlay sat open (the panel can repaint underneath it in a watching TUI)
// must cancel the mutation instead of running it against stale data.
func TestStateTokenRevalidatedInsideTheLockBlocksAStaleMutation(t *testing.T) {
	openedToken := domain.StateToken{
		Branch: "feat-x", HasBranch: true, Tip: "aaa", HasTip: true,
		Situation: domain.SituationReview,
	}
	req := mutationRequest{action: "abortReview", params: domain.ActionParams{}}

	// The repository moved on (a different tip) by the time "yes" is
	// pressed — simulated directly on Panel, since currentStateToken reads
	// Branch/Tip/Situation off it.
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationReview, Branch: "feat-x", Tip: "bbb"}}
	got, cmd := m.beginMutation(req, openedToken)
	if cmd != nil {
		t.Fatal("a stale token must never spawn a process")
	}
	if got.statusLine != domain.StaleNotice {
		t.Errorf("statusLine = %q, want domain.StaleNotice", got.statusLine)
	}
	if got.lock.Busy() {
		t.Fatal("a cancelled lock must not stay busy — Cancel() must release it")
	}
}

func TestStateTokenStillMatchingLetsTheMutationThrough(t *testing.T) {
	token := domain.StateToken{Branch: "feat-x", HasBranch: true, Tip: "aaa", HasTip: true, Situation: domain.SituationReview}
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationReview, Branch: "feat-x", Tip: "aaa"}}
	got, cmd := m.beginMutation(mutationRequest{action: "saveReview"}, token)
	if cmd == nil {
		t.Fatal("a token that still matches must let the mutation spawn")
	}
	if !got.lock.Busy() {
		t.Fatal("a spawned mutation must leave the lock busy")
	}
}

// TestBeginMutationDiscardsASecondMutationWhileOneIsRunning is T063's own
// gate at the ui level: depth 1, discarded with a notice, never queued.
func TestBeginMutationDiscardsASecondMutationWhileOneIsRunning(t *testing.T) {
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationReview, Branch: "x"}}
	m.lock.Begin() // one already in flight
	token := currentStateToken(m.Panel)
	got, cmd := m.beginMutation(mutationRequest{action: "saveReview"}, token)
	if cmd != nil {
		t.Fatal("a second mutation while one is running must be discarded, never queued")
	}
	if got.statusLine != domain.MutationDiscardedNotice {
		t.Errorf("statusLine = %q, want domain.MutationDiscardedNotice", got.statusLine)
	}
}

func TestHandleConfirmKeyRunsOnAcceptAndDoesNothingOnCancel(t *testing.T) {
	panel := domain.PanelModel{Situation: domain.SituationReview, Branch: "x"}
	req := mutationRequest{action: "abortReview", params: domain.ActionParams{}}
	overlay := ConfirmMutation("abortReview", "t", "d", "l", currentStateToken(panel), req)

	cancelled := Model{Panel: panel, confirm: overlay}
	newM, cmd := cancelled.handleConfirmKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'n'}})
	got, ok := newM.(Model)
	if !ok {
		t.Fatal("handleConfirmKey must return a Model")
	}
	if got.confirm != nil {
		t.Fatal("cancelling must close the overlay")
	}
	if cmd != nil {
		t.Fatal("cancelling must never run the mutation")
	}

	accepted := Model{Panel: panel, confirm: overlay}
	newM2, cmd2 := accepted.handleConfirmKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'y'}})
	got2 := newM2.(Model)
	if got2.confirm != nil {
		t.Fatal("accepting must close the overlay")
	}
	if cmd2 == nil {
		t.Fatal("accepting must run the mutation")
	}
}

// TestHandleConfirmKeyStillOpenOnUnrelatedKey: an unresolved key (still
// waiting) must not close the overlay or touch the lock.
func TestHandleConfirmKeyStillOpenOnUnrelatedKey(t *testing.T) {
	overlay := ConfirmMutation("abortReview", "t", "d", "l", domain.StateToken{}, mutationRequest{action: "abortReview"})
	m := Model{confirm: overlay}
	newM, cmd := m.handleConfirmKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'j'}})
	got := newM.(Model)
	if got.confirm == nil {
		t.Fatal("an unrelated key must leave the overlay open")
	}
	if cmd != nil {
		t.Fatal("an unrelated key must not do anything")
	}
}
