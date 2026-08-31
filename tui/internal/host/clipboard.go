// clipboard.go is the whole portapapeles surface (T092, research.md
// Decisión 11): OSC 52, and nothing else. It never shells out to an
// external clipboard tool — over SSH, or inside a terminal multiplexer,
// those tools copy to the wrong machine's clipboard or simply are not
// installed, which is the scenario the spec puts first.
package host

import (
	"encoding/base64"
	"os"
)

// osc52Writer is the one seam a test can substitute for the real terminal —
// CopyOSC52 writes through it instead of calling os.Stdout.WriteString
// directly, which is what lets clipboard_test.go assert on the exact bytes
// without a real terminal attached at all.
var osc52Writer = func(s string) { os.Stdout.WriteString(s) }

// CopyOSC52 writes text to the terminal-mediated clipboard via the OSC 52
// escape sequence — no acknowledgement exists for it: the terminal never
// says whether it accepted the sequence, so the only honest thing this
// function's caller can say is that the sequence was WRITTEN, never that it
// was COPIED (FR-068; contracts/tui-surface.md § Mouse — "el control nunca
// afirma haber copiado"). Writing it while the alt screen is up is the same
// well-established technique other terminal programs already rely on: OSC
// 52 is an escape sequence terminals intercept and never echo into the
// visible frame.
func CopyOSC52(text string) {
	encoded := base64.StdEncoding.EncodeToString([]byte(text))
	osc52Writer("\x1b]52;c;" + encoded + "\x07")
}

// SetOSC52WriterForTest substitutes the writer CopyOSC52 uses and returns a
// func that restores the real one. Test-only: production code always writes
// to the real terminal.
func SetOSC52WriterForTest(w func(string)) (restore func()) {
	prev := osc52Writer
	osc52Writer = w
	return func() { osc52Writer = prev }
}
