package ui

import (
	"fmt"
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	tea "github.com/charmbracelet/bubbletea"
)

// Breaking the focus marker must make this test fail: the next keyboard
// control has to be identifiable before Enter acts on it, including without
// terminal color.
func TestFocusMovementChangesRenderedControl(t *testing.T) {
	m := Model{
		Panel:    fixtureFor(domain.LayoutNoReview),
		Viewport: Viewport{Cols: 80, Rows: 24, Color: false},
	}
	before := m.View()
	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'j'}})
	after := updated.(Model).View()
	if before == after {
		t.Fatal("moving keyboard focus must visibly mark a different control")
	}
}

// The finish-pending frame must tell reviewers that they can commit and push
// now while keeping the remaining finish cleanup and undo choices explicit.
func TestFinishPendingRendersClarifiedFinishActions(t *testing.T) {
	m := Model{
		Panel:    fixtureFor(domain.LayoutFinishPending),
		Viewport: Viewport{Cols: 80, Rows: 24, Color: false},
	}
	rendered := m.View()
	for _, want := range []string{
		"Commit and push them from Source Control. You can still undo this finish.",
		"[ Keep edits & remove Undo ]",
		"[ Undo Finish ]",
	} {
		if !strings.Contains(rendered, want) {
			t.Fatalf("finish-pending frame did not render %q:\n%s", want, rendered)
		}
	}
}

// Finish-conflict keeps its compact recovery actions; the clarified pending
// finish action is not shared with this separate recovery screen.
func TestFinishConflictKeepsCompactUndoAction(t *testing.T) {
	m := Model{
		Panel:    fixtureFor(domain.LayoutFinishConflict),
		Viewport: Viewport{Cols: 80, Rows: 24, Color: false},
	}
	if rendered := m.View(); !strings.Contains(rendered, "[ Undo ]") {
		t.Fatalf("finish-conflict frame did not retain its compact Undo action:\n%s", rendered)
	}
}

// Breaking focus-following scroll must make the last visible action
// unreachable again: j/k owns both focus and the one footer viewport.
func TestFooterFocusScrollsIntoView(t *testing.T) {
	m := Model{
		Panel:    fixtureFor(domain.LayoutNoReview),
		Viewport: Viewport{Cols: 80, Rows: 24, Color: false},
	}
	controls := ControlsFor(m.Panel)
	if len(controls) == 0 {
		t.Fatal("no-review fixture needs controls")
	}
	for range controls[:len(controls)-1] {
		updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'j'}})
		m = updated.(Model)
	}
	if got := m.View(); !strings.Contains(got, domain.ReportABugLabel) {
		t.Fatalf("focused final footer control must be visible at 80x24:\n%s", got)
	}
	intent := ResolveKey("enter", m)
	if intent.Kind != IntentActivate || intent.Control != "openSupport" || intent.Variant != "bug" {
		t.Fatalf("Enter = %+v, want the visible Report a bug control", intent)
	}
}

// Breaking wheel handling must make the compact footer stay frozen. The wheel
// moves the exact same scroll range used by focus, not a second per-section
// offset.
func TestFooterMouseWheelScrollsSharedViewport(t *testing.T) {
	panel := fixtureFor(domain.LayoutNoReview)
	panel.MouseEnabled = true
	m := Model{
		Panel:    panel,
		Viewport: Viewport{Cols: 80, Rows: 24, Color: false},
	}
	before := m.View()
	updated, _ := m.Update(tea.MouseMsg{Action: tea.MouseActionPress, Button: tea.MouseButtonWheelDown})
	after := updated.(Model).View()
	if before == after {
		t.Fatal("mouse wheel must move the same compact footer viewport")
	}
	if !strings.Contains(after, "[#") {
		t.Fatalf("the shared footer viewport must expose its one scrollbar:\n%s", after)
	}
}

// Hover is presentation-only, but it must still identify the same concrete
// control the next click would resolve through the HitMap.
func TestMouseMotionMarksHoveredControl(t *testing.T) {
	panel := fixtureFor(domain.LayoutNoReview)
	panel.MouseEnabled = true
	vp := Viewport{Cols: 80, Rows: 24, Color: false}
	_, hm := View(panel, vp)
	control := ControlsFor(panel)[0]
	rect, ok := hm.Rect(control.ID, control.Variant)
	if !ok {
		t.Fatalf("fixture has no rectangle for %s/%s", control.ID, control.Variant)
	}
	m := Model{Panel: panel, Viewport: vp, FocusIndex: -1}
	updated, _ := m.Update(tea.MouseMsg{X: rect.Col, Y: rect.Row, Action: tea.MouseActionMotion})
	if got := updated.(Model).View(); !strings.Contains(got, "~") {
		t.Fatalf("hovered control must be visibly marked:\n%s", got)
	}
}

