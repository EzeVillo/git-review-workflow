package host

import (
	"reflect"
	"runtime"
	"testing"
)

func TestSplitShellWords(t *testing.T) {
	cases := []struct {
		in   string
		want []string
	}{
		{"vim", []string{"vim"}},
		{"code -w", []string{"code", "-w"}},
		{"nvim -R", []string{"nvim", "-R"}},
		{`code --wait "path with space"`, []string{"code", "--wait", "path with space"}},
		{`'single quoted arg'`, []string{"single quoted arg"}},
		{`a\ b c`, []string{"a b", "c"}},
		{"  spaced   out  ", []string{"spaced", "out"}},
	}
	for _, c := range cases {
		got, err := splitShellWords(c.in)
		if err != nil {
			t.Fatalf("splitShellWords(%q) error: %v", c.in, err)
		}
		if !reflect.DeepEqual(got, c.want) {
			t.Fatalf("splitShellWords(%q) = %#v, want %#v", c.in, got, c.want)
		}
	}
}

func TestSplitShellWordsUnterminatedQuote(t *testing.T) {
	if _, err := splitShellWords(`"unterminated`); err == nil {
		t.Fatal("expected an error for an unterminated double quote")
	}
	if _, err := splitShellWords(`'unterminated`); err == nil {
		t.Fatal("expected an error for an unterminated single quote")
	}
}

// TestEditorArgvUnsetIsNotOK is the "no editor configured" half of T089's
// gate: an absent (or blank) $EDITOR never falls back to vi/nano — ok is
// simply false, and the caller (OpenInEditorCmd) is the one that turns that
// into a "what did not happen" message.
func TestEditorArgvUnsetIsNotOK(t *testing.T) {
	t.Setenv("EDITOR", "")
	if _, ok := EditorArgv(); ok {
		t.Fatal("EditorArgv with EDITOR unset must return ok=false")
	}
}

func TestEditorArgvSplitsArguments(t *testing.T) {
	t.Setenv("EDITOR", "code -w")
	argv, ok := EditorArgv()
	if !ok {
		t.Fatal("EditorArgv must succeed with EDITOR set")
	}
	if !reflect.DeepEqual(argv, []string{"code", "-w"}) {
		t.Fatalf("EditorArgv() = %#v, want [code -w]", argv)
	}
}

// TestOpenInEditorCmdMissingEditorSaysWhatDidNotHappen is FR-024's own gate
// for this action: with no $EDITOR configured, the message names WHAT did
// not happen ("no editor"), never a raw exec error, and no *exec.Cmd is
// built at all.
func TestOpenInEditorCmdMissingEditorSaysWhatDidNotHappen(t *testing.T) {
	t.Setenv("EDITOR", "")
	cmd, reason, ok := OpenInEditorCmd("src/a.go", ".")
	if ok || cmd != nil {
		t.Fatalf("expected ok=false and a nil cmd, got ok=%v cmd=%v", ok, cmd)
	}
	if reason == "" {
		t.Fatal("expected a non-empty reason naming what did not happen")
	}
}

// TestOpenInEditorCmdMissingExecutableSaysWhatDidNotHappen: $EDITOR is set
// but names an executable that is not on $PATH — same "what did not
// happen" shape, not a raw LookPath error.
func TestOpenInEditorCmdMissingExecutableSaysWhatDidNotHappen(t *testing.T) {
	t.Setenv("EDITOR", "definitely-not-a-real-editor-binary")
	cmd, reason, ok := OpenInEditorCmd("src/a.go", ".")
	if ok || cmd != nil {
		t.Fatalf("expected ok=false and a nil cmd, got ok=%v cmd=%v", ok, cmd)
	}
	if reason == "" {
		t.Fatal("expected a non-empty reason naming what did not happen")
	}
}

