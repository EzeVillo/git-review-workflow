package host

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

func TestRealInvokerTeamCommentsAcrossMergeStrategies(t *testing.T) {
	source, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", filepath.Join(source, "bin")+string(os.PathListSeparator)+os.Getenv("PATH"))
	for _, strategy := range []string{"ff", "merge", "squash"} {
		t.Run(strategy, func(t *testing.T) {
			root := t.TempDir()
			history := func(phase string) {
				cmd := exec.Command("sh", filepath.Join(source, "tests/helpers/comments-team-history.sh"), phase, root, strategy)
				if output, err := cmd.CombinedOutput(); err != nil {
					t.Fatalf("%s: %v\n%s", phase, err, output)
				}
			}
			history("init")
			t.Chdir(filepath.Join(root, "reviewer"))
			review := func(verb string, args ...string) string {
				result := InvokeReview(context.Background(), verb, args)
				if result.ExitCode != 0 || result.SpawnFailed || result.TimedOut {
					t.Fatalf("%s %v: %+v", verb, args, result)
				}
				return result.Stdout
			}
			report := func() domain.CommentsReport { return domain.ParseComments(review("comments", "status", "--porcelain")) }
			add := func(kind, text string) {
				args, err := domain.CommentsArgv(report(), "add", kind, "", 0)
				if err != nil {
					t.Fatal(err)
				}
				result := InvokeReviewWithInput(context.Background(), "comments", append(args, "--stdin"), text)
				if result.ExitCode != 0 {
					t.Fatalf("add: %+v", result)
				}
			}
			shared := func() domain.CommentDocument {
				for _, doc := range report().Documents() {
					if doc.Kind == "shared" {
						return doc
					}
				}
				t.Fatal("Shared document missing")
				return domain.CommentDocument{}
			}
			read := func(path string) string {
				bytes, err := os.ReadFile(path)
				if err != nil {
					t.Fatal(err)
				}
				return string(bytes)
			}
			review("start", "--no-walk", "feature/team")
			add("local", "Private reviewer sentinel")
			add("shared", "Reviewer question")
			original := shared().Context
			review("finish")
			if strings.Contains(read(".review/comments.md"), "Private reviewer sentinel") {
				t.Fatal("Local prose delivered")
			}
			history("publish")
			review("clean", "feature/team")
			review("start", "--no-walk", "feature/team")
			review("comments", "init", "--document", "shared")
			doc := shared()
			if doc.Context != original || !strings.Contains(read(doc.Path), "Author response") {
				t.Fatal("Branch prose or identity lost")
			}
			conflict := false
			for _, row := range report().Records("comments-diagnostic") {
				if row[1] == "source-conflict" {
					conflict = true
				}
			}
			if conflict || !strings.Contains(read(".review/comments.md"), "Author response") {
				t.Fatal("An obsolete private copy overrode the author reply")
			}
			if err := os.WriteFile(doc.Path, []byte(read(".review/comments.md")), 0600); err != nil {
				t.Fatal(err)
			}
			review("finish")
			for _, row := range report().Records("comments-diagnostic") {
				if row[1] == "source-conflict" {
					t.Fatal("Resolved conflict persisted after Finish")
				}
			}
			history("merge")
			for _, branch := range []string{"before-merge", "after-merge"} {
				review("start", "--no-walk", branch)
				if rows := report().Records("comments-identity"); len(rows) != 1 || rows[0][0] != "fresh" {
					t.Fatalf("identity: %v", rows)
				}
				add("shared", "Independent question")
				doc = shared()
				if doc.Context == original || !strings.Contains(read(doc.Path), "Independent question") || strings.Contains(read(doc.Path), "Author response") {
					t.Fatal("Inherited comments contaminated a new review")
				}
				review("abort")
			}
		})
	}
}
