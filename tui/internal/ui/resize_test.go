package ui

import (
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// assertNoLineOverflowsOrSplitsMidColumn is T097's own gate, applied to one
// rendered frame: every line's displayed width (lipgloss.Width, which
// already accounts for ANSI escapes and wide runes) fits inside cols, and —
// because frame()/wrapLine() in render.go only ever join or drop WHOLE
// lines, never slice a rune sequence at an arbitrary byte offset — a line
// that does not fit is wrapped onto a following line rather than cut mid-
// glyph or mid-column.
func assertNoLineOverflowsOrSplitsMidColumn(t *testing.T, sit domain.LayoutSituation, cols int, frame string) {
	t.Helper()
	for i, line := range strings.Split(frame, "\n") {
		if w := lipgloss.Width(line); w > cols {
			t.Errorf("%s at %d cols: line %d is %d cells wide, overflows:\n%q", sit, cols, i, w, line)
		}
	}
}

// TestNoLineOverflowsAtReferenceSizes is T097's gate at the two reference
// sizes (FR-057): every situation, both sizes, both color modes -- a wide
// stderr line or a long branch name is exactly what would overflow if
// wrapLine's own wrapping ever regressed.
func TestNoLineOverflowsAtReferenceSizes(t *testing.T) {
	for _, sit := range allFixtureSituations {
		panel := fixtureFor(sit)
		for _, sz := range goldenSizes {
			frame, _ := View(panel, Viewport{Cols: sz.cols, Rows: sz.rows, Color: true})
			assertNoLineOverflowsOrSplitsMidColumn(t, sit, sz.cols, frame)
			frameNoColor, _ := View(panel, Viewport{Cols: sz.cols, Rows: sz.rows, Color: false})
			assertNoLineOverflowsOrSplitsMidColumn(t, sit, sz.cols, frameNoColor)
		}
	}
}

// belowMinimumSizes are panes smaller than anything this client claims to
// target (contracts/tui-surface.md names 80x24 as the smaller REFERENCE
// size, not a floor) -- one that is merely cramped and one that is
// pathologically small, to prove degradation is graceful all the way down
// rather than just slightly below 80x24.
var belowMinimumSizes = []goldenSize{
	{"40x10", 40, 10},
	{"10x3", 10, 3},
}

// TestBelowMinimumSizeDegradesInsteadOfBreaking is T097's third size: a
// pane smaller than the minimum drawable still renders something legible —
// no panic, no line wider than the viewport, no line count that could only
// come from slicing a rendered line in half — rather than corrupting the
// layout. "Legible" here is checked structurally (bounded width, non-empty
// output); a human judging whether 10 columns is USEFUL is a UX question
// this test does not attempt to settle.
func TestBelowMinimumSizeDegradesInsteadOfBreaking(t *testing.T) {
	for _, sit := range allFixtureSituations {
		panel := fixtureFor(sit)
		for _, sz := range belowMinimumSizes {
			frame, _ := View(panel, Viewport{Cols: sz.cols, Rows: sz.rows, Color: false})
			if frame == "" {
				t.Errorf("%s at %s: View produced an empty frame instead of degrading", sit, sz.name)
			}
			assertNoLineOverflowsOrSplitsMidColumn(t, sit, sz.cols, frame)
			lines := strings.Split(frame, "\n")
			if len(lines) > sz.rows {
				t.Errorf("%s at %s: frame has %d lines, want at most %d (vp.Rows)", sit, sz.name, len(lines), sz.rows)
			}
		}
	}
}

// TestLiveResizeRehashesLayoutAcrossSizes drives the resize the way a real
// terminal does: tea.WindowSizeMsg through Model.Update, at the reference
// sizes and then below the minimum, asserting View() keeps producing a
// legible frame at every step (T097: "tea.WindowSizeMsg rehace el layout
// sin corromperlo") -- not calling render.View directly, which the two
// tests above already exercise exhaustively.
func TestLiveResizeRehashesLayoutAcrossSizes(t *testing.T) {
	m := NewModel()
	sizes := []tea.WindowSizeMsg{
		{Width: 80, Height: 24},
		{Width: 120, Height: 40},
		{Width: 40, Height: 10},
		{Width: 10, Height: 3},
		{Width: 120, Height: 40}, // back up, to prove growing again also works
	}
	for _, sz := range sizes {
		next, _ := m.Update(sz)
		m = next.(Model)
		if m.Viewport.Cols != sz.Width || m.Viewport.Rows != sz.Height {
			t.Fatalf("after WindowSizeMsg%+v, Viewport = %+v", sz, m.Viewport)
		}
		frame := m.View()
		if frame == "" {
			t.Fatalf("at %dx%d, View() produced an empty frame", sz.Width, sz.Height)
		}
		for i, line := range strings.Split(frame, "\n") {
			if w := lipgloss.Width(line); w > sz.Width {
				t.Fatalf("at %dx%d, line %d is %d cells wide:\n%q", sz.Width, sz.Height, i, w, line)
			}
		}
	}
}
