package ui

import (
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
)

func TestNavigationPublishesTheReplyAndRejectsOldDetails(t *testing.T) {
	reply := "state\treview/x\tx\tdeadbeef\twalk\tapplied\t2\t2\t2\tb.txt\t0\nentry\t1\ta.txt\t0\t1\nentry\t2\tb.txt\t0\t1\ncapability\tnavigation-state\nguard\t" + strings.Repeat("b", 40) + "\nnavigation\tmoved\n"
	primary, _, ok := host.ReadNavigationReply(reply)
	if !ok {
		t.Fatal("fixture is not a navigation reply")
	}
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationReview, Position: 1}, readGeneration: 4}
	m.lock.Begin()
	got, cmd := m.handleMutationDone(mutationDoneMsg{action: "next", result: host.Result{ExitCode: 0}, navigation: &primary})
	if cmd == nil || got.Panel.Position != 2 || got.lock.Busy() || !got.Panel.CommentsLoading {
		t.Fatalf("navigation did not publish and unlock: %#v", got.Panel)
	}
	old := host.ReadResult{Situation: domain.SituationNoReview, Comments: "obsolete"}
	after, _ := got.handleReadDone(readDoneMsg{generation: 4, result: old})
	if after.Panel != got.Panel {
		t.Fatal("old details overwrote navigation")
	}
}

func TestSaveReplyPublishesSavedReviewAndRejectsOldDetails(t *testing.T) {
	wire := "save-state\t1\nstatus\t2\nlist\tbranch\treview-saved/feature\t1\t0\t0\twalk\t2\t3\nconfig\tconfig\tbase\tmain\nconfig\tconfig\tremote\torigin\nsave-state\tcomplete\n"
	primary, ok := host.ReadSaveReply(wire)
	if !ok || !primary.HasList || !primary.HasConfig {
		t.Fatal("final reports missing")
	}
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationReview}, readGeneration: 4}
	m.lock.Begin()
	got, cmd := m.handleMutationDone(mutationDoneMsg{action: "saveReview", result: host.Result{ExitCode: 0}, navigation: &primary})
	if cmd == nil || got.Panel.Situation != domain.SituationNoReview || got.lock.Busy() || !got.Panel.CommentsLoading {
		t.Fatalf("Save did not publish and unlock: %#v", got.Panel)
	}
	after, _ := got.handleReadDone(readDoneMsg{generation: 4, result: host.ReadResult{Situation: domain.SituationReview}})
	if after.Panel != got.Panel {
		t.Fatal("old details overwrote Save")
	}
}
