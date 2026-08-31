package domain

import "testing"

func TestLayoutSituationForCoversAllElevenKeys(t *testing.T) {
	cases := []struct {
		name string
		m    PanelModel
		want LayoutSituation
	}{
		{"cli-missing", PanelModel{Situation: SituationCliMissing}, LayoutCliMissing},
		{"cli-outdated", PanelModel{Situation: SituationCliOutdated}, LayoutCliOutdated},
		{"no-review-setup", PanelModel{Situation: SituationNoReview, NoBaseConfigured: true}, LayoutNoReviewSetup},
		{"no-review", PanelModel{Situation: SituationNoReview, NoBaseConfigured: false}, LayoutNoReview},
		{"review-walk", PanelModel{Situation: SituationReview, Mode: ModeWalk}, LayoutReviewWalk},
		{"review-step", PanelModel{Situation: SituationReview, Mode: ModeStep}, LayoutReviewStep},
		{"review-whole", PanelModel{Situation: SituationReview, Mode: ModeWhole}, LayoutReviewWhole},
		{"finish-pending", PanelModel{Situation: SituationFinishPending}, LayoutFinishPending},
		{"finish-conflict", PanelModel{Situation: SituationFinishConflict}, LayoutFinishConflict},
		{"out-of-range", PanelModel{Situation: SituationOutOfRange}, LayoutOutOfRange},
		{"error", PanelModel{Situation: SituationError}, LayoutError},
	}
	seen := map[LayoutSituation]bool{}
	for _, c := range cases {
		got := LayoutSituationFor(c.m)
		if got != c.want {
			t.Errorf("%s: LayoutSituationFor = %q, want %q", c.name, got, c.want)
		}
		seen[got] = true
	}
	if len(seen) != len(AllLayoutSituations) {
		t.Fatalf("test cases cover %d of the %d layout situations", len(seen), len(AllLayoutSituations))
	}
	for _, sit := range AllLayoutSituations {
		if !seen[sit] {
			t.Errorf("no test case produces layout situation %q", sit)
		}
	}
}
