package ui

import (
	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	tea "github.com/charmbracelet/bubbletea"
	"strings"
	"testing"
)

func commentModel() Model {
	m := NewModel()
	m.Panel = domain.PanelModel{Situation: domain.SituationReview, Mode: domain.ModeWhole, Branch: "review/feature", Tip: "tip", Comments: "comments-capability\tadd\tlocal\ncomments-capability\tadd\tshared\ncomments-guard\tstep1\ncomments-identity\tfresh\tNew"}
	m.commentsForm = newCommentsForm("step1", "", []string{"local", "shared"})
	return m
}

func TestMainCommentsKeepsIndependentEmptyStatesAfterReading(t *testing.T) {
	for _, setup := range []bool{false, true} {
		m := commentFixture("main-empty")
		m.Panel.NoBaseConfigured = setup
		frame, _, _ := viewWithState(m.Panel, Viewport{Cols: 120, Rows: 100}, renderState{})
		for _, text := range []string{domain.CommentsTitle, domain.CommentsLocal, domain.CommentsEmptyLocal, domain.CommentsShared, domain.CommentsEmptyShared} {
			if !strings.Contains(frame, text) {
				t.Fatalf("setup=%v missing %q:\n%s", setup, text, frame)
			}
		}
		if len(commentsControls(m.Panel)) != 0 {
			t.Fatal("empty comments exposed document actions")
		}
	}
}

func TestPendingCommentsStayVisibleWithoutEmptyStatesOrControls(t *testing.T) {
	m := commentFixture("main-empty")
	m.Panel.CommentsLoading = true
	frame, _, _ := viewWithState(m.Panel, Viewport{Cols: 120, Rows: 100}, renderState{})
	if !strings.Contains(frame, domain.CommentsReading) || strings.Contains(frame, domain.CommentsEmptyLocal) || strings.Contains(frame, domain.CommentsEmptyShared) {
		t.Fatalf("pending comments misrepresented the document state:\n%s", frame)
	}
	if len(commentsControls(m.Panel)) != 0 {
		t.Fatal("pending comments exposed document controls")
	}
}

func TestLateCommentDetailsCannotReplaceNewerReviewState(t *testing.T) {
	m := NewModel()
	m.readGeneration = 2
	m.Panel = domain.PanelModel{Situation: domain.SituationReview, Branch: "review/new", Tip: "new"}
	next, cmd := m.Update(readDoneMsg{generation: 1, result: host.ReadResult{Situation: domain.SituationNoReview, Comments: "comments-identity\tfresh\tOld"}})
	after := next.(Model)
	if cmd != nil || after.Panel != m.Panel {
		t.Fatal("late details replaced the current review")
	}
}

func TestMainCommentsMissingKindPreservesPhysicalDocumentIndex(t *testing.T) {
	for _, kind := range []string{"local", "shared"} {
		m := commentFixture("main-empty")
		m.Panel.Comments = "comments-context\tc\treview\tresult\tg\tFeature\ncomments-document\t/l\tc\tlocal\tabsent\tabsent\ncomments-document\t/s\tc\t" + kind + "\tpresent\tr"
		frame, _, _ := viewWithState(m.Panel, Viewport{Cols: 120, Rows: 100}, renderState{})
		want, absent := domain.CommentsEmptyShared, domain.CommentsEmptyLocal
		if kind == "shared" {
			want, absent = absent, want
		}
		if !strings.Contains(frame, want) || strings.Contains(frame, absent) {
			t.Fatalf("incorrect empty state beside %s:\n%s", kind, frame)
		}
		for _, c := range commentsControls(m.Panel) {
			if c.ID == "openComments" && c.Variant != "1" {
				t.Fatalf("empty row changed the document index: %+v", c)
			}
		}
	}
}

func TestUnreadAndFailedCommentsNeverClaimEmptyStates(t *testing.T) {
	for _, wire := range []string{"", "comments-diagnostic\t\tread\tCannot read comments"} {
		m := commentFixture("main-empty")
		m.Panel.Comments = wire
		frame, _, _ := viewWithState(m.Panel, Viewport{Cols: 120, Rows: 100}, renderState{})
		if strings.Contains(frame, domain.CommentsEmptyLocal) || strings.Contains(frame, domain.CommentsEmptyShared) {
			t.Fatalf("unread or failed comments claimed empty:\n%s", frame)
		}
		if wire != "" && !strings.Contains(frame, "Cannot read comments") {
			t.Fatal("comments diagnostic was lost")
		}
	}
	m := commentFixture("main-empty")
	m.Panel.CommentsError = "Cannot read comments"
	frame, _, _ := viewWithState(m.Panel, Viewport{Cols: 120, Rows: 100}, renderState{})
	if strings.Contains(frame, domain.CommentsEmptyLocal) || strings.Contains(frame, domain.CommentsEmptyShared) || !strings.Contains(frame, m.Panel.CommentsError) {
		t.Fatalf("failed query did not preserve its error:\n%s", frame)
	}
}