// NO_COLOR / -nocolor means ZERO escape sequences, not merely dimmer ones.
func TestNoColorProducesNoEscapeSequences(t *testing.T) {
	for _, sit := range domain.AllLayoutSituations {
		frame, _ := View(fixtureFor(sit), Viewport{Cols: 80, Rows: 24, Color: false})
		if strings.ContainsRune(frame, '\x1b') {
			t.Errorf("%s: NO_COLOR frame still contains an escape sequence:\n%s", sit, frame)
		}
	}
}

// The default (color) mode is expected to differ from the no-color one for
// at least one situation with a styled control — otherwise "Color: true"
// would be a no-op and TestNoColorProducesNoEscapeSequences would be
// vacuous.
func TestColorModeActuallyAddsEscapeSequences(t *testing.T) {
	frame, _ := View(fixtureFor(domain.LayoutNoReview), Viewport{Cols: 80, Rows: 24, Color: true})
	if !strings.ContainsRune(frame, '\x1b') {
		t.Fatal("Color: true produced no escape sequences at all — the profile is not being applied")
	}
}

func TestASCIIModeUsesASCIIGlyphs(t *testing.T) {
	frame, _ := View(fixtureFor(domain.LayoutReviewWalk), Viewport{Cols: 80, Rows: 24, ASCII: true})
	if strings.ContainsRune(frame, '‹') || strings.ContainsRune(frame, '›') {
		t.Fatalf("ASCII mode must not draw the Unicode prev/next glyphs:\n%s", frame)
	}
	if !strings.Contains(frame, "[<]") || !strings.Contains(frame, "[>]") {
		t.Fatalf("ASCII mode must draw the ASCII prev/next glyphs:\n%s", frame)
	}
}

func TestUnicodeModeUsesUnicodeGlyphs(t *testing.T) {
	frame, _ := View(fixtureFor(domain.LayoutReviewWalk), Viewport{Cols: 80, Rows: 24, ASCII: false})
	if !strings.ContainsRune(frame, '‹') || !strings.ContainsRune(frame, '›') {
		t.Fatalf("default mode must draw the Unicode prev/next glyphs:\n%s", frame)
	}
}

// The HitMap resolves a click to the same control a keyboard Enter would
// activate at that row — clicking is not a second, independently-verified
// path to the same button, it is literally the same rectangle.
func TestHitMapResolvesMouseClicksToDrawnControls(t *testing.T) {
	m := fixtureFor(domain.LayoutFinishPending)
	_, hm := View(m, Viewport{Cols: 80, Rows: 24, Color: false})
	controls := ControlsFor(m)
	if len(controls) == 0 {
		t.Fatal("finish-pending must draw at least one control")
	}
	for _, c := range controls {
		row, ok := hm.ControlRow(c.ID, c.Variant)
		if !ok {
			t.Fatalf("HitMap has no rectangle for %s/%s", c.ID, c.Variant)
		}
		id, variant, ok := hm.At(0, row)
		if !ok || id != c.ID || variant != c.Variant {
			t.Fatalf("clicking at (0,%d) resolved to (%s,%s), want (%s,%s)", row, id, variant, c.ID, c.Variant)
		}
	}
}

func TestFixedTailRemapsAndClipsHitMapAfterWrapping(t *testing.T) {
	b := newBuilder(Viewport{Cols: 10, Rows: 5}, renderState{})
	b.text(strings.Repeat("x", 20))
	b.button("startReview", "", "Start", b.st.primary, true)
	b.frameWithTail([]string{"", "q:quit"})
	rect, ok := b.hm.Rect("startReview", "")
	if !ok || rect.Row != 2 {
		t.Fatalf("wrapped control rect = %+v, ok=%v; want row 2", rect, ok)
	}

	clipped := newBuilder(Viewport{Cols: 10, Rows: 4}, renderState{})
	clipped.text(strings.Repeat("x", 20))
	clipped.button("startReview", "", "Start", clipped.st.primary, true)
	clipped.frameWithTail([]string{"", "q:quit"})
	if _, ok := clipped.hm.Rect("startReview", ""); ok {
		t.Fatal("control clipped by wrapping retained a stale hit rectangle")
	}
}

