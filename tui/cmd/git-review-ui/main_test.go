package main

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
)

// TestMain intercepts the askpass sentinel BEFORE the testing framework
// prints anything at all: if the process was launched with the sentinel
// set, it calls the real main() (which exits the process itself) instead of
// running any test. TestAskpassSentinelExitsNonZeroSilently below re-execs
// this very test binary with the sentinel set, so the child process takes
// this exact path.
func TestMain(m *testing.M) {
	if host.IsAskpassSentinel() {
		main()
		// main() always calls os.Exit when the sentinel is set; unreachable.
		return
	}
	os.Exit(m.Run())
}

// T041's gate: invoking the program with the askpass sentinel exits
// non-zero, prints nothing on stdout or stderr, and — because main() never
// reaches tea.NewProgram(...).Run() on this path — never touches the
// terminal (no alt-screen, no cursor hide, no raw mode).
func TestAskpassSentinelExitsNonZeroSilently(t *testing.T) {
	exe, err := os.Executable()
	if err != nil {
		t.Fatalf("os.Executable: %v", err)
	}
	cmd := exec.Command(exe)
	cmd.Env = append(os.Environ(), host.AskpassSentinelEnv+"=1")
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err = cmd.Run()

	if err == nil {
		t.Fatal("expected the askpass sentinel to make the process exit non-zero")
	}
	if exitErr, ok := err.(*exec.ExitError); !ok {
		t.Fatalf("expected an ExitError, got %T: %v", err, err)
	} else if exitErr.ExitCode() == 0 {
		t.Fatal("expected a non-zero exit code")
	}
	if stdout.Len() != 0 {
		t.Fatalf("expected empty stdout, got %q", stdout.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("expected empty stderr, got %q", stderr.String())
	}
}

// T044's gate: no verb under bin/ knows the word "reviewui" — the TUI's own
// config namespace is not read by the CLI (FR-077), and the CLI does not
// write it either.
func TestNoBinVerbMentionsReviewUI(t *testing.T) {
	root, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	binDir := filepath.Join(root, "bin")
	if _, err := os.Stat(binDir); err != nil {
		t.Skipf("bin/ not found at %s: %v", binDir, err)
	}
	var offenders []string
	err = filepath.Walk(binDir, func(path string, info os.FileInfo, werr error) error {
		if werr != nil {
			return werr
		}
		if info.IsDir() {
			return nil
		}
		b, rerr := os.ReadFile(path)
		if rerr != nil {
			return rerr
		}
		if strings.Contains(string(b), "reviewui") {
			rel, _ := filepath.Rel(root, path)
			offenders = append(offenders, rel)
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walking %s: %v", binDir, err)
	}
	if len(offenders) != 0 {
		t.Fatalf("bin/ files mention \"reviewui\", which must stay a TUI-only namespace: %v", offenders)
	}
}

func TestWatcherDefaultsToFsnotify(t *testing.T) {
	t.Setenv("GIT_REVIEW_UI_WATCH", "")
	if got := watcherKindFromEnv(); got != watcherFsnotify {
		t.Fatalf("watcherKindFromEnv() = %v, want fsnotify by default", got)
	}
}

func TestWatcherNopRequiresExplicitOptOut(t *testing.T) {
	t.Setenv("GIT_REVIEW_UI_WATCH", "0")
	if got := watcherKindFromEnv(); got != watcherNop {
		t.Fatalf("watcherKindFromEnv() = %v, want nop for the explicit deterministic opt-out", got)
	}
}

type rebuildCall struct {
	gitDir       string
	gitCommonDir string
	draftPaths   []string
}

type recordingWatcher struct {
	rebuilds []rebuildCall
}

func (*recordingWatcher) Start(context.Context, string, string, []string) (<-chan struct{}, error) {
	return make(chan struct{}), nil
}

func (w *recordingWatcher) Rebuild(gitDir, gitCommonDir string, draftPaths []string) error {
	w.rebuilds = append(w.rebuilds, rebuildCall{
		gitDir:       gitDir,
		gitCommonDir: gitCommonDir,
		draftPaths:   append([]string(nil), draftPaths...),
	})
	return nil
}

func (*recordingWatcher) Stop() error { return nil }

func TestAcceptedReadsRebuildWatcherWithLaterPorcelainDraftPaths(t *testing.T) {
	w := &recordingWatcher{}
	dirs := host.GitDirs{GitDir: "repo/git-dir", GitCommonDir: "repo/git-common-dir"}

	if err := rebuildWatcher(w, dirs, host.ReadResult{Situation: domain.SituationNoReview}); err != nil {
		t.Fatal(err)
	}
	later := host.ReadResult{
		Situation: domain.SituationReview,
		HasStatus: true,
		Status:    domain.PorcelainResult{DraftPath: "drafts/from-status.md"},
		HasConfig: true,
		Config: domain.ConfigPorcelainResult{Drafts: []domain.DraftRecord{
			{Path: "drafts/from-config-a.md"},
			{Path: ""},
			{Path: "drafts/from-config-b.md"},
		}},
	}
	if err := rebuildWatcher(w, dirs, later); err != nil {
		t.Fatal(err)
	}

	if len(w.rebuilds) != 2 {
		t.Fatalf("Rebuild calls = %d, want one for every accepted read", len(w.rebuilds))
	}
	first := w.rebuilds[0]
	if first.gitDir != dirs.GitDir || first.gitCommonDir != dirs.GitCommonDir || len(first.draftPaths) != 0 {
		t.Fatalf("first Rebuild = %+v, want git roots and no draft paths", first)
	}
	wantLater := []string{"drafts/from-status.md", "drafts/from-config-a.md", "drafts/from-config-b.md"}
	if got := w.rebuilds[1]; got.gitDir != dirs.GitDir || got.gitCommonDir != dirs.GitCommonDir || !reflect.DeepEqual(got.draftPaths, wantLater) {
		t.Fatalf("later Rebuild = %+v, want roots and porcelain-only paths %v", got, wantLater)
	}
}
