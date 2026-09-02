package ui

import (
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

func TestActivityBlocksImmediatelyAndWaitsBeforeShowingProgress(t *testing.T) {
	m, cmd := (Model{Panel: domain.PanelModel{Situation: domain.SituationNoReview}}).
		startActivity(activityMutation, "Starting the review of feature/x…", true)
	if !m.presentationPanel().Busy {
		t.Fatal("an active mutation must disable stale controls immediately")
	}
	if got := m.presentationPanel().StatusLine; got != "" {
		t.Fatalf("progress flashed before the delay: %q", got)
	}
	if cmd == nil {
		t.Fatal("activity must schedule its delayed reveal")
	}

	shown, _ := m.Update(activityVisibleMsg{generation: m.activity.generation})
	if got := shown.(Model).presentationPanel().StatusLine; got != "Starting the review of feature/x…" {
		t.Fatalf("visible progress = %q", got)
	}
}

func TestStaleActivityTimerCannotRevealNewerActivity(t *testing.T) {
	first, _ := (Model{}).startActivity(activityReading, domain.WaitingText, true)
	firstGeneration := first.activity.generation
	second, _ := first.startActivity(activityMutation, "Creating the authoring guide…", true)

	got, _ := second.Update(activityVisibleMsg{generation: firstGeneration})
	if got.(Model).activity.visible {
		t.Fatal("a stale timer revealed the newer activity")
	}
}

func TestClearingAnOldActivityCannotClearTheCurrentOne(t *testing.T) {
	first, _ := (Model{}).startActivity(activityReading, domain.WaitingText, true)
	firstGeneration := first.activity.generation
	second, _ := first.startActivity(activityMutation, "Working…", true)

	got := second.clearActivity(firstGeneration)
	if !got.activity.active || got.activity.generation == firstGeneration {
		t.Fatal("clearing an old generation changed the current activity")
	}
}
