package host

import (
	"encoding/base64"
	"os"
	"strings"
	"testing"
)

// TestCopyOSC52WritesTheSequence is the mechanical half: the exact OSC 52
// bytes (ESC ] 52 ; c ; <base64> BEL), the payload base64-decoding back to
// the original text, and — the point of T092 — nothing about pbcopy, xclip,
// wl-copy or clip.exe: this function never shells out to an external
// clipboard tool at all.
func TestCopyOSC52WritesTheSequence(t *testing.T) {
	var got string
	restore := SetOSC52WriterForTest(func(s string) { got = s })
	defer restore()

	CopyOSC52("hello, review")

	if !strings.HasPrefix(got, "\x1b]52;c;") || !strings.HasSuffix(got, "\x07") {
		t.Fatalf("CopyOSC52 wrote %q, want an OSC 52 sequence", got)
	}
	payload := strings.TrimSuffix(strings.TrimPrefix(got, "\x1b]52;c;"), "\x07")
	decoded, err := base64.StdEncoding.DecodeString(payload)
	if err != nil {
		t.Fatalf("payload is not valid base64: %v", err)
	}
	if string(decoded) != "hello, review" {
		t.Fatalf("decoded payload = %q, want %q", decoded, "hello, review")
	}
}

// TestCopyOSC52NeverShellsOut sweeps this file's own source for the four
// external clipboard tools FR-068/research.md Decisión 11 rule out — the
// exact failure mode SSH and a terminal multiplexer both hit: those tools
// reach the wrong machine's clipboard, or do not exist at all.
func TestCopyOSC52NeverShellsOut(t *testing.T) {
	b, err := os.ReadFile("clipboard.go")
	if err != nil {
		t.Fatal(err)
	}
	src := string(b)
	for _, tool := range []string{"pbcopy", "xclip", "wl-copy", "clip.exe"} {
		if strings.Contains(src, tool) {
			t.Fatalf("clipboard.go references %q; OSC 52 must be the only path", tool)
		}
	}
}
