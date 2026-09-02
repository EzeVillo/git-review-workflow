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
// row currently has keyboard focus, FR-039's opt-in poll floor bookkeeping
// (pollFloor/pollGen — see scheduleRead), the generation that prevents late
// reads from repainting newer state, and Phase 6's mutation cycle —
// the depth-1 lock, the one confirmation overlay, the one selection
// overlay (start assistant / setBase / setRemote / finish-destination),
// the last full read (mutation.go's setBase/setRemote pickers read
// Candidates/Remotes straight off it rather than spending a fresh probe on
// data every regular refresh already fetched), the sticky status line
// (domain.PanelModel.StatusLine's own doc), and the one finishReview
// outcome still waiting on its next read to resolve.
type Model struct {
	Viewport       Viewport
	Panel          domain.PanelModel
	FocusIndex     int
	footerOffset   int
	hover          *controlTarget
	pollFloor      time.Duration
	pollGen        int
	readGeneration int
	lock           host.MutationLock
	confirm        *ConfirmOverlay
	selectOverlay  *SelectOverlay
	// actionList / textOverlay: Phase 8's own two extra overlays — the
	// action palette (T084, this client's `surface: action`) and the
	// read-only text viewer showCliLog/previewEditsStat open (T087/T088).
	// Mutually exclusive with confirm/selectOverlay and with each other, the
	// same "at most one open at a time" shape those two already establish.
	actionList  *ActionList
	textOverlay *TextOverlay
	// textPrompt: compareReview's own free-text lower/upper questions
	// (T089) — the one flow that needs typed input rather than a picked
	// item, chained via selectResult exactly like selectOverlay's own
	// questions (applySelectResult in select.go).
	textPrompt           *TextPrompt
	lastRead             host.ReadResult
	statusLine           string
	pendingFinish        *pendingFinishOutcome
	preferredStartSource string
	activityGeneration   int
	activity             activityState
	progressOverlay      *ProgressOverlay
	// onAcceptedRead is the composition root's watcher boundary. Update
	// invokes it only after the generation guard accepts a read; callers
	// must keep it to an in-memory enqueue so filesystem work stays outside
	// Bubble Tea's event loop.
	onAcceptedRead func(host.ReadResult)
}

// WithPreferredStartSource sets reviewui.startsource's resolved value
// (FR-061): the start assistant's SOURCE question pre-positions its cursor
// on it when present, and otherwise never hides an option the CLI itself
// did not rule out. cmd/git-review-ui/main.go is the one caller — reading
// the config key itself happens there, not here, the same split every other
// piece of `reviewui.*` config already follows (pollFloor/pollGen above).
func (m Model) WithPreferredStartSource(source string) Model {
	m.preferredStartSource = source
	return m
}

// WithAcceptedReadCallback installs the one-way boundary used by the
// composition root to keep watcher roots synchronized with accepted
// porcelain reads. A stale read never crosses it.
func (m Model) WithAcceptedReadCallback(callback func(host.ReadResult)) Model {
	m.onAcceptedRead = callback
	return m
}

// WithViewportCapabilities sets the two startup-decided Viewport fields the
// composition root (cmd/git-review-ui/main.go) resolves before the terminal
// ever draws a frame: NO_COLOR's presence (T095) and the ASCII glyph
// fallback (T096, driven by locale/codepage, never by NO_COLOR -- color and
// drawing are two independent questions, contracts/tui-surface.md §
// Iconos). Cols/Rows are deliberately left untouched here: bubbletea's own
// first tea.WindowSizeMsg supplies the real terminal size moments later, and
// Update's WindowSizeMsg branch never touches Color/ASCII, so setting them
// once here is enough for both to survive every subsequent resize.
func (m Model) WithViewportCapabilities(color, ascii bool) Model {
	m.Viewport.Color = color
	m.Viewport.ASCII = ascii
	return m
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

// readDoneMsg carries one full host.ReadState cycle's result and generation
// back from the tea.Cmd that ran it.
type readDoneMsg struct {
	generation int
	result     host.ReadResult
}

// mutationDoneMsg (Phase 6) is defined in mutation.go, alongside the rest of
// the mutation cycle it feeds: handleMutationDone, the lock, the status
// line and undoFinish's --force retry.

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
		return readCmd(m.readGeneration)
	}
	return tea.Batch(readCmd(m.readGeneration), pollFloorTickCmd(m.pollFloor, m.pollGen))
}

