// package host_test, not host: this is the one test in the module that
// needs BOTH internal/host and internal/ui in the same file (to drive a
// real Model through its startup read before watching it sit idle), which
// an internal `package host` test file cannot do without an import cycle
// (internal/ui already imports internal/host).
package host_test

import (
	"context"
	"testing"
	"time"

	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	"github.com/EzeVillo/git-review-workflow/tui/internal/ui"
)

// TestModelAtRestCausesNoInvocations is SC-002's own test: with the model
// past its startup read — "the TUI open on screen" — and NOTHING sending it
// another Msg for a whole window, the invocation log must gain exactly
// zero entries. This is what FR-063 ("la vigilancia es un acelerador, no un
// cimiento") demands as a MEASURED number, not a description — and per
// T054's own note, it is also what every OTHER test in Phase 3/4 already
// proves incidentally by running with nopWatcher; this is the one test
// that measures it directly, on purpose.
func TestModelAtRestCausesNoInvocations(t *testing.T) {
	m := ui.NewModel()
	cmd := m.Init()
	if cmd == nil {
		t.Fatal("Init() must return a Cmd for the startup read")
	}
	msg := cmd() // run the ONE legitimate startup read, exactly as bubbletea's runtime would
	newModel, _ := m.Update(msg)
	m = newModel.(ui.Model)

	// nopWatcher is what cmd/git-review-ui/main.go wires in whenever
	// GIT_REVIEW_UI_WATCH is unset (the suite's default) — exercised here
	// directly to confirm the other half of "sin tocarla": no watchMsg
	// arrives during the idle window either.
	watcher := host.NewNopWatcher()
	ch, err := watcher.Start(context.Background(), "", "", nil)
	if err != nil {
		t.Fatalf("nopWatcher.Start: %v", err)
	}
	t.Cleanup(func() { _ = watcher.Stop() })

	host.ResetInvocationLogForTest() // only the STEADY, idle state counts here

	idle := time.After(300 * time.Millisecond)
	select {
	case <-ch:
		t.Fatal("nopWatcher must never send on its channel")
	case <-idle:
	}

	if got := len(host.InvocationLog()); got != 0 {
		t.Fatalf("invocation log has %d entries after an idle window with no Msg sent, want 0", got)
	}

	// The model itself must be unchanged too — Update was never called
	// again, so there is nothing else to assert beyond the log staying
	// empty, but keeping the reference alive documents that this is a
	// steady-state check, not a "never even started" one.
	_ = m
}
