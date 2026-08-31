package ui

import (
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	tea "github.com/charmbracelet/bubbletea"
)

// TestMutationSilenceWindowProducesExactlyOneRepaint is SC-004's own gate
// (T064): a mutation whose own writes make the watcher fire several times
// during its silence window still produces exactly ONE frame change,
// because domain.PanelModel is comparable by value (domain/panelmodel.go's
// own doc) and re-reading identical porcelain twice in a row yields two
// byte-identical PanelModel values. This is asserted by comparing m.Panel
// across each step with `==`, never by counting how many reads happened —
// contracts/refresh.md's own words: "SC-004 se afirma sobre el repintado,
// no sobre el número de lecturas."
func TestMutationSilenceWindowProducesExactlyOneRepaint(t *testing.T) {
	before := host.ReadResult{
		Situation: domain.SituationNoReview,
		HasConfig: true,
		Config: domain.ConfigPorcelainResult{
			Config: domain.EffectiveConfig{Base: "develop", HasBase: true, Remote: "origin"},
		},
	}
	// The mutation's OWN effect: setBase actually changed the configured
	// base. Every read AFTER the mutation reports this same new state —
	// the first one is what SC-004's "exactly one" repaint counts, and
	// every read after that (the mutation's own late-arriving watch events,
	// per contracts/refresh.md) must repaint ZERO further times because
	// they report the identical, already-drawn state.
	after := host.ReadResult{
		Situation: domain.SituationNoReview,
		HasConfig: true,
		Config: domain.ConfigPorcelainResult{
			Config: domain.EffectiveConfig{Base: "main", HasBase: true, Remote: "origin"},
		},
	}

	m := NewModel()
	// Settle to a baseline no-review panel BEFORE the mutation itself —
	// that first transition (waiting -> no-review) is not part of what
	// this test measures.
	baselineM, _ := m.Update(readDoneMsg{result: before})
	m = baselineM.(Model)

	// Acquire the lock exactly as beginMutation would, so handleMutationDone
	// below has something real to End(). One Begin() from zero makes the
	// lock's own generation 1 — which is why silenceWindowMsg is built with
	// gen: 1 further down, deterministically, without needing an exported
	// accessor onto host.MutationLock's private fields.
	m.lock.Begin()

	repaints := 0
	step := func(msg tea.Msg) {
		before := m.Panel
		newM, _ := m.Update(msg)
		m = newM.(Model)
		if m.Panel != before {
			repaints++
		}
	}

	// The mutation's own end: schedules the guaranteed immediate read
	// (disparador 1) and the silence-window timer. Neither Cmd is executed
	// for real here — this test feeds the messages they would eventually
	// produce, the same convention every other Update-level test in this
	// package already follows for readCmd().
	step(mutationDoneMsg{action: "setBase", params: domain.ActionParams{}, result: host.Result{ExitCode: 0}})
	// The immediate read lands, reporting the NEW state — the one and only
	// repaint this whole sequence should ever produce.
	step(readDoneMsg{result: after})
	// A watchMsg fires while the silence window is still open: suppressed
	// and remembered, no read of its own.
	step(watchMsg{})
	// The window closes; because something was suppressed during it, this
	// owes exactly one more read.
	step(silenceWindowMsg{gen: 1})
	// That read lands, reporting the SAME (new) state yet again — same
	// PanelModel value, so no further repaint.
	step(readDoneMsg{result: after})

	if repaints != 1 {
		t.Fatalf("got %d repaints across the mutation's own refresh cycle, want exactly 1 (SC-004)", repaints)
	}
}

// TestSilenceWindowWithNothingSuppressedCostsNoExtraRead is the mirror
// case: if nothing fired during the window, WindowClosed reports no read is
// owed, so there is no third readDoneMsg to even send — asserted here by
// checking the lock directly rather than by counting frames, since "no
// message was ever produced" cannot be observed as a repaint count of zero
// (zero is also what a same-state read produces).
func TestSilenceWindowWithNothingSuppressedCostsNoExtraRead(t *testing.T) {
	m := NewModel()
	m.lock.Begin()
	newM, _ := m.Update(mutationDoneMsg{action: "saveReview", result: host.Result{ExitCode: 0}})
	m = newM.(Model)
	if m.lock.WindowClosed(1) {
		t.Fatal("a window nothing was suppressed during must not owe a read")
	}
}
