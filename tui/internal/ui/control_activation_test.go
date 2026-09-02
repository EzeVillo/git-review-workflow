package ui

import (
	"encoding/base64"
	"reflect"
	"runtime"
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
)

func TestShowWhyInvokesStatusWhyForTheRawPathAndDisplaysItsResult(t *testing.T) {
	host.ResetInvocationLogForTest()
	raw := `src/\303\261o with space.go`
	m := Model{Panel: domain.PanelModel{
		Situation:   domain.SituationReview,
		Mode:        domain.ModeWalk,
		Branch:      "review/feat-x",
		Source:      "feat-x",
		Tip:         "abc1234",
		CurrentPath: domain.PathRef{Raw: raw, Display: "src/año with space.go"},
		WhyState:    domain.WhyPresent,
	}}

	after, cmd := m.activateControl("showWhy", raw)
	if cmd == nil {
		t.Fatal("showWhy must schedule the normal review invoker")
	}
	message := cmd()
	msg, ok := message.(textActionDoneMsg)
	if !ok {
		t.Fatalf("showWhy command returned %T, want textActionDoneMsg", message)
	}
	updated, _ := after.Update(msg)
	got := updated.(Model)
	if got.textOverlay == nil {
		t.Fatal("the status --why result must open the text overlay")
	}
	if got.textOverlay.Title != "Why this entry" {
		t.Fatalf("overlay title = %q, want Why this entry", got.textOverlay.Title)
	}

	entries := host.InvocationLog()
	if len(entries) != 1 {
		t.Fatalf("showWhy ran %d review invocations, want exactly 1", len(entries))
	}
	want := []string{"git", "review", "status", "--why", raw}
	if !reflect.DeepEqual(entries[0].Argv, want) {
		t.Fatalf("showWhy argv = %#v, want %#v", entries[0].Argv, want)
	}
}

func TestPaletteShowWhyUsesTheCurrentRawPath(t *testing.T) {
	host.ResetInvocationLogForTest()
	raw := `src/\303\261o.go`
	m := Model{Panel: domain.PanelModel{
		Situation:   domain.SituationReview,
		Mode:        domain.ModeWalk,
		Branch:      "review/feat-x",
		Source:      "feat-x",
		Tip:         "abc1234",
		CurrentPath: domain.PathRef{Raw: raw, Display: "src/año.go"},
	}}
	_, cmd := m.activatePaletteAction("showWhy")
	if cmd == nil {
		t.Fatal("the showWhy palette action must keep the current raw path")
	}
	_ = cmd()
	entries := host.InvocationLog()
	if len(entries) != 1 || !reflect.DeepEqual(entries[0].Argv, []string{"git", "review", "status", "--why", raw}) {
		t.Fatalf("palette showWhy invocations = %#v, want one status --why for %q", entries, raw)
	}
}

func TestOutOfRangeHelpDisplaysTheCLIRecoveryTextOrAFallback(t *testing.T) {
	withDiagnostic := Model{Panel: domain.PanelModel{
		Situation: domain.SituationOutOfRange,
		Stderr:    "Run git review abort, then start again.\n",
	}}
	after, cmd := withDiagnostic.activateControl("outOfRangeHelp", "")
	if cmd != nil {
		t.Fatal("native help must open immediately, without invoking a command")
	}
	if after.textOverlay == nil || after.textOverlay.Body != "Run git review abort, then start again." {
		t.Fatalf("diagnostic help = %#v, want the trimmed CLI recovery text", after.textOverlay)
	}

	fallback, _ := (Model{Panel: domain.PanelModel{Situation: domain.SituationError}}).activateControl("outOfRangeHelp", "")
	if fallback.textOverlay == nil || !strings.Contains(fallback.textOverlay.Body, "git review status") {
		t.Fatalf("empty diagnostic help = %#v, want a useful recovery fallback", fallback.textOverlay)
	}
}

