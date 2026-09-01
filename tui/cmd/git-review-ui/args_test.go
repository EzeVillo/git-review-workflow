package main

import (
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

func TestNoArgumentsRunsTheTUI(t *testing.T) {
	if got := parseArgs(nil); got.Outcome != argsRun {
		t.Fatalf("parseArgs(nil).Outcome = %v, want argsRun", got.Outcome)
	}
	if got := parseArgs([]string{}); got.Outcome != argsRun {
		t.Fatalf("parseArgs([]).Outcome = %v, want argsRun", got.Outcome)
	}
}

func TestVersionPrintsExactlyTheStampedVersion(t *testing.T) {
	for _, flag := range []string{"-V", "--version"} {
		got := parseArgs([]string{flag})
		if got.Outcome != argsPrint {
			t.Errorf("parseArgs(%q).Outcome = %v, want argsPrint", flag, got.Outcome)
		}
		// Exactly the version and nothing else: the release workflow greps
		// TUIVersion out of version.go, and a bug report pastes this.
		if got.Text != domain.TUIVersion {
			t.Errorf("parseArgs(%q).Text = %q, want %q", flag, got.Text, domain.TUIVersion)
		}
	}
}

func TestHelpPrintsUsageNamingBothFlags(t *testing.T) {
	for _, flag := range []string{"-h", "--h", "--help"} {
		got := parseArgs([]string{flag})
		if got.Outcome != argsPrint {
			t.Errorf("parseArgs(%q).Outcome = %v, want argsPrint", flag, got.Outcome)
		}
		for _, want := range []string{"usage:", "--version", "--help"} {
			if !strings.Contains(got.Text, want) {
				t.Errorf("parseArgs(%q) usage does not mention %q", flag, want)
			}
		}
	}
}

// The whole point of args.go: an argument this binary does not know is
// REFUSED on stderr, never swallowed into a silent startup. `git review ui`
// passes everything through unchanged, so a typo lands here.
func TestUnknownArgumentsAreRefusedAndNameThemselves(t *testing.T) {
	for _, argv := range [][]string{
		{"--setp"},
		{"start"},
		{"-h", "-V"},
		{"--version", "extra"},
		{""},
	} {
		got := parseArgs(argv)
		if got.Outcome != argsReject {
			t.Errorf("parseArgs(%q).Outcome = %v, want argsReject", argv, got.Outcome)
		}
		if !strings.Contains(got.Text, "git-review-ui -h") {
			t.Errorf("parseArgs(%q) refusal does not point at -h: %q", argv, got.Text)
		}
	}
}

// A refusal has to name what it refused, or the reviewer cannot see the
// typo they made.
func TestRefusalQuotesTheOffendingArgument(t *testing.T) {
	got := parseArgs([]string{"--setp"})
	if !strings.Contains(got.Text, "--setp") {
		t.Errorf("refusal %q does not quote the argument it refused", got.Text)
	}
}
