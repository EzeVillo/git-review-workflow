package ui

import (
	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"strings"
	"testing"
)

func TestCommentsFormAcceptsOptionalColumnEndpoints(t *testing.T) {
	f := newCommentsForm("g", "file", []string{"local", "shared"})
	f.Destination, f.Scope = "local", "selection"
	f.Text.SetValue("fragment")
	for _, pair := range [][2]string{{"1", "2"}, {"1:2", "1:4"}, {"1:2", "2:1"}} {
		f.Start.SetValue(pair[0])
		f.End.SetValue(pair[1])
		if !f.valid() {
			t.Fatalf("valid endpoints rejected: %v", pair)
		}
	}
	for _, pair := range [][2]string{{"1:2", "2"}, {"1", "2:2"}, {"1:2", "1:2"}, {"1:4", "1:2"}, {"1:0", "2:1"}, {"1:2:3", "2:1"}} {
		f.Start.SetValue(pair[0])
		f.End.SetValue(pair[1])
		if f.valid() {
			t.Fatalf("invalid endpoints accepted: %v", pair)
		}
	}
}

func TestCommentCaretsUseUTF16ColumnsOnOriginalSide(t *testing.T) {
	report := domain.ParseComments("comment-entry\t1\t1\t1\tfile\ncomment-scope\t1\tselection\thead\ncomment-path\t1\thead\tfile\ncomment-location\t1\thead\t1\t1\ncomment-columns\t1\thead\t2\t4")
	entry := domain.PresentComment(report, report.Records("comment-entry")[0])
	if entry.Location != "file:1:2–1:4 · New version" {
		t.Fatal(entry.Location)
	}
	marker, ok := commentColumnMarker("a😀\tZ", 1, entry, "> 1 | ")
	if !ok || marker != "       ^^" {
		t.Fatalf("wrong emoji highlight %q (%v)", marker, ok)
	}
	entry.StartColumn, entry.EndColumn = 4, 5
	marker, ok = commentColumnMarker("a😀\tZ", 1, entry, "> 1 | ")
	if !ok || marker != strings.Repeat(" ", 9)+strings.Repeat("^", 7) {
		t.Fatalf("wrong tab highlight %q (%v)", marker, ok)
	}
	entry.StartColumn, entry.EndColumn = 2, 4
	patch := "@@ -1 +1 @@\n-old\n+a😀\tZ"
	marked := markCommentLines(patch, entry)
	if !strings.Contains(marked, "  -old\n> +a😀\tZ\n    ^^") {
		t.Fatal(marked)
	}
	entry.Last, entry.EndColumn = 2, 1
	if commentContainsLine(entry, 2) {
		t.Fatal("exclusive endpoint marked the next line")
	}
}
