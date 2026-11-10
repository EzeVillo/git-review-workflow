package ui

import (
	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	tea "github.com/charmbracelet/bubbletea"
	"strings"
	"testing"
)

func TestCommentsBrowserShowsFullProseAndScrollsBeforeOpening(t *testing.T) {
	m := NewModel()
	m.Viewport = Viewport{Cols: 80, Rows: 24}
	m, _ = m.handleCommentsQuery(commentsQueryDone{entries: true, result: host.Result{Stdout: "comment-entry\t1\t7\t1\tFile\ncomment-scope\t1\tgeneral\t\ncomment-body\t1\tFirst paragraph\ncomment-body\t1\t\ncomment-body\t1\tLast paragraph"}})
	if m.commentsBrowser == nil || m.selectOverlay != nil || !strings.Contains(m.View(), "First paragraph\n\nLast paragraph") {
		t.Fatal(m.View())
	}
	m, _ = m.handleCommentsBrowserKey(tea.KeyMsg{Type: tea.KeyPgDown})
	if m.commentsBrowser.Offset == 0 {
		t.Fatal("detail cannot scroll")
	}
}

func TestCommentsBrowserRendersUntrustedCommentsAndDiffAsText(t *testing.T) {
	const terminalCommands = "\x1b[H\x1b]52;c;YXVkaXQ=\x07\u009c"
	m := NewModel()
	m.Viewport = Viewport{Cols: 120, Rows: 40}
	m, _ = m.handleCommentsQuery(commentsQueryDone{entries: true, result: host.Result{
		Stdout: "comment-entry\t1\t1\t1\tHeading " + terminalCommands +
			"\ncomment-scope\t1\tgeneral\t\ncomment-body\t1\tBefore " + terminalCommands + "after",
	}})
	view := m.View()
	if !strings.Contains(view, "Heading") || !strings.Contains(view, "Before after") {
		t.Fatalf("lost the comment text: %q", view)
	}
	if strings.ContainsAny(view, "\x1b\x07\u009c") {
		t.Fatalf("emitted terminal controls from comments: %q", view)
	}
	m.commentsDiff = m.commentsBrowser
	m.commentsBrowser = nil
	m.commentsDiff.ShowingDiff = true
	m.commentsDiff.Diff = "+changed " + terminalCommands + "line"
	view = m.View()
	if !strings.Contains(view, "+changed line") || strings.ContainsAny(view, "\x1b\x07\u009c") {
		t.Fatalf("historical diff was not rendered as text: %q", view)
	}
	m.commentsDiff = nil
	m, _ = m.handleCommentsQuery(commentsQueryDone{result: host.Result{Stdout: "+prepared " + terminalCommands + "line"}})
	view = m.View()
	if !strings.Contains(view, "+prepared line") || strings.ContainsAny(view, "\x1b\x07\u009c") {
		t.Fatalf("delivery comparison was not rendered as text: %q", view)
	}
}

func TestCommentsDiffClosesBrowserAndReturnsDirectlyToPanel(t *testing.T) {
	m := NewModel()
	m.Viewport = Viewport{Cols: 80, Rows: 24}
	entry := domain.CommentPresentation{Ordinal: 2, Label: "2. file.go", Body: "Selected observation", Preview: "Selected observation"}
	m.commentsBrowser = &CommentsBrowser{Entries: []domain.CommentPresentation{{Ordinal: 1, Body: "Other observation"}, entry}, Cursor: 1, Busy: true}
	m, _ = m.handleCommentsQuery(commentsQueryDone{result: host.Result{Stdout: "historical diff"}})
	if m.commentsBrowser != nil || m.commentsDiff == nil {
		t.Fatal("opening a diff must replace the browser")
	}
	if !strings.Contains(m.View(), "historical diff") || strings.Contains(m.View(), "Other observation") {
		t.Fatal(m.View())
	}
	m, _ = m.handleCommentsBrowserKey(tea.KeyMsg{Type: tea.KeyTab})
	if !strings.Contains(m.View(), entry.Body) || m.commentsBrowser != nil {
		t.Fatal("the selected prose must remain readable without reopening the browser")
	}
	m, _ = m.handleCommentsBrowserKey(tea.KeyMsg{Type: tea.KeyEnter})
	if !strings.Contains(m.View(), "historical diff") {
		t.Fatal(m.View())
	}
	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyEsc})
	m = updated.(Model)
	if m.commentsBrowser != nil || m.commentsDiff != nil {
		t.Fatal("closing a diff must return directly to the panel")
	}
}

