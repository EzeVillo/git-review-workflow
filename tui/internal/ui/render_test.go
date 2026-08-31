package ui

import (
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

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
