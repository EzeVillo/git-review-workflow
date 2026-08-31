package ui

import "github.com/EzeVillo/git-review-workflow/tui/internal/domain"

// IntentKind classifies what a keypress or click resolved to. Nothing in
// this package invokes an action directly from a key handler — resolution
// only ever produces one of these, and Update() is the one place that turns
// an Intent into a tea.Cmd (T045, T048).
type IntentKind int

const (
	IntentNone IntentKind = iota
	IntentFocusMove
	IntentCursorAction
	IntentBoundAction
	IntentOverlay
	IntentToggle
	IntentActivate
	IntentQuit
)

// Intent is the typed result of resolving one KeyMsg/MouseMsg. Only the
// field matching Kind is meaningful.
type Intent struct {
	Kind IntentKind
	// Movement: "focus_next_row" | "focus_prev_row" (IntentFocusMove).
	Movement string
	// Action: the cursor action ("next"/"prev") or the bound action's id
	// ("refresh") — IntentCursorAction / IntentBoundAction.
	Action string
	// Overlay: which overlay to open (IntentOverlay).
	Overlay string
	// Toggle: which client-local toggle to flip (IntentToggle).
	Toggle string
	// Control / Variant: the focused control activated by Enter or a click
	// (IntentActivate) — Variant disambiguates a repeated id (openSupport).
	Control domain.ControlID
	Variant string
}

// quitKeys are handled directly rather than through domain/keymap.go: the
// canonical's `keymap:` block declares movement, cursor, actions, overlays
// and toggles, and deliberately nothing about quitting — every terminal
// program needs SOME way out, and ctrl+c specifically needs a handler at
// all, since bubbletea puts the terminal in raw mode and does not translate
// it to a signal on its own.
var quitKeys = map[string]bool{"ctrl+c": true, "q": true}

// ResolveKey turns one key's string form (tea.KeyMsg.String()) into an
// Intent, resolved from domain/keymap.go (T048) — the same map the key bar
// is drawn from, so a key that exists and is not shown is impossible by
// construction (KeyBarFor below reads the identical tables).
func ResolveKey(key string, m Model) Intent {
	if quitKeys[key] {
		return Intent{Kind: IntentQuit}
	}
	if key == "enter" {
		return activateFocused(m)
	}
	if move, ok := domain.MovementFor(key); ok {
		return Intent{Kind: IntentFocusMove, Movement: move}
	}
	// Cursor keys (n/p) only resolve inside a situation that actually has a
	// review cursor — pressing them anywhere else (finish-conflict included,
	// User Story 3 scenario 4) must not silently invoke next/prev.
	if action, ok := domain.CursorActionFor(key); ok && hasReviewCursor(m.Panel) {
		return Intent{Kind: IntentCursorAction, Action: action}
	}
	if action, ok := domain.BoundActionFor(key); ok {
		return Intent{Kind: IntentBoundAction, Action: action}
	}
	if toggle, ok := domain.ToggleFor(key); ok {
		return Intent{Kind: IntentToggle, Toggle: toggle}
	}
	if overlay, ok := domain.OverlayFor(key); ok {
		return Intent{Kind: IntentOverlay, Overlay: overlay}
	}
	return Intent{Kind: IntentNone}
}

// hasReviewCursor reports whether m's situation is one of the two that walk
// a review with next/prev (review-walk, review-step) — the cursor reserved
// for n/p, distinct from moving focus in the list (j/k).
func hasReviewCursor(m domain.PanelModel) bool {
	sit := domain.LayoutSituationFor(m)
	return sit == domain.LayoutReviewWalk || sit == domain.LayoutReviewStep
}

// activateFocused resolves Enter against the currently focused control, per
// ControlsFor(m.Panel) — the same list render.go draws buttons from.
// Activating a disabled control (prev at the first entry, say) or activating
// with nothing focusable at all resolves to IntentNone: a safe no-op, never
// a crash and never a fabricated action.
func activateFocused(m Model) Intent {
	cs := ControlsFor(m.Panel)
	if len(cs) == 0 {
		return Intent{Kind: IntentNone}
	}
	idx := m.FocusIndex
	if idx < 0 {
		idx = 0
	}
	if idx >= len(cs) {
		idx = len(cs) - 1
	}
	c := cs[idx]
	if !c.Enabled {
		return Intent{Kind: IntentNone}
	}
	return Intent{Kind: IntentActivate, Control: c.ID, Variant: c.Variant}
}