func readCmd(generation int) tea.Cmd {
	return func() tea.Msg {
		cwd, _ := os.Getwd()
		return readDoneMsg{generation: generation, result: host.ReadState(context.Background(), cwd, domain.MinCLIVersion)}
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
	m.readGeneration++
	if m.pollFloor <= 0 {
		return m, readCmd(m.readGeneration)
	}
	return m, tea.Batch(readCmd(m.readGeneration), pollFloorTickCmd(m.pollFloor, m.pollGen))
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
		// Watcher's channel (cmd/git-review-ui/main.go, Phase 5) — the ONE
		// trigger the mutation lock suppresses (contracts/refresh.md's
		// table): while a verb is running, or during its post-mutation
		// silence window, this is discarded and remembered rather than
		// acted on (host.MutationLock.Suppress).
		if m.lock.Suppress() {
			return m, nil
		}
		return m.scheduleRead()

	case pollFloorMsg:
		if msg.gen != m.pollGen {
			return m, nil // superseded by a more recent read; staying quiet IS the point (FR-039)
		}
		return m.scheduleRead()

	case activityVisibleMsg:
		if m.activity.active && msg.generation == m.activity.generation {
			m.activity.visible = true
		}
		return m, nil

	case readDoneMsg:
		if msg.generation != m.readGeneration {
			return m, nil
		}
		m.lastRead = msg.result
		if m.onAcceptedRead != nil {
			m.onAcceptedRead(msg.result)
		}
		m.Panel = domain.Project(toProjectInput(msg.result, m.Panel.MouseEnabled, m.lock.Busy(), m.statusLine))
		if m.pendingFinish != nil {
			// finishReview's own deferred outcome (T074): the fresh read's
			// matching list record is the only honest answer to "did THIS
			// source land pending or not" — never the verb's own stdout or
			// another review's repository-wide pending state (FR-013).
			if !m.pendingFinish.matchesPending(msg.result) {
				text := m.pendingFinish.destination() + domain.FinishReadySuffix
				m.statusLine = text
				m.Panel.StatusLine = text
			}
			m.pendingFinish = nil
		}
		if m.FocusIndex >= len(ControlsFor(m.Panel)) {
			m.FocusIndex = 0
		}
		return m, nil

	case mutationDoneMsg:
		return m.handleMutationDone(msg)

	case silenceWindowMsg:
		if m.lock.WindowClosed(msg.gen) {
			return m.scheduleRead()
		}
		return m, nil

	case assistantStepMsg:
		return m.handleAssistantStep(msg)

	case execDoneMsg:
		// T089: "al volver dispara un refresco" -- the reviewer may have
		// edited and saved inside the child process. err is deliberately
		// not surfaced: a nonzero exit from $EDITOR or a diff tool is
		// common (":cq" in vim, a diff tool's own exit code) and does not
		// mean anything failed -- and there is no stderr to show anyway,
		// since the child owned the terminal directly.
		return m.scheduleRead()

	case textActionDoneMsg:
		m.textOverlay = &TextOverlay{Title: msg.title, Body: textOverlayBody(msg.title, msg.result)}
		return m, nil

	case tea.KeyMsg:
		if m.confirm != nil {
			return m.handleConfirmKey(msg)
		}
		if m.selectOverlay != nil {
			return m.handleSelectKey(msg)
		}
		if m.textPrompt != nil {
			return m.handleTextPromptKey(msg)
		}
		if m.actionList != nil {
			return m.handleActionListKey(msg)
		}
		if m.textOverlay != nil {
			if m.textOverlay.HandleKey(msg.String()) {
				m.textOverlay = nil
			}
			return m, nil
		}
		if m.progressOverlay != nil {
			return m, nil
		}
		return m.handleKey(msg)

	case tea.MouseMsg:
		if m.confirm != nil || m.selectOverlay != nil || m.textPrompt != nil || m.actionList != nil || m.textOverlay != nil {
			// A stray event while an overlay is open must never resolve
			// against the HIDDEN base panel underneath it (T090).
			return m, nil
		}
		return m.handleMouse(msg)
	}
	return m, nil
}

func (m Model) View() string {
	// The confirm overlay and the select overlay are mutually exclusive by
	// construction (handleConfirmKey/handleSelectKey each clear their own
	// field before ever opening the other), and both take over the WHOLE
	// frame while open — see ConfirmOverlay.Render's own comment on why a
	// full replacement stands in for true on-top compositing here.
	if m.confirm != nil {
		return m.confirm.Render(m.Viewport)
	}
	if m.selectOverlay != nil {
		return m.selectOverlay.Render(m.Viewport)
	}
	if m.textPrompt != nil {
		return m.textPrompt.Render(m.Viewport)
	}
	if m.actionList != nil {
		return m.actionList.Render(m.Viewport)
	}
	if m.textOverlay != nil {
		return m.textOverlay.Render(m.Viewport)
	}
	if m.progressOverlay != nil {
		return m.progressOverlay.Render(m.Viewport)
	}
	frame, _, _ := viewWithState(m.presentationPanel(), m.Viewport, m.presentationState())
	return frame
}

func (m Model) presentationState() renderState {
	state := renderState{hover: m.hover, footerOffset: m.footerOffset}
	controls := ControlsFor(m.presentationPanel())
	if len(controls) == 0 || m.FocusIndex < 0 || m.FocusIndex >= len(controls) {
		return state
	}
	state.focus = &controlTarget{id: controls[m.FocusIndex].ID, variant: controls[m.FocusIndex].Variant}
	return state
}

