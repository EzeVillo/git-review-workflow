package ui

import (
	"context"
	"os"
	"time"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	tea "github.com/charmbracelet/bubbletea"
)

// Model is the bubbletea program's whole state. It carries the drawn
// PanelModel (comparable by value, per domain/panelmodel.go) plus the
// pieces of state that are NOT product state: the terminal Viewport, which
// row currently has keyboard focus, and FR-039's opt-in poll floor
// bookkeeping (pollFloor/pollGen — see scheduleRead).
type Model struct {
	Viewport   Viewport
	Panel      domain.PanelModel
	FocusIndex int
	busy       bool
	pollFloor  time.Duration
	pollGen    int
}

// NewModel builds the program's initial state: waiting_text on the very
// first frame (T046), before any invocation has even started, and the
// mouse reporting on by default (contracts/tui-surface.md § Mouse). The
// opt-in poll floor (FR-039) starts off, exactly as every existing test
// that calls this constructor already relies on.
func NewModel() Model {
	return NewModelWithPollFloor(0)
}

// NewModelWithPollFloor is NewModel plus contracts/refresh.md § El piso de
// poll opt-in: seconds is `reviewui.pollseconds` as the composition root
// (cmd/git-review-ui/main.go) already resolved it — 0 (its zero value)
// means "off", which is what makes every OTHER caller of this package's
// bare NewModel() unaffected by this existing at all.
func NewModelWithPollFloor(seconds int) Model {
	m := Model{
		Viewport: Viewport{Cols: 80, Rows: 24, Color: true},
		Panel:    domain.PanelModel{Situation: domain.SituationWaiting, MouseEnabled: true},
	}
	if seconds > 0 {
		m.pollFloor = time.Duration(seconds) * time.Second
	}
	return m
}

// WatchTick constructs disparador 2's message as an opaque tea.Msg. It
// exists so that whatever assembles the real Watcher and forwards its
// channel (cmd/git-review-ui/main.go) can call tea.Program.Send(WatchTick())
// without this package ever exporting watchMsg's own type — Update's
// handling of it was already in place before Phase 5 built anything that
// could send one.
func WatchTick() tea.Msg { return watchMsg{} }

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

// pollFloorMsg is FR-039's opt-in poll floor firing. gen ties it to the
// exact scheduleRead() call that armed it: if a NEWER read has happened
// since (from ANY of the four triggers), gen is stale against the model's
// current pollGen and this tick is inert — the floor only ever acts when
// nothing else has read more recently than Interval ago, which is what
// keeps it from adding a single invocation while the watcher (or focus, or
// the keyboard) is already doing its job.
type pollFloorMsg struct{ gen int }

// Init returns the FIRST read as a Cmd — never invoked synchronously — so
// bubbletea renders the model's zero/waiting state at least once before any
// process has even started (T046). When the poll floor is configured, its
// very first tick is armed here too (gen 0, matching the model's own zero
// value): if nothing else re-arms it first, it is what covers the window
// between startup and the first FocusMsg/watchMsg/keypress.
func (m Model) Init() tea.Cmd {
	if m.pollFloor <= 0 {
		return readCmd()
	}
	return tea.Batch(readCmd(), pollFloorTickCmd(m.pollFloor, m.pollGen))
}

func readCmd() tea.Cmd {
	return func() tea.Msg {
		cwd, _ := os.Getwd()
		return readDoneMsg{result: host.ReadState(context.Background(), cwd, domain.MinCLIVersion)}
	}
}

func pollFloorTickCmd(interval time.Duration, gen int) tea.Cmd {
	return tea.Tick(interval, func(time.Time) tea.Msg {
		return pollFloorMsg{gen: gen}
	})
}

// scheduleRead is every path that means "go read now": disparadores 2
// (watchMsg), 3 (FocusMsg), 4 (the refresh key), and the read a mutation's
// own end triggers. It bumps the poll floor's generation — which makes any
// tick armed by an EARLIER read inert — and, only when the opt-in floor is
// configured, arms a fresh tick that fires the floor's own read if nothing
// else does first. Routing every "go read now" site through this instead
// of each calling readCmd() directly is what makes "re-arm on every read,
// from wherever" true by construction (FR-039), rather than by remembering
// to call something at N call sites.
func (m Model) scheduleRead() (Model, tea.Cmd) {
	m.pollGen++
	if m.pollFloor <= 0 {
		return m, readCmd()
	}
	return m, tea.Batch(readCmd(), pollFloorTickCmd(m.pollFloor, m.pollGen))
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
		return m.scheduleRead()

	case tea.BlurMsg:
		return m, nil

	case watchMsg:
		// Disparador 2, sent via WatchTick() by whatever forwards the real
		// Watcher's channel (cmd/git-review-ui/main.go, Phase 5) — handled
		// exactly like FocusMsg.
		return m.scheduleRead()

	case pollFloorMsg:
		if msg.gen != m.pollGen {
			return m, nil // superseded by a more recent read; staying quiet IS the point (FR-039)
		}
		return m.scheduleRead()

	case readDoneMsg:
		m.Panel = domain.Project(toProjectInput(msg.result, m.Panel.MouseEnabled, m.busy))
		if m.FocusIndex >= len(ControlsFor(m.Panel)) {
			m.FocusIndex = 0
		}
		return m, nil

	case mutationDoneMsg:
		m.busy = false
		return m.scheduleRead()

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
			// Disparador 4, FR-038: available in all eight situations, and
			// the one trigger that is NEVER suppressed or degraded.
			return m.scheduleRead()
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