func TestRepositorySharedFollowsWalkthroughAndUsesReadingControls(t *testing.T) {
	m := commentFixture("pending")
	m.Panel.Comments = "comments-context\tc\treview\trepository\tg\tfeature\ncomments-document\t/repo/.review/comments.md\tc\tshared\tpresent\tr\ncomments-count\t/repo/.review/comments.md\t1"
	positions := map[domain.ControlID]int{}
	for i, c := range ControlsFor(m.Panel) {
		positions[c.ID] = i
	}
	if !(positions["walkthroughBuild"] < positions["openComments"] && positions["openComments"] < positions["compareReview"]) {
		t.Fatalf("comment controls do not follow the footer order: %v", positions)
	}
	for _, id := range []domain.ControlID{"addComment", "deleteComments", "renumberComments"} {
		if _, found := positions[id]; found {
			t.Fatalf("repository Shared exposes %s", id)
		}
	}
	frame, _, _ := viewWithState(m.Panel, Viewport{Cols: 120, Rows: 80}, renderState{})
	if !(strings.Index(frame, "Walkthrough") < strings.Index(frame, "Comments") && strings.Index(frame, "Comments") < strings.Index(frame, "Compare")) {
		t.Fatalf("comments section is out of order:\n%s", frame)
	}
}
func TestSoleCliDestinationSkipsSelectorAndSubmits(t *testing.T) {
	for _, kind := range []string{"local", "shared"} {
		m := commentModel()
		m.Panel.Readonly = true
		m.Panel.Comments = "comments-guard\tstep1\ncomments-capability\tadd\t" + kind
		m.commentsForm = nil
		m, _ = m.beginAddComment()
		f := m.commentsForm
		if f == nil || f.Destination != kind {
			t.Fatalf("sole destination not selected: %+v", f)
		}
		if strings.Contains(f.render(Viewport{Cols: 80, Rows: 24}), domain.CommentsDestinationLabel+":") {
			t.Fatal("sole destination selector visible")
		}
		f.Focus = 8
		m, _ = m.handleCommentsKey(tea.KeyMsg{Type: tea.KeyTab})
		if f.Focus != 1 {
			t.Fatal("Tab focuses hidden destination")
		}
		f.Text.SetValue("Comparison note")
		m, cmd := m.submitComment()
		if cmd == nil || !m.lock.Busy() {
			t.Fatal("sole destination did not submit")
		}
	}
}

func TestCommentComposerWaitsForCompletePanelReport(t *testing.T) {
	m := commentModel()
	m.commentsForm = nil
	m.Panel.CommentsLoading = true
	waiting, cmd := m.beginAddComment()
	if waiting.commentsForm != nil || cmd != nil {
		t.Fatal("pending report opened the composer")
	}
	m.Panel.CommentsLoading = false
	m.Panel.CommentsError = "Read failed"
	failed, cmd := m.beginAddComment()
	if failed.commentsForm != nil || cmd != nil {
		t.Fatal("failed report opened the composer")
	}
	m.Panel.CommentsError = ""
	ready, _ := m.beginAddComment()
	if ready.commentsForm == nil || ready.commentsForm.Guard != "step1" {
		t.Fatal("complete report did not open a guarded composer")
	}
}