// TestOpenInEditorCmdPathsWithSpaceAndNonASCII is T089's own gate: a
// display path with a space or non-ASCII bytes must arrive at the editor's
// argv UNCHANGED, as its own argument — never mangled by a naive
// whitespace split, and never quoted again (exec.Cmd's argv is not a shell
// command line).
func TestOpenInEditorCmdPathsWithSpaceAndNonASCII(t *testing.T) {
	editor := "cmd"
	if runtime.GOOS != "windows" {
		editor = "true"
	}
	t.Setenv("EDITOR", editor)
	display := `src/año with space.go`
	cmd, reason, ok := OpenInEditorCmd(display, ".")
	if !ok {
		t.Fatalf("expected ok=true, got reason=%q", reason)
	}
	last := cmd.Args[len(cmd.Args)-1]
	if last != display {
		t.Fatalf("editor argv's last argument = %q, want %q (unchanged)", last, display)
	}
}

// TestOpenInEditorCmdDoesNotCheckWhetherThePathExists is research.md
// Decisión 12's "un archivo eliminado en el rango no es fatal": neither
// OpenInEditorCmd nor DiffPathCmd stats the path at all — a file deleted
// somewhere in the review's range still builds a real command (the editor
// or git decides what an absent path means, informatively, never this
// client refusing to even try).
func TestOpenInEditorCmdDoesNotCheckWhetherThePathExists(t *testing.T) {
	t.Setenv("EDITOR", "cmd")
	if runtime.GOOS != "windows" {
		t.Setenv("EDITOR", "true")
	}
	missing := "this/path/definitely-does-not-exist-anywhere.go"
	cmd, reason, ok := OpenInEditorCmd(missing, ".")
	if !ok {
		t.Fatalf("a missing FILE path must not make OpenInEditorCmd fail, got reason=%q", reason)
	}
	if cmd.Args[len(cmd.Args)-1] != missing {
		t.Fatalf("editor argv's last argument = %q, want the missing path unchanged", cmd.Args[len(cmd.Args)-1])
	}
	diffCmd := DiffPathCmd(missing, ".")
	if diffCmd == nil {
		t.Fatal("DiffPathCmd must build a command for a missing path too — git itself decides what that means")
	}
}

func TestDiffPathCmdBuildsExpectedArgv(t *testing.T) {
	cmd := DiffPathCmd("src/a.go", "/repo")
	want := []string{"git", "-c", "core.quotePath=false", "diff", "HEAD", "--", "src/a.go"}
	if !reflect.DeepEqual(cmd.Args, want) {
		t.Fatalf("DiffPathCmd args = %#v, want %#v", cmd.Args, want)
	}
	if cmd.Dir != "/repo" {
		t.Fatalf("DiffPathCmd Dir = %q, want /repo", cmd.Dir)
	}
}

func TestDiffCommitCmdBuildsExpectedArgv(t *testing.T) {
	cmd := DiffCommitCmd("abc1234", "/repo")
	want := []string{"git", "-c", "core.quotePath=false", "diff", "abc1234^", "abc1234"}
	if !reflect.DeepEqual(cmd.Args, want) {
		t.Fatalf("DiffCommitCmd args = %#v, want %#v", cmd.Args, want)
	}
}

func TestPreviewEditsCmdBuildsExpectedArgv(t *testing.T) {
	cmd := PreviewEditsCmd("/repo")
	want := []string{"git", "review", "preview"}
	if !reflect.DeepEqual(cmd.Args, want) {
		t.Fatalf("PreviewEditsCmd args = %#v, want %#v", cmd.Args, want)
	}
}

// TestOpenURLCmdUsesThePlatformBrowserOpener proves that link controls hand
// their allowlisted URL to the operating system's URL opener, rather than
// displaying text that the reviewer must copy and paste themselves.
func TestOpenURLCmdUsesThePlatformBrowserOpener(t *testing.T) {
	url := "https://example.invalid/install#options"
	cmd := OpenURLCmd(url)

	var want []string
	switch runtime.GOOS {
	case "windows":
		want = []string{"rundll32", "url.dll,FileProtocolHandler", url}
	case "darwin":
		want = []string{"open", url}
	default:
		want = []string{"xdg-open", url}
	}
	if !reflect.DeepEqual(cmd.Args, want) {
		t.Fatalf("OpenURLCmd args = %#v, want %#v", cmd.Args, want)
	}
}
