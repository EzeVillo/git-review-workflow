package host

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"unicode/utf8"
)

func TestRunProcessReportsSpawnFailedForAMissingBinary(t *testing.T) {
	res := runProcess(context.Background(), "definitely-not-a-real-binary-xyz", nil, nil)
	if !res.SpawnFailed {
		t.Fatalf("expected SpawnFailed for a binary that does not exist, got %+v", res)
	}
	if !res.ExecutableNotFound {
		t.Fatalf("expected unequivocal executable-not-found evidence, got %+v", res)
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

func TestInteractiveReviewCmdSharesEnvironmentWorkingDirectoryAndLogging(t *testing.T) {
	t.Setenv("GIT_REVIEW_ADVICE", "1")
	ResetInvocationLogForTest()
	invocation := InteractiveReviewCmd("preview", nil, "/repo")

	if want := []string{"git", "review", "preview"}; !reflect.DeepEqual(invocation.Cmd.Args, want) {
		t.Fatalf("interactive argv = %v, want %v", invocation.Cmd.Args, want)
	}
	if invocation.Cmd.Dir != "/repo" {
		t.Fatalf("interactive cwd = %q, want /repo", invocation.Cmd.Dir)
	}
	var advice string
	for _, entry := range invocation.Cmd.Env {
		if strings.HasPrefix(entry, "GIT_REVIEW_ADVICE=") {
			advice = entry
		}
	}
	if advice != "GIT_REVIEW_ADVICE=0" {
		t.Fatalf("interactive advice environment = %q, want disabled through central review policy", advice)
	}
	if len(InvocationLog()) != 0 {
		t.Fatal("building an interactive command must not log it before the terminal child completes")
	}

	result := invocation.Complete(nil)
	entries := InvocationLog()
	if result.ExitCode != 0 || len(entries) != 1 {
		t.Fatalf("completion result=%+v entries=%+v, want one successful logged invocation", result, entries)
	}
	if !reflect.DeepEqual(entries[0].Argv, []string{"git", "review", "preview"}) || entries[0].Cwd != "/repo" {
		t.Fatalf("interactive log entry = %+v, want shared argv/cwd policy", entries[0])
	}
}

func TestInteractiveReviewCmdSharesSpawnErrorPolicy(t *testing.T) {
	ResetInvocationLogForTest()
	invocation := InteractiveReviewCmd("preview", nil, "/repo")
	err := &exec.Error{Name: "git", Err: exec.ErrNotFound}
	result := invocation.Complete(err)

	if !result.SpawnFailed || !result.ExecutableNotFound || result.TimedOut {
		t.Fatalf("interactive spawn result = %+v, want the central not-found classification", result)
	}
	entries := InvocationLog()
	if len(entries) != 1 || !entries[0].SpawnFailed {
		t.Fatalf("interactive spawn log = %+v, want one shared-policy failure entry", entries)
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

// --- the invocation log's two bounds -----------------------------------------

// A pane is not a command that exits: left open all day with the watcher
// accelerating a read on every ref change, the log would otherwise grow
// forever. Same bound the other clients already have (Visual Studio's
// CliLogSink is a 500-line ring).
func TestInvocationLogKeepsOnlyTheNewestEntries(t *testing.T) {
	ResetInvocationLogForTest()
	t.Cleanup(ResetInvocationLogForTest)

	total := logMax + 250
	for i := 0; i < total; i++ {
		appendLog(LogEntry{Argv: []string{"git", "review", "status", fmt.Sprint(i)}})
	}

	entries := InvocationLog()
	if len(entries) != logMax {
		t.Fatalf("InvocationLog() has %d entries, want the %d cap", len(entries), logMax)
	}
	// Oldest-first order survives, and the window is the NEWEST slice: what
	// showCliLog exists to answer is always "what did the thing I just
	// pressed run".
	firstKept := total - logMax
	if got := entries[0].Argv[3]; got != fmt.Sprint(firstKept) {
		t.Errorf("oldest kept entry = %q, want %q", got, fmt.Sprint(firstKept))
	}
	if got := entries[len(entries)-1].Argv[3]; got != fmt.Sprint(total-1) {
		t.Errorf("newest entry = %q, want %q", got, fmt.Sprint(total-1))
	}
}

func TestInvocationLogTruncatesLongStderrAtARuneBoundary(t *testing.T) {
	ResetInvocationLogForTest()
	t.Cleanup(ResetInvocationLogForTest)

	// Multi-byte runes chosen so the cap lands mid-sequence: a naive byte
	// slice would leave a broken tail the renderer draws as U+FFFD.
	long := strings.Repeat("é", logStderrMax)
	appendLog(LogEntry{Argv: []string{"git"}, Stderr: long})

	got := InvocationLog()[0].Stderr
	if len(got) >= len(long) {
		t.Fatalf("stderr of %d bytes was not truncated (got %d)", len(long), len(got))
	}
	if !strings.HasSuffix(got, logTruncated) {
		t.Errorf("truncated stderr does not say so: %q", got[max(0, len(got)-40):])
	}
	if !utf8.ValidString(got) {
		t.Error("truncation cut mid-rune: the result is not valid UTF-8")
	}
}

// Short stderr is left exactly as it came: the cap is a bound, not a filter.
func TestInvocationLogKeepsShortStderrVerbatim(t *testing.T) {
	ResetInvocationLogForTest()
	t.Cleanup(ResetInvocationLogForTest)

	const msg = "error: no base configured"
	appendLog(LogEntry{Argv: []string{"git"}, Stderr: msg})
	if got := InvocationLog()[0].Stderr; got != msg {
		t.Errorf("stderr = %q, want it verbatim", got)
	}
}
