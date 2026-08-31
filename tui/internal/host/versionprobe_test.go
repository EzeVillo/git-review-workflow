package host

import (
	"context"
	"os"
	"path/filepath"
	"testing"

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
	outcome, res := ProbeVersion(context.Background())
	if outcome.TimedOut || outcome.SpawnOrExitFailed {
		t.Fatalf("expected a clean version read, got outcome=%+v res=%+v", outcome, res)
	}
	if outcome.Version == "" {
		t.Fatal("expected a non-empty version string")
	}
	situation, ok := domain.SituationFromVersionProbe(outcome, domain.MinCLIVersion)
	if !ok {
		t.Fatalf("real dispatcher's version must clear this client's own floor, got situation=%q", situation)
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

func TestProbeVersionSpawnFailureIsCliMissing(t *testing.T) {
	// A PATH with nothing named "git" on it: the spawn itself fails.
	t.Setenv("PATH", t.TempDir())
	outcome, _ := ProbeVersion(context.Background())
	if !outcome.SpawnOrExitFailed {
		t.Fatal("expected SpawnOrExitFailed with no git on PATH")
	}
	situation, ok := domain.SituationFromVersionProbe(outcome, domain.MinCLIVersion)
	if ok || situation != domain.SituationCliMissing {
		t.Fatalf("situation = %q ok=%v, want cli-missing", situation, ok)
	}
}