func TestCommentsDiffFailureKeepsBrowserSelectionForRetry(t *testing.T) {
	for _, exit := range []int{1, 4} {
		m := NewModel()
		m.commentsBrowser = &CommentsBrowser{Entries: []domain.CommentPresentation{{Ordinal: 1}, {Ordinal: 2, Body: "Keep this observation"}}, Cursor: 1, Busy: true}
		m, _ = m.handleCommentsQuery(commentsQueryDone{result: host.Result{ExitCode: exit, Stderr: "Cannot open historical diff"}})
		if m.commentsDiff != nil || m.commentsBrowser == nil || m.commentsBrowser.Busy || m.commentsBrowser.Cursor != 1 {
			t.Fatal("a failed diff must keep the selected comment available for retry")
		}
		want := "Cannot open historical diff"
		if exit == 4 {
			want = domain.StaleNotice
		}
		if m.commentsBrowser.Error != want || m.commentsBrowser.Entries[1].Body != "Keep this observation" {
			t.Fatalf("unexpected browser after failure: %+v", m.commentsBrowser)
		}
	}
}
func TestCommentMarkerUsesOldCounterForRemovedLines(t *testing.T) {
	patch := "@@ -10,2 +20,2 @@\n-old\n+new\n same"
	rendered := markCommentLines(patch, domain.CommentPresentation{Side: "base", First: 10, Last: 10})
	if !strings.Contains(rendered, "> -old\n  +new") {
		t.Fatal(rendered)
	}
	rendered = markCommentLines(patch, domain.CommentPresentation{Side: "head", First: 20, Last: 20})
	if !strings.Contains(rendered, "  -old\n> +new") {
		t.Fatal(rendered)
	}
}
func TestResultCommentsOfferDelete(t *testing.T) {
	controls := commentsControls(domain.PanelModel{Comments: "comments-context\tc\treview\tresult\tg\tFinished\ncomments-document\t/tmp/local.md\tc\tlocal\tpresent\tr"})
	for _, c := range controls {
		if c.ID == "deleteComments" && c.Enabled {
			return
		}
	}
	t.Fatal("retained result has no Delete control")
}

func TestCommentsBrowserKeepsHistoryCollapsedAndScrollsLongProse(t *testing.T) {
	m := NewModel()
	m.Viewport = Viewport{Cols: 80, Rows: 24}
	m.commentsBrowser = &CommentsBrowser{Entries: []domain.CommentPresentation{{Ordinal: 1, Label: "1. file.go:3–7 · New version", Location: "file.go:3–7 · New version", Version: "Original changes · abcdef12 → 123456ab", Warning: domain.CommentsOriginalUnversioned, Body: strings.Repeat("Full paragraph\n", 40) + "Last paragraph", Preview: "Full paragraph…"}}}
	view := m.View()
	if strings.Contains(view, "abcdef12") || !strings.Contains(view, "unsaved changes") || strings.Count(view, "file.go:3–7") != 1 {
		t.Fatal(view)
	}
	m, _ = m.handleCommentsBrowserKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'d'}})
	if !strings.Contains(m.View(), "abcdef12") {
		t.Fatal(m.View())
	}
	for i := 0; i < 10; i++ {
		m, _ = m.handleCommentsBrowserKey(tea.KeyMsg{Type: tea.KeyPgDown})
	}
	if !strings.Contains(m.View(), "Last paragraph") {
		t.Fatal(m.View())
	}
}

func TestGeneralCommentsCannotOpenDiff(t *testing.T) {
	m := NewModel()
	m.Viewport = Viewport{Cols: 80, Rows: 24}
	m.commentsBrowser = &CommentsBrowser{Entries: []domain.CommentPresentation{{Ordinal: 1, Body: "General note"}}}
	next, cmd := m.handleCommentsBrowserKey(tea.KeyMsg{Type: tea.KeyEnter})
	if cmd != nil || next.commentsBrowser.Busy || strings.Contains(next.View(), "Enter diff") {
		t.Fatal("general comment offered a diff")
	}
}

