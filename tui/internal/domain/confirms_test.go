package domain

import "testing"

func TestConfirmingIDsHasThirteenEntries(t *testing.T) {
	if len(ConfirmingIDs) != 13 {
		t.Fatalf("expected 13 confirming ids, got %d: %v", len(ConfirmingIDs), ConfirmingIDs)
	}
}

func TestStartNeverConfirmsOnEitherPath(t *testing.T) {
	// SE CONFIRMA LO QUE NO SE PUEDE DESHACER, y start no es eso en ninguno
	// de los dos caminos que llegan a el: el asistente y startFromDraft.
	for _, id := range []string{"startReview", "startFromDraft"} {
		if RequiresConfirmation(id) {
			t.Errorf("%s must never require confirmation", id)
		}
	}
}

func TestWalkthroughInitIsTheDeclaredException(t *testing.T) {
	if !RequiresConfirmation("walkthroughInit") {
		t.Fatal("walkthroughInit must stay confirms: true: a modal still sits between the gesture and the mutation")
	}
}

func TestRequiresConfirmationTable(t *testing.T) {
	for id := range ConfirmingIDs {
		if !RequiresConfirmation(id) {
			t.Errorf("%s is in ConfirmingIDs but RequiresConfirmation says false", id)
		}
	}
	if RequiresConfirmation("refresh") {
		t.Error("refresh must not require confirmation")
	}
}