func TestInteractiveRowsHardWrapInTheSameGeometryAsTheirHitMap(t *testing.T) {
	b := newBuilder(Viewport{Cols: 20, Rows: 5}, renderState{})
	b.buttonRow(
		rowButton{id: "continueReview", label: "First action", style: b.st.primary, enabled: true},
		rowButton{id: "discardInventory", label: "Second action", style: b.st.secondary, enabled: true},
	)
	frame := b.frameWithTail(nil)
	lines := strings.Split(frame, "\n")
	if len(lines) != 2 || lines[0] != "[ First action ]  [ " || lines[1] != "Second action ]" {
		t.Fatalf("interactive row did not hard-wrap predictably: %#v", lines)
	}
	var second []Rect
	for _, h := range b.hm.hits {
		if h.id == "discardInventory" {
			second = append(second, h.rect)
		}
	}
	if len(second) != 2 || second[0] != (Rect{Row: 0, Col: 18, Width: 2, Height: 1}) || second[1] != (Rect{Row: 1, Col: 0, Width: 15, Height: 1}) {
		t.Fatalf("second control hit segments = %+v", second)
	}
}

func TestBusyBuilderStylesNominallyEnabledBodyControlsAsDisabled(t *testing.T) {
	b := newBuilder(Viewport{Cols: 80, Rows: 24, Color: true}, renderState{})
	b.busy = true
	b.button("openEntry", "", domain.FileLabel, b.st.secondary, true)
	want := "[ " + b.st.disabled.Render(domain.FileLabel) + " ]"
	if b.lines[0] != want {
		t.Fatalf("busy control rendered as enabled: %q, want %q", b.lines[0], want)
	}
}

func TestBusyBuilderStylesIconRowsAndInstallCopyAsDisabled(t *testing.T) {
	b := newBuilder(Viewport{Cols: 80, Rows: 24, Color: true}, renderState{})
	b.busy = true
	b.iconRow(rowIcon{id: "openGuide", icon: domain.IconFile, hint: "open", enabled: true})
	wantIcon := "[" + glyph(b.vp, domain.IconFile) + "] " + b.st.disabled.Render("open")
	if b.lines[0] != wantIcon {
		t.Fatalf("busy icon row rendered as enabled: %q, want %q", b.lines[0], wantIcon)
	}

	install := newBuilder(Viewport{Cols: 80, Rows: 24, Color: true}, renderState{})
	install.busy = true
	renderCliInstall(install, "title", "hint", "npm install tool", "")
	if got := strings.Join(install.lines, "\n"); !strings.Contains(got, install.st.disabled.Render("npm install tool")) {
		t.Fatalf("busy install copy rendered as enabled:\n%s", got)
	}
}

// Every icon this client uses is exactly one terminal cell wide in both
// glyph sets (contracts/tui-surface.md § Iconos) — checked with the same
// table icons_test.go already validates the vocabulary against, not a
// hand-picked list.
func TestIconsRenderAtExactlyOneCellWide(t *testing.T) {
	for name, icon := range domain.IconVocabulary {
		if !domain.IsSafeTerminalGlyph(icon.Unicode) {
			t.Errorf("icon %q Unicode glyph %q is not a safe single-width terminal glyph", name, icon.Unicode)
		}
		if !domain.IsASCIIGlyph(icon.ASCII) {
			t.Errorf("icon %q ASCII glyph %q is not a plain printable ASCII character", name, icon.ASCII)
		}
	}
}

func TestFixedTailKeepsFailureAndKeyBarVisibleBelowLongInventory(t *testing.T) {
	var rows []string
	for i := 0; i < 12; i++ {
		rows = append(rows, domain.FooterField(
			fmt.Sprintf("review-saved/feature-%02d", i), "1", "0", "0", "1", "walk . 1/3",
		))
	}
	panel := domain.PanelModel{
		Situation:     domain.SituationNoReview,
		HasReviews:    true,
		InventoryRows: strings.Join(rows, "\n"),
		StatusLine:    "error: you have local changes; commit or stash them first",
		MouseEnabled:  true,
	}
	for _, vp := range []Viewport{{Cols: 80, Rows: 24}, {Cols: 120, Rows: 40}} {
		frame, _ := View(panel, vp)
		if !strings.Contains(frame, panel.StatusLine) {
			t.Fatalf("%dx%d clipped the failure:\n%s", vp.Cols, vp.Rows, frame)
		}
		if !strings.Contains(frame, "q:quit") {
			t.Fatalf("%dx%d clipped the key bar:\n%s", vp.Cols, vp.Rows, frame)
		}
		if lines := strings.Count(frame, "\n") + 1; lines > vp.Rows {
			t.Fatalf("%dx%d rendered %d rows", vp.Cols, vp.Rows, lines)
		}
	}
}
