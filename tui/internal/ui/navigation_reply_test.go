package ui

import (
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
)

func TestCommentsAddReplyUsesOnlyTheCurrentRead(t *testing.T) {
	before, after, guard, revision := strings.Repeat("a", 40), strings.Repeat("b", 40), strings.Repeat("c", 40), strings.Repeat("d", 40)
	wire := "comments-add-result\t1\t" + before + "\t" + after + "\n" +
		"comments-identity\tresolved\tCurrent\ncomments-guard\t" + guard + "\ncomments-context\tc1\treview\tactive\t" + guard + "\tCurrent\n" +
		"comments-document\t/local.md\tc1\tlocal\tpresent\t" + revision + "\ncomments-count\t/local.md\t1\ncomments-add-result-end\t1\n"
	reply, ok := domain.ParseCommentsAddReply(wire, "local")
	if !ok {
		t.Fatal("invalid reply fixture")
	}
	if _, ok := domain.ParseCommentsAddReply(strings.TrimSuffix(wire, "comments-add-result-end\t1\n"), "local"); ok {
		t.Fatal("accepted an incomplete reply")
	}
	primary := host.ReadResult{Situation: domain.SituationReview, Guard: before}
	for _, generation := range []int{4, 5} {
		m := Model{Panel: domain.Project(toProjectInput(primary, false, false, "")), lastRead: primary, readGeneration: generation}
		m.lock.Begin()
		got, _ := m.handleMutationDone(mutationDoneMsg{action: "addComment", result: host.Result{ExitCode: 0}, commentsReply: &reply, commentsReadGen: 4})
		if generation == 4 && (got.Panel.Guard != after || got.Panel.Comments != reply.Report) {
			t.Fatal("current reply did not update the panel")
		}
		if generation == 5 && (got.Panel.Guard != before || got.Panel.Comments != "") {
			t.Fatal("obsolete reply replaced the panel")
		}
	}
}

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

func TestContinueReplyPublishesAndRetainsCapabilitiesBeforeDetails(t *testing.T) {
	guard := strings.Repeat("b", 40)
	wire := "continue-state\t1\nstate\treview/x\tx\tdeadbeef\twhole\tnone\ncapability\tsave-state\nguard\t" + guard + "\ncontinue-state\tcomplete\n"
	primary, ok := host.ReadContinueReply(wire)
	if !ok || !primary.SaveState || primary.Guard != guard {
		t.Fatal("final review/capabilities missing")
	}
	m := Model{Panel: domain.PanelModel{Situation: domain.SituationNoReview, ContinueGuard: strings.Repeat("a", 40)}, readGeneration: 4}
	m.lock.Begin()
	got, cmd := m.handleMutationDone(mutationDoneMsg{action: "continueReview", result: host.Result{ExitCode: 0}, navigation: &primary})
	if cmd == nil || got.Panel.Situation != domain.SituationReview || got.lock.Busy() || !got.Panel.CommentsLoading || got.Panel.ContinueGuard != "" || !got.Panel.SaveState {
		t.Fatalf("Continue did not publish and unlock: %#v", got.Panel)
	}
	after, _ := got.handleReadDone(readDoneMsg{generation: 4, result: host.ReadResult{Situation: domain.SituationNoReview}})
	if after.Panel != got.Panel {
		t.Fatal("old details overwrote Continue")
	}
}

func TestSavedInventoryGuardReachesTheConfirmationToken(t *testing.T) {
	guard := strings.Repeat("a", 40)
	wire := "save-state\t1\nstatus\t2\nlist\tcapability\tcontinue-state\nlist\tcontinue-guard\t" + guard + "\nlist\tbranch\treview-saved/feature\t1\t0\t0\twhole\nconfig\tconfig\tremote\torigin\nsave-state\tcomplete\n"
	primary, ok := host.ReadSaveReply(wire)
	if !ok {
		t.Fatal("invalid fixture")
	}
	panel := domain.Project(toProjectInput(primary, false, false, ""))
	if currentStateToken(panel).ContinueGuard != guard {
		t.Fatal("inventory guard lost before confirmation")
	}
}
