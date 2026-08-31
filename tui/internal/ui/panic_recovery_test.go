package ui

import (
	"bytes"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// panicTrigger is a tea.Msg with no production sender anywhere in this
// client -- it exists ONLY in this test file, as the deterministic way to
// make crashModel.Update panic on command, without leaving any test-only
// branch inside program.go's own Update (FR-044's gate needs a REAL panic,
// not a simulated one, but "real" means "an actual runtime panic
// propagating out of Update", not "reachable from production input").
type panicTrigger struct{}

// crashModel wraps the real ui.Model — the real Init/View, the real
// tea.WithAltScreen()/WithMouseCellMotion() options this test configures
// below, same as cmd/git-review-ui/main.go — and injects exactly one
// deterministic panic into its Update. Bubble Tea's own recovery (tea.go's
// Run, "Recover from panics") is what T098 is checking; wrapping the real
// Model rather than a bare stub is what makes this a test of THIS client's
// composition, not just of the library in isolation.
type crashModel struct{ Model }

func (m crashModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if _, ok := msg.(panicTrigger); ok {
		panic("T098: synthetic panic to prove the terminal comes back clean")
	}
	updated, cmd := m.Model.Update(msg)
	return crashModel{updated.(Model)}, cmd
}

// TestPanicInUpdateRestoresTerminal is FR-044's own gate: a real panic
// raised from inside Update must leave the terminal restored -- alt screen
// exited, cursor shown again -- not merely "probably fine because Bubble
// Tea says so in its docs". tea.WithOutput(&buf) lets this run without a
// real TTY (bubbletea's own screen_test.go proves these exact escape
// sequences are written to a plain io.Writer regardless of whether it is
// backed by a terminal), and tea.WithInput(nil) disables the input loop
// entirely (documented on tea.WithInput) so the only message this program
// ever receives is the one this test sends itself.
func TestPanicInUpdateRestoresTerminal(t *testing.T) {
	var buf bytes.Buffer
	p := tea.NewProgram(crashModel{Model: NewModel()},
		tea.WithInput(nil),
		tea.WithOutput(&buf),
		tea.WithAltScreen(),
		tea.WithMouseCellMotion(),
	)

	done := make(chan struct{})
	go func() {
		defer close(done)
		time.Sleep(30 * time.Millisecond) // let Init's first frame draw
		p.Send(panicTrigger{})
	}()

	_, runErr := p.Run()
	<-done

	if runErr == nil {
		t.Fatal("Run() must return an error after Update panicked, not nil")
	}

	out := buf.String()
	const (
		enterAltScreen = "\x1b[?1049h"
		exitAltScreen  = "\x1b[?1049l"
		showCursor     = "\x1b[?25h"
	)

	enterIdx := strings.Index(out, enterAltScreen)
	if enterIdx < 0 {
		t.Fatalf("alt screen was never entered -- this test's own setup is broken:\n%q", out)
	}
	exitIdx := strings.Index(out, exitAltScreen)
	if exitIdx < 0 || exitIdx < enterIdx {
		t.Fatalf("alt screen was not exited after the panic -- the terminal would be left showing the TUI's blank screen:\n%q", out)
	}
	if !strings.Contains(out[exitIdx:], showCursor) {
		t.Fatalf("the cursor was not shown again after the panic -- it would be left hidden in the user's shell:\n%q", out)
	}
}
