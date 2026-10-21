package host

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCommentBlobReadsOriginalObjectAfterWorkingFileChanges(t *testing.T) {
	dir := initRepo(t)
	t.Chdir(dir)
	oid := strings.TrimSpace(runGit(t, dir, "rev-parse", "HEAD:f.txt"))
	if err := os.WriteFile(filepath.Join(dir, "f.txt"), []byte("new working text"), 0o644); err != nil {
		t.Fatal(err)
	}
	result := ReadCommentBlob(context.Background(), oid)
	if result.ExitCode != 0 || result.Stdout != "x" {
		t.Fatalf("%+v", result)
	}
	missing := ReadCommentBlob(context.Background(), strings.Repeat("1", 40))
	if missing.ExitCode == 0 || missing.Stdout != "" {
		t.Fatalf("missing content substituted: %+v", missing)
	}
}
func TestCommentBlobRejectsArgumentsThatAreNotOids(t *testing.T) {
	for _, oid := range []string{"HEAD:f.txt", "--help", strings.Repeat("g", 40), "", strings.Repeat("1", 41)} {
		result := ReadCommentBlob(context.Background(), oid)
		if result.ExitCode != 5 || len(result.Argv) != 0 {
			t.Fatalf("unexpected invocation: %+v", result)
		}
	}
}
