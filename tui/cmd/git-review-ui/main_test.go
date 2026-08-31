package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

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
