package host

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

// repoBinDir prepends the monorepo's real bin/ (the actual git-review
// dispatcher) onto PATH, so ProbeVersion exercises the real thing instead of
// a fixture — the CLI's own reported version is what this probe has to
// compare against domain.MinCLIVersion correctly.
func useRealDispatcher(t *testing.T) {
	t.Helper()
	root, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(root, "bin")
	if _, err := os.Stat(filepath.Join(bin, "git-review")); err != nil {
		t.Skipf("real dispatcher not found at %s: %v", bin, err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
}

func TestProbeVersionAgainstRealDispatcher(t *testing.T) {
	useRealDispatcher(t)
	ResetInvocationLogForTest()
	outcome, res := ProbeVersion(context.Background())
	if outcome.TimedOut || outcome.ExecutableNotFound || outcome.Failed {
		t.Fatalf("expected a clean version read, got outcome=%+v res=%+v", outcome, res)
	}
	if outcome.Version == "" {
		t.Fatal("expected a non-empty version string")
	}
	situation, ok := domain.SituationFromVersionProbe(outcome, domain.MinCLIVersion)
	if !ok {
		t.Fatalf("real dispatcher's version must clear this client's own floor, got situation=%q", situation)
	}
	entries := InvocationLog()
	if len(entries) != 1 || len(entries[0].Argv) < 3 || entries[0].Argv[1] != "review" || entries[0].Argv[2] != "--version" {
		t.Fatalf("version probe must retain central InvokeReview logging, got %+v", entries)
	}
}

// contracts/cli-invocation.md § Probe de versión: a timeout is NEVER
// cli-missing — it is reported as an error that says the probe was slow, not
// as an absent CLI that would send the user to reinstall something that is
// already there.
func TestProbeVersionTimeoutIsNeverCliMissing(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 0)
	defer cancel()
	outcome, _ := ProbeVersion(ctx)
	if !outcome.TimedOut {
		t.Fatal("expected TimedOut for an already-expired context")
	}
	situation, ok := domain.SituationFromVersionProbe(outcome, domain.MinCLIVersion)
	if ok {
		t.Fatal("a timeout must be terminal (ok=false), not fall through to status")
	}
	if situation == domain.SituationCliMissing {
		t.Fatal("a timeout must never be reported as cli-missing")
	}
	if situation != domain.SituationError {
		t.Fatalf("situation = %q, want error", situation)
	}
}

func TestProbeVersionExecutableNotFoundIsCliMissing(t *testing.T) {
	// A PATH with nothing named "git" on it: the spawn itself fails.
	t.Setenv("PATH", t.TempDir())
	outcome, _ := ProbeVersion(context.Background())
	if !outcome.ExecutableNotFound || outcome.Failed {
		t.Fatalf("expected only executable-not-found evidence with no git on PATH, got %+v", outcome)
	}
	situation, ok := domain.SituationFromVersionProbe(outcome, domain.MinCLIVersion)
	if ok || situation != domain.SituationCliMissing {
		t.Fatalf("situation = %q ok=%v, want cli-missing", situation, ok)
	}
}

func TestVersionResultClassificationRequiresUnequivocalMissingEvidence(t *testing.T) {
	cases := []struct {
		name      string
		result    Result
		want      domain.VersionProbeOutcome
		wantRetry bool
	}{
		{
			name:   "spawn executable not found",
			result: Result{SpawnFailed: true, ExecutableNotFound: true},
			want:   domain.VersionProbeOutcome{ExecutableNotFound: true},
		},
		{
			name:   "git reports missing review subcommand",
			result: Result{ExitCode: 1, Stderr: "git: 'review' is not a git command. See 'git --help'."},
			want:   domain.VersionProbeOutcome{ExecutableNotFound: true},
		},
		{
			name:      "generic spawn failure",
			result:    Result{SpawnFailed: true},
			want:      domain.VersionProbeOutcome{Failed: true},
			wantRetry: true,
		},
		{
			name:      "general exit error",
			result:    Result{ExitCode: 128, Stderr: "fatal: corrupt configuration"},
			want:      domain.VersionProbeOutcome{Failed: true},
			wantRetry: true,
		},
		{
			name:      "timeout",
			result:    Result{TimedOut: true},
			want:      domain.VersionProbeOutcome{TimedOut: true},
			wantRetry: true,
		},
		{
			name:   "blank successful stdout",
			result: Result{ExitCode: 0, Stdout: "  \r\n"},
			want:   domain.VersionProbeOutcome{Version: ""},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, retry := classifyVersionResult(tc.result)
			if got != tc.want || retry != tc.wantRetry {
				t.Fatalf("classifyVersionResult(%+v) = (%+v, %v), want (%+v, %v)", tc.result, got, retry, tc.want, tc.wantRetry)
			}
		})
	}
}

func TestProbeVersionRetriesTransientFailuresTwiceBeforePublishing(t *testing.T) {
	results := []Result{
		{SpawnFailed: true},
		{TimedOut: true},
		{Stdout: "9.9.9\n"},
	}
	attempts := 0
	waits := 0
	invoke := func(context.Context, string, []string) Result {
		result := results[attempts]
		attempts++
		return result
	}
	wait := func(context.Context, time.Duration) bool {
		waits++
		return true
	}

	outcome, result := probeVersionWith(context.Background(), invoke, wait)
	if attempts != 3 || waits != 2 {
		t.Fatalf("attempts=%d waits=%d, want 3 attempts and 2 retry waits", attempts, waits)
	}
	if outcome != (domain.VersionProbeOutcome{Version: "9.9.9"}) || result.Stdout != "9.9.9\n" {
		t.Fatalf("settled result = outcome %+v result %+v, want third successful attempt", outcome, result)
	}
}

func TestProbeVersionDoesNotRetryUnequivocalMissingEvidence(t *testing.T) {
	attempts := 0
	invoke := func(context.Context, string, []string) Result {
		attempts++
		return Result{SpawnFailed: true, ExecutableNotFound: true}
	}
	wait := func(context.Context, time.Duration) bool {
		t.Fatal("missing evidence must publish immediately, without waiting")
		return false
	}

	outcome, _ := probeVersionWith(context.Background(), invoke, wait)
	if attempts != 1 || !outcome.ExecutableNotFound {
		t.Fatalf("attempts=%d outcome=%+v, want one immediate missing verdict", attempts, outcome)
	}
}

func TestProbeVersionPublishesErrorAfterTwoFailedRetries(t *testing.T) {
	attempts := 0
	invoke := func(context.Context, string, []string) Result {
		attempts++
		return Result{ExitCode: 1, Stderr: "fatal: transient host error"}
	}
	wait := func(context.Context, time.Duration) bool { return true }

	outcome, _ := probeVersionWith(context.Background(), invoke, wait)
	if attempts != 3 || !outcome.Failed || outcome.ExecutableNotFound {
		t.Fatalf("attempts=%d outcome=%+v, want general error after exactly two retries", attempts, outcome)
	}
}
