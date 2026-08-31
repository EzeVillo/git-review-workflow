package ui

import (
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

// T048's named gate: in finish-conflict, the cursor keys (n/p) are neither
// available nor shown — the bar reflects the situation, not a fixed set.
func TestFinishConflictHidesAndDisablesCursorKeys(t *testing.T) {
	m := domain.PanelModel{Situation: domain.SituationFinishConflict, Mode: domain.ModeWalk, FinishConflict: true}

	for _, key := range []string{"n", "p"} {
		intent := ResolveKey(key, Model{Panel: m})
		if intent.Kind == IntentCursorAction {
			t.Errorf("key %q must not resolve to a cursor action in finish-conflict, got %+v", key, intent)
		}
	}

	bar := KeyBarFor(m)
	for _, item := range bar {
		if item.Key == "n" || item.Key == "p" {
			t.Errorf("finish-conflict's key bar must not offer n/p, got %+v", bar)
		}
	}
}

// The mirror positive case: review-walk and review-step DO have a live
// cursor, so n/p both resolve and appear in the bar.
func TestReviewWalkAndStepExposeCursorKeys(t *testing.T) {
	for _, mode := range []domain.ReviewMode{domain.ModeWalk, domain.ModeStep} {
		m := domain.PanelModel{Situation: domain.SituationReview, Mode: mode}
		nextIntent := ResolveKey("n", Model{Panel: m})
		if nextIntent.Kind != IntentCursorAction || nextIntent.Action != "next" {
			t.Errorf("%s: key n = %+v, want IntentCursorAction/next", mode, nextIntent)
		}
		prevIntent := ResolveKey("p", Model{Panel: m})
		if prevIntent.Kind != IntentCursorAction || prevIntent.Action != "prev" {
			t.Errorf("%s: key p = %+v, want IntentCursorAction/prev", mode, prevIntent)
		}
		bar := KeyBarFor(m)
		sawN, sawP := false, false
		for _, item := range bar {
			if item.Key == "n" {
				sawN = true
			}
			if item.Key == "p" {
				sawP = true
			}
		}
		if !sawN || !sawP {
			t.Errorf("%s: key bar = %+v, want both n and p", mode, bar)
		}
	}
}

// review-whole has no cursor at all (no next/prev control, Layout[] is
// empty for it) — n/p must not resolve there either.
func TestReviewWholeHasNoCursorKeys(t *testing.T) {
	m := domain.PanelModel{Situation: domain.SituationReview, Mode: domain.ModeWhole}
	if intent := ResolveKey("n", Model{Panel: m}); intent.Kind == IntentCursorAction {
		t.Errorf("review-whole must not expose the cursor key, got %+v", intent)
	}
}

// FR-038: 'r' resolves to the bound refresh action in all eight situations.
func TestRefreshKeyResolvesInAllEightSituations(t *testing.T) {
	models := []domain.PanelModel{
		{Situation: domain.SituationCliMissing},
		{Situation: domain.SituationCliOutdated},
		{Situation: domain.SituationNoReview},
		{Situation: domain.SituationFinishPending},
		{Situation: domain.SituationReview, Mode: domain.ModeWhole},
		{Situation: domain.SituationFinishConflict},
		{Situation: domain.SituationOutOfRange},
		{Situation: domain.SituationError},
	}
	for _, m := range models {
		intent := ResolveKey("r", Model{Panel: m})
		if intent.Kind != IntentBoundAction || intent.Action != "refresh" {
			t.Errorf("%s: key r = %+v, want refresh", m.Situation, intent)
		}
		found := false
		for _, item := range KeyBarFor(m) {
			if item.Key == "r" {
				found = true
			}
		}
		if !found {
			t.Errorf("%s: key bar missing r/refresh", m.Situation)
		}
	}
}

func TestQuitKeysResolve(t *testing.T) {
	for _, key := range []string{"q", "ctrl+c"} {
		intent := ResolveKey(key, Model{})
		if intent.Kind != IntentQuit {
			t.Errorf("key %q = %+v, want IntentQuit", key, intent)
		}
	}
}

func TestMovementResolvesToFocusIntents(t *testing.T) {
	m := domain.PanelModel{Situation: domain.SituationNoReview, NoBaseConfigured: true}
	next := ResolveKey("j", Model{Panel: m})
	if next.Kind != IntentFocusMove || next.Movement != "focus_next_row" {
		t.Fatalf("j = %+v", next)
	}
	prev := ResolveKey("k", Model{Panel: m})
	if prev.Kind != IntentFocusMove || prev.Movement != "focus_prev_row" {
		t.Fatalf("k = %+v", prev)
	}
}

func TestMouseToggleResolves(t *testing.T) {
	intent := ResolveKey("m", Model{})
	if intent.Kind != IntentToggle || intent.Toggle != "mouse_reporting" {
		t.Fatalf("m = %+v, want IntentToggle/mouse_reporting", intent)
	}
}
