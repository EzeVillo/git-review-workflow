package ui

import (
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
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

func TestResolvedPanelRefreshShowsDelayedReadingFeedbackUntilReadReturns(t *testing.T) {
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationNoReview}}
	refreshing, cmd := m.scheduleRead()
	if cmd == nil || !refreshing.presentationPanel().Busy {
		t.Fatalf("refresh did not become busy: cmd=%v busy=%v", cmd != nil, refreshing.presentationPanel().Busy)
	}
	if refreshing.presentationPanel().StatusLine != "" {
		t.Fatal("a fast refresh flashed its progress")
	}
	shownModel, _ := refreshing.Update(activityVisibleMsg{generation: refreshing.activity.generation})
	shown := shownModel.(Model)
	if shown.presentationPanel().StatusLine != domain.WaitingText {
		t.Fatalf("reading progress = %q", shown.presentationPanel().StatusLine)
	}
	resolvedModel, _ := shown.Update(readDoneMsg{generation: shown.readGeneration, result: host.ReadResult{Situation: domain.SituationNoReview}})
	if resolvedModel.(Model).activity.active {
		t.Fatal("accepted read left reading activity active")
	}
}
