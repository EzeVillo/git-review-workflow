package host

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

// sandboxWithOrigin builds the same shape tests/step.bats does: a bare
// "origin" plus a working checkout with `develop` pushed and a two-commit
// `feature/x` pushed on top, reviewworkflow.base already configured. The
// remote is a local filesystem path — no real network involved — so `git
// review start`'s Network class never actually reaches out anywhere.
func sandboxWithOrigin(t *testing.T) (work string) {
	t.Helper()
	useRealDispatcher(t)

	tmp := t.TempDir()
	home := filepath.Join(tmp, "home")
	if err := os.MkdirAll(home, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", home)
	t.Setenv("USERPROFILE", home)

	runGit(t, tmp, "config", "--global", "user.email", "t@example.com")
	runGit(t, tmp, "config", "--global", "user.name", "tester")
	runGit(t, tmp, "config", "--global", "init.defaultBranch", "develop")

	origin := filepath.Join(tmp, "origin.git")
	work = filepath.Join(tmp, "work")
	runGit(t, tmp, "init", "--quiet", "--bare", origin)
	runGit(t, tmp, "init", "--quiet", work)
	runGit(t, work, "remote", "add", "origin", origin)
	runGit(t, work, "config", "reviewworkflow.base", "develop")

	if err := os.WriteFile(filepath.Join(work, "a.txt"), []byte("a1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, work, "add", "a.txt")
	runGit(t, work, "commit", "--quiet", "-m", "base")
	runGit(t, work, "branch", "-M", "develop")
	runGit(t, work, "push", "--quiet", "-u", "origin", "develop")

	runGit(t, work, "switch", "--quiet", "-c", "feature/x")
	if err := os.WriteFile(filepath.Join(work, "a.txt"), []byte("a1\na2\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, work, "add", "a.txt")
	runGit(t, work, "commit", "--quiet", "-m", "touch-a")
	runGit(t, work, "push", "--quiet", "-u", "origin", "feature/x")

	return work
}

func TestReadStateNoReviewInvokesListAndConfig(t *testing.T) {
	work := sandboxWithOrigin(t)
	runGit(t, work, "switch", "--quiet", "develop")
	t.Chdir(work) // ReadState's exec spawns use the PROCESS's cwd, not a param

	ResetInvocationLogForTest()
	result := ReadState(context.Background(), work, domain.MinCLIVersion)
	if result.Situation != domain.SituationNoReview {
		t.Fatalf("Situation = %q, want no-review (stderr=%q)", result.Situation, result.Stderr)
	}
	if !result.HasList {
		t.Error("expected list --porcelain to have run for no-review")
	}
	if !result.HasConfig {
		t.Error("expected config --porcelain to have run for no-review")
	}
	sawList, sawConfig := false, false
	for _, e := range InvocationLog() {
		if len(e.Argv) >= 3 && e.Argv[0] == "git" && e.Argv[1] == "review" {
			switch e.Argv[2] {
			case "list":
				sawList = true
			case "config":
				sawConfig = true
			}
		}
	}
	if !sawList || !sawConfig {
		t.Fatalf("invocation log missing list/config calls: %+v", InvocationLog())
	}
}

// T043's central gate: inside an active review, list/config are never
// invoked at all — the footer's registers simply do not arrive, because
// nobody asked for them.
func TestReadStateReviewNeverInvokesListOrConfig(t *testing.T) {
	work := sandboxWithOrigin(t)
	runGit(t, work, "switch", "--quiet", "feature/x")
	t.Chdir(work)
	if res := InvokeReview(context.Background(), "start", nil); res.ExitCode != 0 {
		t.Fatalf("git review start failed: exit=%d stderr=%s", res.ExitCode, res.Stderr)
	}

	ResetInvocationLogForTest()
	result := ReadState(context.Background(), work, domain.MinCLIVersion)
	if result.Situation != domain.SituationReview {
		t.Fatalf("Situation = %q, want review (stderr=%q)", result.Situation, result.Stderr)
	}
	if !result.HasStatus {
		t.Fatal("expected a parsed status record for an active review")
	}
	if result.HasList || result.HasConfig {
		t.Fatalf("a review must never read list/config: HasList=%v HasConfig=%v", result.HasList, result.HasConfig)
	}
	for _, e := range InvocationLog() {
		if len(e.Argv) >= 3 && e.Argv[0] == "git" && e.Argv[1] == "review" && (e.Argv[2] == "list" || e.Argv[2] == "config") {
			t.Fatalf("review situation invoked %v, which must never happen inside a review", e.Argv)
		}
	}
}

// TestReadWhyStates is T094's own gate at the host layer: readWhy tells
// apart an entry with nothing to say (WhyAbsent — `status --why` exits 0
// with empty stdout, the walkthrough never annotates a.txt) from one it
// could not even ask about (WhyFailed — the invocation itself cannot
// succeed at all). The old bool HasWhy collapsed both into the same false,
// which is exactly why no golden fixture built before this task exercises
// WhyFailed and none of them can regress from this split.
func TestReadWhyStates(t *testing.T) {
	work := sandboxWithOrigin(t)
	runGit(t, work, "switch", "--quiet", "feature/x")
	// A walkthrough that COVERS a.txt but leaves its why body empty: `status
	// --why` only answers at all once a walkthrough is in effect (bin/
	// git-review-verbs/status refuses --why otherwise, with its own error —
	// a genuinely different failure this test does not need), and an empty
	// body is what actually exercises WhyAbsent (exit 0, empty stdout)
	// rather than that unrelated refusal.
	if err := os.MkdirAll(filepath.Join(work, ".review"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(work, ".review", "walkthrough.md"), []byte("# Walkthrough\n\n## 1. a.txt\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, work, "add", ".review/walkthrough.md")
	runGit(t, work, "commit", "--quiet", "-m", "walkthrough")
	runGit(t, work, "push", "--quiet", "origin", "feature/x")

	t.Chdir(work)
	if res := InvokeReview(context.Background(), "start", nil); res.ExitCode != 0 {
		t.Fatalf("git review start failed: exit=%d stderr=%s", res.ExitCode, res.Stderr)
	}

	if _, state := readWhy(context.Background(), "a.txt"); state != domain.WhyAbsent {
		t.Fatalf("readWhy(a walkthrough entry with an empty why body) state = %q, want absent", state)
	}

	dir := t.TempDir()
	t.Chdir(dir) // outside any repository: the invocation itself cannot succeed
	if _, state := readWhy(context.Background(), "a.txt"); state != domain.WhyFailed {
		t.Fatalf("readWhy(outside a repository) state = %q, want failed", state)
	}
}

func TestReadStateOutsideARepositoryIsError(t *testing.T) {
	useRealDispatcher(t)
	dir := t.TempDir()
	t.Chdir(dir)
	result := ReadState(context.Background(), dir, domain.MinCLIVersion)
	if result.Situation != domain.SituationForMissingRepo() {
		t.Fatalf("Situation = %q, want %q", result.Situation, domain.SituationForMissingRepo())
	}
	// T100: the panel's own actionable copy (per_client_strings.
	// no_single_root.tui) lands in Stderr, never git rev-parse's raw "fatal:
	// not a git repository..." -- that raw text would not tell a reader what
	// to do, and the panel must never be a blank error screen.
	if result.Stderr != domain.NoSingleRoot {
		t.Fatalf("Stderr = %q, want the no_single_root copy %q", result.Stderr, domain.NoSingleRoot)
	}
}
