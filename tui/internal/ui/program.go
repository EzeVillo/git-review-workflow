package ui

import (
	"context"
	"os"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	tea "github.com/charmbracelet/bubbletea"
)

// Model is the bubbletea program's whole state. It carries the drawn
// PanelModel (comparable by value, per domain/panelmodel.go) plus the two
// pieces of state that are NOT product state: the terminal Viewport and
// which row currently has keyboard focus.
type Model struct {
	Viewport   Viewport
	Panel      domain.PanelModel
	FocusIndex int
	busy       bool
}

// NewModel builds the program's initial state: waiting_text on the very
// first frame (T046), before any invocation has even started, and the
// mouse reporting on by default (contracts/tui-surface.md § Mouse).
func NewModel() Model {
	return Model{
		Viewport: Viewport{Cols: 80, Rows: 24, Color: true},
		Panel:    domain.PanelModel{Situation: domain.SituationWaiting, MouseEnabled: true},
	}
}

// --- the six message classes (T045) -----------------------------------------

// watchMsg is disparador 2 (file-event coalesced into one signal, FR-062):
// no payload, no watcher exists yet to send it (Phase 5, T054-T059) — the
// type and its handling below land now so that phase only has to wire a
// sender, never touch Update's shape.
type watchMsg struct{}

// readDoneMsg carries one full host.ReadState cycle's result back from the
// tea.Cmd that ran it.
type readDoneMsg struct{ result host.ReadResult }

// mutationDoneMsg carries one CLI mutation's result back. Real mutations are
// Phase 6 (T070-T082); today nothing produces this message, but Update
// already knows how to react to one: re-read (disparador 1, contracts/
// refresh.md), the same way a real mutation's own follow-up read will.
type mutationDoneMsg struct{ result host.Result }

// Init returns the FIRST read as a Cmd — never invoked synchronously — so
// bubbletea renders the model's zero/waiting state at least once before any
// process has even started (T046).
func (m Model) Init() tea.Cmd {
	return readCmd()
}

func readCmd() tea.Cmd {
	return func() tea.Msg {
		cwd, _ := os.Getwd()
		return readDoneMsg{result: host.ReadState(context.Background(), cwd, domain.MinCLIVersion)}
	}
}

// Update never calls into internal/host itself — every branch either
// mutates m's own fields or returns a tea.Cmd for bubbletea to run later.
// program_test.go's TestUpdateNeverImportsOSExec is the structural half of
// that guarantee; this comment is the other half, since the guarantee is
// "look at what Update returns", not "search for a banned import" (invoke.go
// does the real spawning; this file only ever calls readCmd()/mutation
// helpers that themselves return Cmds).
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.Viewport.Cols = msg.Width
		m.Viewport.Rows = msg.Height
		return m, nil

	case tea.FocusMsg:
		// Disparador 3: never suppressed by the mutation lock (contracts/
		// refresh.md). Phase 6 adds the lock; today there is nothing to
		// suppress against.
		return m, readCmd()

	case tea.BlurMsg:
		return m, nil

	case watchMsg:
		// Disparador 2: no sender exists before Phase 5. When one does, it
		// reaches here exactly like FocusMsg does today.
		return m, readCmd()

	case readDoneMsg:
		m.Panel = domain.Project(toProjectInput(msg.result, m.Panel.MouseEnabled, m.busy))
		if m.FocusIndex >= len(ControlsFor(m.Panel)) {
			m.FocusIndex = 0
		}
		return m, nil

	case mutationDoneMsg:
		m.busy = false
		return m, readCmd()

	case tea.KeyMsg:
		return m.handleKey(msg)

	case tea.MouseMsg:
		return m.handleMouse(msg)
	}
	return m, nil
}

func (m Model) View() string {
	frame, _ := View(m.Panel, m.Viewport)
	return frame
}

func (m Model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	intent := ResolveKey(msg.String(), m)
	switch intent.Kind {
	case IntentQuit:
		return m, tea.Quit

	case IntentFocusMove:
		n := len(ControlsFor(m.Panel))
		if n == 0 {
			return m, nil
		}
		switch intent.Movement {
		case "focus_next_row":
			m.FocusIndex = (m.FocusIndex + 1) % n
		case "focus_prev_row":
			m.FocusIndex = (m.FocusIndex - 1 + n) % n
		}
		return m, nil

	case IntentBoundAction:
		if intent.Action == "refresh" {
			return m, readCmd()
		}
		return m, nil

	case IntentCursorAction:
		// next/prev the review cursor: BuildArgv("next"/"prev", ...) exists
		// in domain/actions.go, but wiring it to a real mutation (the lock,
		// the confirmation-free path, the follow-up read) is T073 (Phase 6).
		// The intent above is what T053's reachability test asserts on.
		return m, nil

	case IntentToggle:
		if intent.Toggle == "mouse_reporting" {
			m.Panel.MouseEnabled = !m.Panel.MouseEnabled
			if m.Panel.MouseEnabled {
				return m, tea.EnableMouseCellMotion
			}
			return m, tea.DisableMouse
		}
		return m, nil

	case IntentOverlay, IntentActivate:
		// action_list/entry_picker (Phase 8) and the body controls' real
		// mutations (Phase 6+) are not wired yet; the correct Intent having
		// been produced is what T053 checks for a control that lands here.
		return m, nil
	}
	return m, nil
}

func (m Model) handleMouse(msg tea.MouseMsg) (tea.Model, tea.Cmd) {
	if msg.Action != tea.MouseActionPress {
		return m, nil
	}
	_, hm := View(m.Panel, m.Viewport)
	id, variant, ok := hm.At(msg.X, msg.Y)
	if !ok {
		return m, nil
	}
	for i, c := range ControlsFor(m.Panel) {
		if c.ID == id && c.Variant == variant {
			m.FocusIndex = i
			return m, nil
		}
	}
	return m, nil
}

// toProjectInput adapts one host.ReadResult into domain.ProjectInput. It is
// the one seam between "what the host read" and "what the domain projects"
// — kept here (ui), not in host or domain, because it is neither I/O nor
// pure derivation: it is wiring between the two, exactly like Visual
// Studio's/JetBrains' host-side adapters.
func toProjectInput(r host.ReadResult, mouseEnabled, busy bool) domain.ProjectInput {
	return domain.ProjectInput{
		Situation:    r.Situation,
		Status:       r.Status,
		HasStatus:    r.HasStatus,
		Branches:     r.Branches,
		Fixes:        r.Fixes,
		HasList:      r.HasList,
		Config:       r.Config,
		HasConfig:    r.HasConfig,
		Why:          r.Why,
		HasWhy:       r.HasWhy,
		MouseEnabled: mouseEnabled,
		Busy:         busy,
		Stderr:       r.Stderr,
	}
}
