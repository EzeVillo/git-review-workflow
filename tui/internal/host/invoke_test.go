package host

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRunProcessReportsSpawnFailedForAMissingBinary(t *testing.T) {
	res := runProcess(context.Background(), "definitely-not-a-real-binary-xyz", nil, nil)
	if !res.SpawnFailed {
		t.Fatalf("expected SpawnFailed for a binary that does not exist, got %+v", res)
	}
	if res.TimedOut {
		t.Fatal("a missing binary is not a timeout")
	}
}

// A timeout must never be reported as SpawnFailed (contracts/cli-
// invocation.md § Timeouts: "un timeout no es una CLI ausente"). An
// already-expired context exercises the exact same classification code path
// as a process killed mid-flight (ctx.Err() reports DeadlineExceeded either
// way), without needing a real slow subprocess or any OS-specific shell.
func TestInvokeReviewReportsTimedOutNotSpawnFailed(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 0)
	defer cancel()
	res := InvokeReview(ctx, "status", []string{"--porcelain"})
	if !res.TimedOut {
		t.Fatalf("expected TimedOut for an already-expired context, got %+v", res)
	}
	if res.SpawnFailed {
		t.Fatal("a timeout must not also report SpawnFailed")
	}
}

func TestInvokeSupportGitReportsTimedOutNotSpawnFailed(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 0)
	defer cancel()
	res := InvokeSupportGit(ctx, []string{"rev-parse", "--git-dir"})
	if !res.TimedOut {
		t.Fatalf("expected TimedOut, got %+v", res)
	}
}

// FR-007: the only command InvokeReview/InvokeSupportGit ever spawn is
// "git" — never the dispatcher, never anything configurable.
func TestOnlyCommandIsGit(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 0)
	defer cancel()
	for _, res := range []Result{
		InvokeReview(ctx, "status", []string{"--porcelain"}),
		InvokeSupportGit(ctx, []string{"rev-parse", "--git-dir"}),
	} {
		if len(res.Argv) == 0 || res.Argv[0] != "git" {
			t.Fatalf("Argv[0] = %v, want \"git\"", res.Argv)
		}
	}
}

func TestInvokeReviewPrependsReviewVerb(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 0)
	defer cancel()
	res := InvokeReview(ctx, "status", []string{"--porcelain"})
	want := []string{"git", "review", "status", "--porcelain"}
	if strings.Join(res.Argv, " ") != strings.Join(want, " ") {
		t.Fatalf("Argv = %v, want %v", res.Argv, want)
	}
}

func TestInvocationLogRecordsStartAndEnd(t *testing.T) {
	ResetInvocationLogForTest()
	ctx, cancel := context.WithTimeout(context.Background(), 0)
	defer cancel()
	InvokeReview(ctx, "status", []string{"--porcelain"})
	entries := InvocationLog()
	if len(entries) != 1 {
		t.Fatalf("expected 1 log entry, got %d", len(entries))
	}
	if !entries[0].TimedOut {
		t.Fatal("the logged entry must record the timeout")
	}
}

// FR-078: the invocation log lives in memory only. This asserts the actual
// filesystem effect (nothing new appears under a scratch working directory)
// rather than trusting that no code path happens to call os.Create.
func TestInvocationLogWritesNoFiles(t *testing.T) {
	dir := t.TempDir()
	before, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	oldWd, _ := os.Getwd()
	if err := os.Chdir(dir); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(oldWd)

	ctx, cancel := context.WithTimeout(context.Background(), 0)
	defer cancel()
	InvokeReview(ctx, "status", []string{"--porcelain"})
	InvokeSupportGit(ctx, []string{"rev-parse", "--git-dir"})

	after, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(after) != len(before) {
		t.Fatalf("invoking left files behind in cwd: before=%v after=%v", before, after)
	}
}

// FR-009: GIT_REVIEW_ADVICE is exported from exactly one file in the whole
// module — this one. Every other .go file (production or test) is swept for
// the literal string.
func TestGitReviewAdviceExportedNowhereElse(t *testing.T) {
	root, err := filepath.Abs("../..")
	if err != nil {
		t.Fatal(err)
	}
	var offenders []string
	err = filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		if !strings.HasSuffix(path, ".go") {
			return nil
		}
		rel, _ := filepath.Rel(root, path)
		rel = filepath.ToSlash(rel)
		// invoke.go is where the rule allows it; invoke_test.go is this very
		// test naming the rule it enforces, in its own doc comment.
		if rel == "internal/host/invoke.go" || rel == "internal/host/invoke_test.go" {
			return nil
		}
		b, rerr := os.ReadFile(path)
		if rerr != nil {
			return rerr
		}
		if strings.Contains(string(b), "GIT_REVIEW_ADVICE") {
			offenders = append(offenders, rel)
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walking %s: %v", root, err)
	}
	if len(offenders) != 0 {
		t.Fatalf("GIT_REVIEW_ADVICE referenced outside internal/host/invoke.go: %v", offenders)
	}
}