func TestCommentsContextPickerShowsDetailsAndKeepsOpaqueIdentity(t *testing.T) {
	m := commentModel()
	m.Panel.Comments = "comments-capability\tadd\tlocal\ncomments-capability\tadd\tshared\ncomments-guard\tg\ncomments-identity\tambiguous\tChoose\ncomments-candidate\tc1\tfeature\tReview 1 · shared: 2\ncomments-candidate\tc2\tfeature\tReview 2 · shared: 1"
	m, _ = m.beginAddComment()
	if m.selectOverlay == nil || len(m.selectOverlay.Items) != 3 {
		t.Fatal("missing context choices")
	}
	first, second := m.selectOverlay.Items[1], m.selectOverlay.Items[2]
	if m.selectOverlay.Notice != domain.CommentsContextHint || m.selectOverlay.Items[0].Detail != domain.CommentsNewContextDetail {
		t.Fatal("context picker must explain that Shared is kept and previous Local stays separate")
	}
	if first.Label != "Continue: feature" || first.Detail != domain.CommentsContinueContextDetail+" Review 1 · shared: 2" || second.Detail != domain.CommentsContinueContextDetail+" Review 2 · shared: 1" {
		t.Fatalf("indistinguishable choices: %+v", m.selectOverlay.Items)
	}
	result := m.selectOverlay.OnPick(second.Value)
	if result.commentForm == nil || result.commentForm.ContextChoice != "c2" {
		t.Fatal("display detail replaced context identity")
	}
	m.Panel.Comments = strings.ReplaceAll(m.Panel.Comments, "comments-capability\tadd\tshared\n", "")
	m, _ = m.beginAddComment()
	if m.selectOverlay.Notice != domain.CommentsLocalContextHint || strings.Contains(m.selectOverlay.Notice, "Shared") {
		t.Fatal("Local-only comparisons must not claim that Shared is available")
	}
}
func TestCommentsRepaintPreservesFormAndIndependentDiagnostic(t *testing.T) {
	m := commentModel()
	m.commentsForm.Text.SetValue("Keep this draft")
	m.commentsForm.Destination = "shared"
	next, _ := m.Update(readDoneMsg{generation: m.readGeneration, result: host.ReadResult{Situation: domain.SituationReview, CommentsError: "Comments unreadable"}})
	m = next.(Model)
	if m.commentsForm == nil || m.commentsForm.Text.Value() != "Keep this draft" || m.commentsForm.Destination != "shared" {
		t.Fatal("repaint lost draft")
	}
	if m.Panel.Situation != domain.SituationReview || m.Panel.CommentsError != "Comments unreadable" {
		t.Fatalf("comments replaced primary state: %+v", m.Panel)
	}
}
func TestCommentsEnterIsMultilineAndDoesNotNavigate(t *testing.T) {
	m := commentModel()
	m.commentsForm.Text.SetValue("first")
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	m = next.(Model)
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("second")})
	m = next.(Model)
	if !strings.Contains(m.commentsForm.Text.Value(), "\n") || !strings.Contains(m.commentsForm.Text.Value(), "second") {
		t.Fatal(m.commentsForm.Text.Value())
	}
	if m.lock.Busy() || m.Panel.Branch != "review/feature" {
		t.Fatal("typing triggered a mutation")
	}
}
func TestCommentsDestinationIsExplicitForEveryCapture(t *testing.T) {
	for _, kind := range []string{"local", "shared", "local"} {
		m := commentModel()
		if m.commentsForm.Destination != "" {
			t.Fatal("retained destination")
		}
		m.commentsForm.Text.SetValue("body")
		if m.commentsForm.valid() {
			t.Fatal("accepted no destination")
		}
		m.commentsForm.Destination = kind
		if !m.commentsForm.valid() {
			t.Fatal("rejected chosen destination")
		}
	}
}
func TestCommentsCancelAndWhitespaceNeverSpawn(t *testing.T) {
	m := commentModel()
	m.commentsForm.Destination = "local"
	m.commentsForm.Text.SetValue(" \n\t")
	m, cmd := m.submitComment()
	if cmd != nil || m.lock.Busy() {
		t.Fatal("whitespace spawned")
	}
	m, cmd = m.handleCommentsKey(tea.KeyMsg{Type: tea.KeyEsc})
	if m.commentsForm != nil || cmd != nil {
		t.Fatal("cancel did not stop")
	}
}
func TestCommentsStaleStepKeepsFormText(t *testing.T) {
	m := commentModel()
	m.commentsForm.Text.SetValue("keep this")
	m.commentsForm.Destination = "shared"
	m.Panel.Comments = "comments-guard\tstep2"
	m, cmd := m.submitComment()
	if cmd != nil || m.commentsForm.Text.Value() != "keep this" || m.commentsForm.Error != domain.StaleNotice {
		t.Fatal("stale form lost its text")
	}
}
func TestCommentsBusyDiscardKeepsFormUsable(t *testing.T) {
	m := commentModel()
	m.commentsForm.Text.SetValue("keep this")
	m.commentsForm.Destination = "local"
	m.lock.Begin()
	m, _ = m.submitComment()
	if m.commentsForm.Busy {
		t.Fatal("discarded submit left form disabled")
	}
}
func TestCommentsFailureKeepsTextAndDestination(t *testing.T) {
	m := commentModel()
	m.commentsForm.Text.SetValue("keep this")
	m.commentsForm.Destination = "shared"
	m.commentsForm.Busy = true
	m.lock.Begin()
	m, _ = m.handleMutationDone(mutationDoneMsg{action: "addComment", result: host.Result{ExitCode: 4}})
	if m.commentsForm == nil || m.commentsForm.Text.Value() != "keep this" || m.commentsForm.Destination != "shared" || m.commentsForm.Busy || m.commentsForm.Error != domain.StaleNotice {
		t.Fatal("failed submit did not retain the form")
	}
}
func TestCommentsSaveHasAccessibleKeyboardAlternative(t *testing.T) {
	m := commentModel()
	m.commentsForm.Text.SetValue("body")
	m.commentsForm.Destination = "local"
	m.commentsForm.Focus = 5
	m, _ = m.handleCommentsKey(tea.KeyMsg{Type: tea.KeyTab})
	if m.commentsForm.Focus != 6 {
		t.Fatal("Save not reachable by Tab")
	}
	m, cmd := m.handleCommentsKey(tea.KeyMsg{Type: tea.KeyEnter})
	if cmd == nil || !m.lock.Busy() {
		t.Fatal("Save did not dispatch")
	}
}
