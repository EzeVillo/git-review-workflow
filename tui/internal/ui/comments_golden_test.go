package ui

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

func commentFixture(name string) Model {
	m := NewModel()
	m.Panel = domain.PanelModel{Situation: domain.SituationReview, Mode: domain.ModeWhole, Branch: "review/feature", Source: "feature"}
	state, kind := "active", "review"
	local, shared := "absent", "absent"
	switch name {
	case "local":
		local = "present"
	case "shared":
		shared = "present"
	case "both", "form":
		local, shared = "present", "present"
	case "pending":
		local, shared, state = "present", "present", "result"
		m.Panel.Situation = domain.SituationNoReview
	case "main-empty":
		state = "result"
		m.Panel.Situation = domain.SituationNoReview
	}
	localRevision, sharedRevision, localCount, sharedCount := "L1", "S1", 2, 1
	if local == "absent" {
		localRevision, localCount = "absent", 0
	}
	if shared == "absent" {
		sharedRevision, sharedCount = "absent", 0
	}
	m.Panel.Comments = fmt.Sprintf("comments-context\tc1\t%s\t%s\tg1\tFeature\ncomments-document\t/local.md\tc1\tlocal\t%s\t%s\ncomments-document\t/shared.md\tc1\tshared\t%s\t%s\ncomments-count\t/local.md\t%d\ncomments-count\t/shared.md\t%d", kind, state, local, localRevision, shared, sharedRevision, localCount, sharedCount)
	if state == "active" {
		m.Panel.Comments += "\ncomments-guard\tg1\ncomments-capability\tadd\tlocal\ncomments-capability\tadd\tshared"
	}
	if name == "pending" {
		m.Panel.Comments += "\ncomments-delivery\tc1\tpending\tDestination changed"
	}
	if name == "ambiguous" {
		m.Panel.Comments += "\ncomments-identity\tambiguous\tChoose a context\ncomments-candidate\tc2\tEarlier review"
		m, _ = m.beginAddComment()
	}
	if name == "form" {
		m.commentsForm = newCommentsForm("g1", "src/file.go", []string{"local", "shared"})
		m.commentsForm.Text.SetValue("First line\nSecond line")
	}
	return m
}

func TestCommentsGoldenFrames(t *testing.T) {
	for _, name := range []string{"local", "shared", "both", "absent", "ambiguous", "pending", "main-empty", "form"} {
		for _, size := range goldenSizes {
			for _, mode := range goldenModes {
				key := name + "-" + size.name + mode.suffix
				t.Run(key, func(t *testing.T) {
					m := commentFixture(name)
					m.Viewport = Viewport{Cols: size.cols, Rows: size.rows, Color: mode.color, ASCII: mode.ascii}
					got := m.View()
					file := filepath.Join(goldenDir(), "comments", key+".txt")
					if shouldUpdateGolden() {
						if err := os.MkdirAll(filepath.Dir(file), 0755); err != nil {
							t.Fatal(err)
						}
						if err := os.WriteFile(file, []byte(got), 0644); err != nil {
							t.Fatal(err)
						}
						return
					}
					want, err := os.ReadFile(file)
					if err != nil {
						t.Fatal(err)
					}
					if string(want) != got {
						t.Fatalf("frame differs from %s\n%s", file, got)
					}
					if name == "form" && !strings.Contains(got, "First line") {
						t.Fatal("comment body is hidden")
					}
				})
			}
		}
	}
}

func TestCommentsBrowserGoldenFrames(t *testing.T) {
	for _, diff := range []bool{false, true} {
		name := "browser"
		if diff {
			name = "historical-lines"
		}
		for _, size := range goldenSizes {
			for _, mode := range goldenModes {
				key := name + "-" + size.name + mode.suffix
				t.Run(key, func(t *testing.T) {
					m := NewModel()
					m.Viewport = Viewport{Cols: size.cols, Rows: size.rows, Color: mode.color, ASCII: mode.ascii}
					m.commentsBrowser = &CommentsBrowser{Entries: []domain.CommentPresentation{
						{Ordinal: 1, Label: "7. sample.go · General comment", Location: "General comment", Preview: "Keep this behavior documented.", Body: "Keep this behavior documented."},
						{CanOpenDiff: true, Ordinal: 2, Label: "7. sample.go:40–41 · Previous version", Location: "sample.go:40–41 · Previous version", Version: "Original changes · aaaaaaaa → bbbbbbbb", Preview: "Can this return before releasing the lock?", Body: "Can this return before releasing the lock?\n\nThe error path needs the same cleanup.\n\n    defer release()\n\nThis paragraph remains readable without opening Markdown."},
					}, Cursor: 1, ShowingDiff: diff, Diff: "> marks the commented lines.\n\n  39 | acquire()\n> 40 | if failed {\n> 41 |     return err\n  42 | }\n\n@@ -40,2 +40,3 @@\n> -if failed {\n> -    return err\n  +defer release()\n  +if failed {\n  +    return err"}
					if diff {
						m.commentsDiff = m.commentsBrowser
						m.commentsBrowser = nil
					}
					got := m.View()
					file := filepath.Join(goldenDir(), "comments", key+".txt")
					if shouldUpdateGolden() {
						if err := os.WriteFile(file, []byte(got), 0o644); err != nil {
							t.Fatal(err)
						}
					}
					expected, err := os.ReadFile(file)
					if err != nil {
						t.Fatal(err)
					}
					if got != string(expected) {
						t.Fatalf("frame differs from %s\n%s", file, got)
					}
				})
			}
		}
	}
}

func TestCommentsRowsAndPrepareHaveIndependentAvailability(t *testing.T) {
	m := commentFixture("local")
	controls := commentsControls(m.Panel)
	open, create := 0, 0
	for _, c := range controls {
		if c.ID == "openComments" {
			open++
		}
		if c.ID == "initComments" {
			create++
		}
	}
	if open != 1 || create != 0 {
		t.Fatalf("expected only the existing Local document: %+v", controls)
	}
	for _, name := range []string{"both", "pending"} {
		m = commentFixture(name)
		prepared := 0
		for _, c := range commentsControls(m.Panel) {
			if c.ID == "prepareSharedComments" {
				prepared++
			}
		}
		if (name == "pending") != (prepared == 1) {
			t.Fatalf("prepare scope for %s: %d", name, prepared)
		}
	}
}