func TestStartFromDraftUsesTheFreshRawSourceAndRecordedIntent(t *testing.T) {
	raw := `feature/\303\261o`
	panel := domain.PanelModel{
		Situation: domain.SituationNoReview,
		FreshDraftRows: domain.FooterField(
			raw,
			"C:/gitdir/review-walkthrough/feature-ñ.md",
			"offline",
			"delta",
			"4",
			"4",
		),
	}
	m := Model{Panel: panel}
	after, cmd := m.activateControl("startFromDraft", raw)
	if cmd == nil {
		t.Fatal("a complete fresh draft must start through the mutation lock")
	}
	if after.confirm != nil {
		t.Fatal("startFromDraft must not open a confirmation")
	}
	if !after.lock.Busy() {
		t.Fatal("startFromDraft must acquire the mutation lock before dispatch")
	}

	got := startFromDraftRequest(draftRowView{src: raw, source: "offline", rrange: "delta"})
	if got.action != "startFromDraft" || got.argv == nil || got.argv.Verb != "start" {
		t.Fatalf("start request = %+v, want a startFromDraft git review start request", got)
	}
	want := []string{"--delta", "--offline", "--", raw}
	if !reflect.DeepEqual(got.argv.Args, want) {
		t.Fatalf("startFromDraft args = %#v, want %#v", got.argv.Args, want)
	}
}

func TestReportedEditorPathsResolveRawRowsAndNeverDerivePaths(t *testing.T) {
	rawDraft := `feature/\303\261o`
	panel := domain.PanelModel{
		Situation:         domain.SituationNoReview,
		FreshDraftRows:    domain.FooterField(rawDraft, "C:/gitdir/drafts/feature-ñ.md", "remote", "full", "1", "1"),
		SpentDraftRows:    domain.FooterField("spent", "C:/gitdir/drafts/spent.md", "local", "delta", "1", "1"),
		HasWalkthroughRow: true,
		WalkthroughState:  domain.WalkthroughStale,
		HasGuideRows:      true,
		TeamGuideRow:      "C:/repo/.review/team guide.md",
		TeamGuideState:    domain.GuideInForce,
		OwnGuideRow:       "C:/gitdir/own guide.md",
		OwnGuideState:     domain.GuideEmpty,
	}
	m := Model{Panel: panel, lastRead: host.ReadResult{
		HasConfig: true,
		Config: domain.ConfigPorcelainResult{Walkthrough: &domain.WalkthroughRecord{
			Path:  "C:/repo/.review/walkthrough.md",
			State: domain.WalkthroughStale,
		}},
	}}
	cases := []struct {
		id, variant, want string
	}{
		{"openDraft", rawDraft, "C:/gitdir/drafts/feature-ñ.md"},
		{"openDraft", "spent", "C:/gitdir/drafts/spent.md"},
		{"openWalkthrough", "", "C:/repo/.review/walkthrough.md"},
		{"openGuide", "team", "C:/repo/.review/team guide.md"},
		{"openGuide", "own", "C:/gitdir/own guide.md"},
	}
	for _, tc := range cases {
		t.Run(tc.id+"/"+tc.variant, func(t *testing.T) {
			got, ok := m.reportedEditorPath(domain.ControlID(tc.id), tc.variant)
			if !ok || got != tc.want {
				t.Fatalf("reportedEditorPath(%s, %q) = %q, %v; want %q, true", tc.id, tc.variant, got, ok, tc.want)
			}
		})
	}
	if _, ok := m.reportedEditorPath("openDraft", "not-a-current-row"); ok {
		t.Fatal("an unknown raw draft identifier must not open a derived path")
	}
}

func TestOpenReportedFileControlsDelegateToTheConfiguredEditor(t *testing.T) {
	editor := "true"
	if runtime.GOOS == "windows" {
		editor = "cmd"
	}
	t.Setenv("EDITOR", editor)
	panel := domain.PanelModel{
		Situation:         domain.SituationNoReview,
		FreshDraftRows:    domain.FooterField("feature", "C:/gitdir/draft.md", "remote", "full", "1", "1"),
		HasWalkthroughRow: true,
		WalkthroughState:  domain.WalkthroughInSync,
		HasGuideRows:      true,
		TeamGuideRow:      "C:/repo/.review/guide.md",
		TeamGuideState:    domain.GuideInForce,
	}
	m := Model{Panel: panel, lastRead: host.ReadResult{
		HasConfig: true,
		Config: domain.ConfigPorcelainResult{Walkthrough: &domain.WalkthroughRecord{
			Path:  "C:/repo/.review/walkthrough.md",
			State: domain.WalkthroughInSync,
		}},
	}}
	for _, tc := range []struct{ id, variant string }{
		{"openDraft", "feature"},
		{"openWalkthrough", ""},
		{"openGuide", "team"},
	} {
		t.Run(tc.id, func(t *testing.T) {
			_, cmd := m.activateControl(domain.ControlID(tc.id), tc.variant)
			if cmd == nil {
				t.Fatalf("%s must hand the reported path to the configured editor", tc.id)
			}
		})
	}
}