// keepFocusedControlVisible adjusts the one footer viewport only when the
// newly focused control lies outside it. The renderer remains the authority
// for real row geometry, so wrapped text and future footer rows cannot make
// a parallel scrolling calculation disagree with the HitMap.
func (m Model) keepFocusedControlVisible(direction int) Model {
	state := m.presentationState()
	if state.focus == nil || direction == 0 {
		return m
	}
	for attempt := 0; attempt < 512; attempt++ {
		_, hm, metrics := viewWithState(m.presentationPanel(), m.Viewport, state)
		m.footerOffset = metrics.footerOffset
		if _, ok := hm.Rect(state.focus.id, state.focus.variant); ok {
			return m
		}
		next := metrics.footerOffset + direction
		if next < 0 || next > metrics.footerMax {
			return m
		}
		m.footerOffset = next
		state.footerOffset = next
	}
	return m
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
			m = m.keepFocusedControlVisible(1)
		case "focus_prev_row":
			m.FocusIndex = (m.FocusIndex - 1 + n) % n
			m = m.keepFocusedControlVisible(-1)
		}
		return m, nil

	case IntentBoundAction:
		if intent.Action == "refresh" {
			// Disparador 4, FR-038: available in all eight situations, and
			// the one trigger that is NEVER suppressed or degraded.
			return m.scheduleRead()
		}
		return m.activateBoundAction(intent.Action)

	case IntentCursorAction:
		// next/prev the review cursor (T073): j/k move the focused ROW
		// (IntentFocusMove above), n/p move the review's own cursor — two
		// different concepts, and ResolveKey already keeps n/p from
		// resolving at all outside a situation that has one
		// (hasReviewCursor in keys.go), which is what the reservation of
		// n/p exists to guarantee.
		return m.beginCursor(intent.Action)

	case IntentToggle:
		if intent.Toggle == "mouse_reporting" {
			m.Panel.MouseEnabled = !m.Panel.MouseEnabled
			if m.Panel.MouseEnabled {
				return m, tea.EnableMouseCellMotion
			}
			return m, tea.DisableMouse
		}
		return m, nil

	case IntentActivate:
		return m.activateControl(intent.Control, intent.Variant)

	case IntentOverlay:
		switch intent.Overlay {
		case "action_list":
			m.actionList = NewActionList(m.Panel.Situation, m.Panel.Busy, m.Panel.Readonly)
		case "entry_picker":
			m = m.openEntryPicker()
		}
		return m, nil
	}
	return m, nil
}

// handleMouse resolves a click against the base panel's own HitMap (T090):
// the control under the cursor is focused, and — matching contracts/
// tui-surface.md's "un clic hace exactamente lo mismo que su tecla" —
// activated through the SAME activateControl call Enter resolves to
// (keys.go's activateFocused), never a second, parallel path. Disabled
// controls still have a rectangle (so hovering/clicking finds them and
// focuses them, the same as tabbing onto one with the keyboard) but are
// never activated — mirroring activateFocused's own guard.
func (m Model) handleMouse(msg tea.MouseMsg) (tea.Model, tea.Cmd) {
	if !m.Panel.MouseEnabled {
		return m, nil
	}
	panel := m.presentationPanel()
	_, hm, metrics := viewWithState(panel, m.Viewport, m.presentationState())
	m.footerOffset = metrics.footerOffset
	if msg.Button == tea.MouseButtonWheelDown {
		m.footerOffset += 3
		if m.footerOffset > metrics.footerMax {
			m.footerOffset = metrics.footerMax
		}
		return m, nil
	}
	if msg.Button == tea.MouseButtonWheelUp {
		m.footerOffset -= 3
		if m.footerOffset < 0 {
			m.footerOffset = 0
		}
		return m, nil
	}
	if msg.Action == tea.MouseActionMotion {
		id, variant, ok := hm.At(msg.X, msg.Y)
		if !ok {
			m.hover = nil
			return m, nil
		}
		m.hover = &controlTarget{id: id, variant: variant}
		return m, nil
	}
	if msg.Action != tea.MouseActionPress {
		return m, nil
	}
	id, variant, ok := hm.At(msg.X, msg.Y)
	if !ok {
		m.hover = nil
		return m, nil
	}
	m.hover = &controlTarget{id: id, variant: variant}
	for i, c := range ControlsFor(panel) {
		if c.ID != id || c.Variant != variant {
			continue
		}
		m.FocusIndex = i
		if !c.Enabled {
			return m, nil
		}
		return m.activateControl(c.ID, c.Variant)
	}
	return m, nil
}

// toProjectInput adapts one host.ReadResult into domain.ProjectInput. It is
// the one seam between "what the host read" and "what the domain projects"
// — kept here (ui), not in host or domain, because it is neither I/O nor
// pure derivation: it is wiring between the two, exactly like Visual
// Studio's/JetBrains' host-side adapters.
func toProjectInput(r host.ReadResult, mouseEnabled, busy bool, statusLine string) domain.ProjectInput {
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
		WhyState:     r.WhyState,
		MouseEnabled: mouseEnabled,
		Busy:         busy,
		Stderr:       r.Stderr,
		StatusLine:   statusLine,
	}
}
