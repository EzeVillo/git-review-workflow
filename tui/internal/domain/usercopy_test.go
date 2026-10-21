package domain

import (
	"regexp"
	"strings"
	"testing"
)

func TestDraftAgentPromptReconstructsTheSharedSentence(t *testing.T) {
	yaml := readCanonicalYAML(t)
	m := regexp.MustCompile(`(?m)^ {2}draft_agent_prompt: >-\n((?: {4}.*\n)+)`).FindStringSubmatch(yaml)
	if m == nil {
		t.Fatal("canonical draft_agent_prompt not found")
	}
	var lines []string
	for _, l := range strings.Split(m[1], "\n") {
		l = strings.TrimSpace(l)
		if l != "" {
			lines = append(lines, l)
		}
	}
	want := strings.Join(lines, " ")
	got := DraftAgentPromptBefore + "{path}" + DraftAgentPromptAfter
	if got != want {
		t.Errorf("reconstructed draft_agent_prompt =\n  %q\nwant\n  %q", got, want)
	}
}

func TestSupportURLsMatchCanonical(t *testing.T) {
	yaml := readCanonicalYAML(t)
	for id, got := range map[string]string{
		"star": SupportStarURL, "bug": SupportBugURL,
		"sponsor": SupportSponsorURL, "contact": SupportContactURL,
	} {
		match := regexp.MustCompile(id + `_url:\s*"([^"]+)"`).FindStringSubmatch(yaml)
		if match == nil {
			t.Fatalf("canonical support.%s_url not found", id)
		}
		if got != match[1] {
			t.Errorf("support %s URL = %q, canonical = %q", id, got, match[1])
		}
	}
}

func TestWaitingTextMatchesCanonical(t *testing.T) {
	yaml := readCanonicalYAML(t)
	if !strings.Contains(yaml, `waiting_text: "`+WaitingText+`"`) {
		t.Errorf("WaitingText %q does not match the canonical's waiting_text", WaitingText)
	}
}

func TestCliOutdatedTitleKeepsTheWordInstalled(t *testing.T) {
	if !strings.Contains(CliOutdatedTitle, "installed") {
		t.Error(`cli_outdated_title must keep the word "installed" (panelHtml.ts ~917)`)
	}
}

// FR-069: this client's after_install copy never promises a poll. FR-032
// forbids doing it; this locks in that the copy does not say it either.
func TestAfterInstallDoesNotPromiseAPoll(t *testing.T) {
	if strings.Contains(strings.ToLower(AfterInstall), "every few seconds") {
		t.Fatal("after_install must not describe polling: FR-069")
	}
}

// A terminal has no window and no multi-root concept: the copy for "no
// single root" should point at the one thing that IS true for a terminal —
// standing outside a repository — not at the other clients' workspace
// language.
func TestNoSingleRootTalksAboutARepositoryNotAWorkspace(t *testing.T) {
	if !strings.Contains(NoSingleRoot, "repository") {
		t.Error("no_single_root.tui should name the actual fix: run from inside a git repository")
	}
}

func TestProgressTextNamesTheOperationWithoutExposingArgv(t *testing.T) {
	cases := []struct {
		action string
		params ActionParams
		want   string
	}{
		{"startReview", ActionParams{Intent: ReviewIntent{Branch: "feature/x"}}, "Starting the review of feature/x…"},
		{"continueReview", ActionParams{Source: "feature/x"}, "Continuing the review of feature/x…"},
		{"createGuide", ActionParams{}, "Creating the authoring guide…"},
	}
	for _, tc := range cases {
		if got := ProgressText(tc.action, tc.params); got != tc.want {
			t.Errorf("ProgressText(%q) = %q, want %q", tc.action, got, tc.want)
		}
	}
}

func TestGuideCreatedNamesTheReportedPath(t *testing.T) {
	if got := GuideCreated("C:/repo/.review/walkthrough-guide.md"); got != "Created C:/repo/.review/walkthrough-guide.md." {
		t.Fatalf("GuideCreated = %q", got)
	}
}

func TestFinishPendingCopySaysEditsJoinTheBranchOnlyWhenCommitted(t *testing.T) {
	const want = "Your edits are staged and ready to commit to {destination}. Commit them before switching branches."
	if FinishPendingLine1 != want {
		t.Fatalf("FinishPendingLine1 = %q, want %q", FinishPendingLine1, want)
	}
}