func TestOpenWithoutEditorReportsTheFailureInTheCurrentFrame(t *testing.T) {
	t.Setenv("EDITOR", "")
	m := Model{
		Viewport: Viewport{Cols: 80, Rows: 24},
		Panel: domain.PanelModel{
			Situation:         domain.SituationNoReview,
			HasWalkthroughRow: true,
			WalkthroughState:  domain.WalkthroughInSync,
		},
		lastRead: host.ReadResult{HasConfig: true, Config: domain.ConfigPorcelainResult{
			Walkthrough: &domain.WalkthroughRecord{Path: "C:/repo/.review/walkthrough.md", State: domain.WalkthroughInSync},
		}},
	}
	after, cmd := m.activateControl("openWalkthrough", "")
	if cmd != nil {
		t.Fatal("missing editor must not dispatch a child")
	}
	if !strings.Contains(after.View(), "No editor is configured: set $EDITOR and try again.") {
		t.Fatalf("missing-editor feedback is not visible:\n%s", after.View())
	}
}

func TestCopyWalkthroughPromptWritesTheDocumentedPointerWithTheHonestAcknowledgement(t *testing.T) {
	var wire string
	restore := host.SetOSC52WriterForTest(func(s string) { wire = s })
	defer restore()
	path := "C:/repo/.review/walkthrough.md"
	m := Model{Panel: domain.PanelModel{
		Situation:         domain.SituationNoReview,
		HasWalkthroughRow: true,
		WalkthroughState:  domain.WalkthroughInSync,
	}, lastRead: host.ReadResult{
		HasConfig: true,
		Config: domain.ConfigPorcelainResult{Walkthrough: &domain.WalkthroughRecord{
			Path:  path,
			State: domain.WalkthroughInSync,
		}},
	}}

	after, cmd := m.activateControl("copyWalkthroughPrompt", "")
	if cmd != nil {
		t.Fatal("copyWalkthroughPrompt must use OSC 52 directly, not spawn a process")
	}
	if after.statusLine != copiedNothingToConfirm {
		t.Fatalf("copy acknowledgement = %q, want the existing honest acknowledgement", after.statusLine)
	}
	payload := strings.TrimSuffix(strings.TrimPrefix(wire, "\x1b]52;c;"), "\x07")
	decoded, err := base64.StdEncoding.DecodeString(payload)
	if err != nil {
		t.Fatalf("OSC 52 payload %q is not base64: %v", payload, err)
	}
	want := "Update the reading order at " + path + ". The instructions are inside the file, in the comment at the top. Entries that already have a number and a why are finished: leave them as they are, and fill in only the ones marked \"## ?.\"."
	if string(decoded) != want {
		t.Fatalf("walkthrough clipboard text = %q, want %q", decoded, want)
	}
}

func TestExternalLinkControlsUseOnlyTheirDocumentedURLs(t *testing.T) {
	cases := []struct {
		id, variant, want string
	}{
		{"installCli", "", "https://github.com/EzeVillo/git-review-workflow#readme"},
		{"openSupport", "star", domain.SupportStarURL},
		{"openSupport", "bug", domain.SupportBugURL},
	}
	for _, tc := range cases {
		t.Run(tc.id+"/"+tc.variant, func(t *testing.T) {
			got, ok := externalURLForControl(domain.ControlID(tc.id), tc.variant)
			if !ok || got != tc.want {
				t.Fatalf("externalURLForControl(%s, %q) = %q, %v; want %q, true", tc.id, tc.variant, got, ok, tc.want)
			}
		})
	}
	if _, ok := externalURLForControl("openSupport", "not-allowlisted"); ok {
		t.Fatal("an unknown support variant must not launch an arbitrary URL")
	}
}

func TestExternalLinkControlsDispatchTheNativeBrowserOpener(t *testing.T) {
	for _, tc := range []struct {
		id      domain.ControlID
		variant string
		panel   domain.PanelModel
	}{
		{"installCli", "", domain.PanelModel{Situation: domain.SituationCliMissing}},
		{"openSupport", "star", domain.PanelModel{Situation: domain.SituationNoReview}},
		{"openSupport", "bug", domain.PanelModel{Situation: domain.SituationNoReview}},
	} {
		t.Run(string(tc.id)+"/"+tc.variant, func(t *testing.T) {
			_, cmd := (Model{Panel: tc.panel}).activateControl(tc.id, tc.variant)
			if cmd == nil {
				t.Fatalf("%s/%s must delegate to the platform browser opener", tc.id, tc.variant)
			}
		})
	}
}
