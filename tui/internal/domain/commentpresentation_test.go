package domain

import "testing"
import "strings"

func TestCommentPresentationKeepsOriginalSideAndSingleLayerEscapes(t *testing.T) {
	report := ParseComments("comment-entry\t2\t7\t4\tFile\ncomment-scope\t2\tselection\tbase\ncomment-path\t2\tbase\told%25name\ncomment-location\t2\tbase\t3\t5\ncomment-body\t2\t    100%25 and %2509\ncomment-body\t2\t\ncomment-body\t2\tSecond%09paragraph")
	view := PresentComment(report, report.Records("comment-entry")[0])
	if !view.CanOpenDiff || view.Body != "    100% and %09\n\nSecond\tparagraph" || view.Location != "old%name:3–5 · Previous version" || view.Ordinal != 2 || view.Label != "7. File · old%name:3–5 · Previous version" {
		t.Fatalf("%+v", view)
	}
}

func TestRetainedCommentUsesItsContextGuardBesideAnActiveReview(t *testing.T) {
	report := ParseComments("comments-guard\tactive\ncomments-context\tc\treview\tresult\tretained\tOld\ncomments-document\t/local.md\tc\tlocal\tpresent\tr")
	args, err := CommentsArgv(report, "diff", "local", "c", 1)
	if err != nil || !strings.Contains(strings.Join(args, " "), "--expect-context retained") {
		t.Fatalf("%v: %v", args, err)
	}
}

func TestLongCommentPreviewPreservesUnicodeAndUnsavedWarning(t *testing.T) {
	body := strings.Repeat("🙂", 161)
	report := ParseComments("comment-entry\t1\t1\t1\tsrc/file.go\ncomment-scope\t1\tselection\thead\ncomment-path\t1\thead\tsrc/file.go\ncomment-location\t1\thead\t3\t7\ncomment-version\t1\tabcdef123456\t123456abcdef\ncomment-unversioned\t1\ncomment-body\t1\t" + body)
	view := PresentComment(report, report.Records("comment-entry")[0])
	if view.Body != body || view.Preview != strings.Repeat("🙂", 159)+"…" || view.Label != "1. src/file.go:3–7 · New version" || view.Version != "Original changes · abcdef12 → 123456ab" || view.Warning != CommentsOriginalUnversioned {
		t.Fatalf("%+v", view)
	}
}

func TestGeneralAndUnlocatedCommentsHaveNoDiff(t *testing.T) {
	report := ParseComments("comment-entry\t1\t7\t1\tGeneral\ncomment-scope\t1\tgeneral\t\ncomment-version\t1\taaaa\tbbbb\ncomment-entry\t2\t8\t4\tManual")
	for _, entry := range report.Records("comment-entry") {
		if PresentComment(report, entry).CanOpenDiff {
			t.Fatal("invented a file for general or manual entry")
		}
	}
}
