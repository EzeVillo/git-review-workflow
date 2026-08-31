package domain

import "testing"

// isPanelModelComparable FAILS TO COMPILE — not to run — the moment
// PanelModel gains a field that is not comparable (a slice, a map, a
// pointer): Go rejects `==` between two values of a type that is not
// comparable at compile time, so this line IS the test SC-004 depends on.
// Any variable-length data must keep traveling as a pre-joined string plus
// its count, never as a slice.
var isPanelModelComparable = PanelModel{} == PanelModel{}

func TestPanelModelIsComparableByValue(t *testing.T) {
	if !isPanelModelComparable {
		t.Fatal("two zero-value PanelModel values must compare equal")
	}
	a := PanelModel{Situation: SituationReview, Branch: "feature", Position: 1}
	b := a
	if a != b {
		t.Fatal("two identical PanelModel values must compare equal")
	}
	b.Position = 2
	if a == b {
		t.Fatal("changing one field must make the models compare unequal")
	}
}
