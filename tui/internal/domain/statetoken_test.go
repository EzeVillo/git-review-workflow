package domain

import "testing"

func TestStateTokenMatches(t *testing.T) {
	a := StateToken{Branch: "feature", HasBranch: true, Tip: "abc123", HasTip: true, Situation: SituationReview}
	b := a
	if !a.Matches(b) {
		t.Fatal("identical tokens must match")
	}
	b.Tip = "def456"
	if a.Matches(b) {
		t.Fatal("a different tip must not match")
	}
}

func TestStateTokenAbsentNeverMatchesPresentEvenWhenEmpty(t *testing.T) {
	absent := StateToken{Situation: SituationNoReview}
	presentEmpty := StateToken{Branch: "", HasBranch: true, Situation: SituationNoReview}
	if absent.Matches(presentEmpty) {
		t.Fatal("an absent branch must never match a present-but-empty one")
	}
	if !absent.Matches(StateToken{Situation: SituationNoReview}) {
		t.Fatal("two absent branches must match each other")
	}
}

func TestStateTokenSituationChangeBreaksTheMatch(t *testing.T) {
	a := StateToken{Situation: SituationReview}
	b := StateToken{Situation: SituationFinishConflict}
	if a.Matches(b) {
		t.Fatal("a changed situation must break the match, even with identical branch/tip")
	}
}