// KeyBarItem is one entry of the footer key bar: the key that runs it
// (String() form of a bubbletea key) and its label.
type KeyBarItem struct {
	Key   string
	Label string
}

// KeyBarFor builds the footer key bar for m, reading the SAME
// domain/keymap.go tables ResolveKey reads (never a hardcoded parallel
// list): a key that resolves to something must appear here, and a key shown
// here must resolve to something. Cursor keys (n/p) are included only when
// hasReviewCursor(m) — this is the concrete form of the finish-conflict rule
// in contracts/tui-surface.md: "the bar reflects the situation, not a fixed
// set".
func KeyBarFor(m domain.PanelModel) []KeyBarItem {
	var bar []KeyBarItem
	if len(ControlsFor(m)) > 0 {
		bar = append(bar,
			KeyBarItem{Key: domain.KeymapMovement[0].Keys[0], Label: "up"},
			KeyBarItem{Key: domain.KeymapMovement[1].Keys[0], Label: "down"},
			KeyBarItem{Key: "enter", Label: "select"},
		)
	}
	if hasReviewCursor(m) {
		bar = append(bar,
			KeyBarItem{Key: domain.KeymapCursor[0].Keys[0], Label: "next"},
			KeyBarItem{Key: domain.KeymapCursor[1].Keys[0], Label: "prev"},
		)
	}
	for _, entry := range domain.KeymapActions {
		switch entry.Action {
		case "refresh":
			bar = append(bar, KeyBarItem{Key: entry.Keys[0], Label: "refresh"})
		case "finishReview":
			// requires_not_readonly in the canonical: a read-only compare
			// review has nothing to finish (finishReview.ts's own defensive
			// check has the same shape).
			if m.Situation == domain.SituationReview && !m.Readonly {
				bar = append(bar, KeyBarItem{Key: entry.Keys[0], Label: "finish"})
			}
		case "saveReview":
			if m.Situation == domain.SituationReview {
				bar = append(bar, KeyBarItem{Key: entry.Keys[0], Label: "save"})
			}
		case "abortReview":
			if m.Situation == domain.SituationReview || m.Situation == domain.SituationFinishConflict {
				bar = append(bar, KeyBarItem{Key: entry.Keys[0], Label: "cancel"})
			}
		}
	}
	for _, entry := range domain.KeymapOverlays {
		switch entry.Opens {
		case "action_list":
			// Always available: PaletteActionsFor's own "refresh" row alone
			// covers all eight situations (its own situations: list is the
			// same eight this client ever draws), so the palette this key
			// opens is never empty.
			bar = append(bar, KeyBarItem{Key: entry.Keys[0], Label: "actions"})
		case "entry_picker":
			// goToEntry's own situations: [review, finish-conflict], plus
			// something to pick from — the same "only when meaningful"
			// refinement KeymapActions' own finish/save/abort already add
			// below on top of raw resolution (BoundActionFor, like
			// OverlayFor, does not gate by situation either; KeyBarFor is
			// where that extra layer has always lived).
			hasEntries := m.Situation == domain.SituationReview || m.Situation == domain.SituationFinishConflict
			if hasEntries && m.EntryPickerRows != "" {
				bar = append(bar, KeyBarItem{Key: entry.Keys[0], Label: "entries"})
			}
		}
	}
	for _, entry := range domain.KeymapToggles {
		if entry.Toggles == "mouse_reporting" {
			// U+00A0 (non-breaking space), not a plain " ": the key bar is
			// one long string wrapLine() wraps by WIDTH, treating each
			// space as an independent break opportunity — a plain space
			// here risked the wrap point landing inside this one label,
			// splitting "mouse" onto one line and "on"/"off" onto the
			// next. A non-breaking space reads identically on screen and
			// keeps the two words moving together.
			label := "mouse off"
			if !m.MouseEnabled {
				label = "mouse on"
			}
			bar = append(bar, KeyBarItem{Key: entry.Keys[0], Label: label})
		}
	}
	bar = append(bar, KeyBarItem{Key: "q", Label: "quit"})
	return bar
}