func TestIndividualDeletionConfirmsAndReloadsWithoutRenumbering(t *testing.T) {
	m := NewModel()
	report := domain.ParseComments("comments-context\tc\treview\tactive\tg\tCurrent\ncomments-document\t/local.md\tc\tlocal\tpresent\tr")
	doc := report.Documents()[0]
	m, _ = m.handleCommentsQuery(commentsQueryDone{entries: true, document: doc, report: report, result: host.Result{Stdout: "comments-document\t/local.md\tc\tlocal\tpresent\tr\ncomment-entry\t1\t7\t1\tFirst\ncomment-entry\t2\t7\t3\tRemove\ncomment-entry\t3\t42\t5\tLast"}})
	m.commentsBrowser.Cursor = 1
	m, cmd := m.handleCommentsBrowserKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'x'}})
	if cmd != nil || m.confirm == nil || m.confirm.ID != "deleteCommentEntry" {
		t.Fatal("deletion must confirm before spawning")
	}
	want := "delete --document local --context c --expect-context g --expect-document r --entry 2"
	if got := strings.Join(m.confirm.Pending.argv.Args, " "); got != want {
		t.Fatalf("argv = %q", got)
	}
	cancelled, cmd := m.handleConfirmKey(tea.KeyMsg{Type: tea.KeyEsc})
	m = cancelled.(Model)
	if cmd != nil || len(m.commentsBrowser.Entries) != 3 || m.commentsBrowser.Cursor != 1 {
		t.Fatal("cancel changed browser")
	}
	m, _ = m.handleCommentsBrowserKey(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'x'}})
	confirmed, cmd := m.handleConfirmKey(tea.KeyMsg{Type: tea.KeyEnter})
	m = confirmed.(Model)
	if cmd == nil || !m.commentsBrowser.Busy {
		t.Fatal("confirmed deletion did not start")
	}
	m, cmd = m.handleMutationDone(mutationDoneMsg{action: "deleteCommentEntry", result: host.Result{ExitCode: 0}})
	if cmd == nil || !m.commentsBrowser.Busy {
		t.Fatal("successful deletion must reload entries")
	}
	m, _ = m.handleCommentsQuery(commentsQueryDone{entries: true, document: doc, report: report, result: host.Result{Stdout: "comments-document\t/local.md\tc\tlocal\tpresent\tr2\ncomment-entry\t1\t7\t1\tFirst\ncomment-entry\t2\t42\t3\tLast"}})
	b := m.commentsBrowser
	if b == nil || b.Busy || b.Cursor != 1 || b.Entries[1].Label != "42. Last · Location unavailable" || b.Report.Documents()[0].Revision != "r2" {
		t.Fatalf("unexpected reload: %+v", b)
	}
	m, _ = m.handleCommentsQuery(commentsQueryDone{entries: true, document: doc, report: report, result: host.Result{Stdout: "comments-document\t/local.md\tc\tlocal\tpresent\tr3"}})
	if m.commentsBrowser == nil || len(m.commentsBrowser.Entries) != 0 {
		t.Fatal("deleting last entry closed browser")
	}
	for _, key := range []tea.KeyType{tea.KeyUp, tea.KeyDown, tea.KeyEnter} {
		m, _ = m.handleCommentsBrowserKey(tea.KeyMsg{Type: key})
	}
}

func TestFailedIndividualDeletionRetainsSelectionAndProse(t *testing.T) {
	m := NewModel()
	m.commentsBrowser = &CommentsBrowser{Entries: []domain.CommentPresentation{{Ordinal: 1, Body: "Keep"}}, Busy: true}
	m, _ = m.handleMutationDone(mutationDoneMsg{action: "deleteCommentEntry", result: host.Result{ExitCode: 4}})
	if m.commentsBrowser.Busy || m.commentsBrowser.Error != domain.StaleNotice || m.commentsBrowser.Entries[0].Body != "Keep" {
		t.Fatalf("%+v", m.commentsBrowser)
	}
}
