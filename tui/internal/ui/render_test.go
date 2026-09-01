package ui

import (
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
