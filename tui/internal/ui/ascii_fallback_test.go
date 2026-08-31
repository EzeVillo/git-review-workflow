package ui

import (
	"strings"
	"testing"
)

// TestASCIIFallbackLosesNoRow is T096's own gate: falling back to the
// ASCII glyph set changes GLYPHS, never the number of lines a situation
// draws. Checked across every one of the 11 panel_layout: situations (the
// same fixtures the golden files use), at both reference sizes, with
// Rows: 0 (unbounded) so the 55%-footer cap never confounds this with a
// truncation this test is not about (that is resize_test.go's own
// concern).
func TestASCIIFallbackLosesNoRow(t *testing.T) {
	for _, sit := range allFixtureSituations {
		panel := fixtureFor(sit)
		for _, sz := range goldenSizes {
			unicodeFrame, _ := View(panel, Viewport{Cols: sz.cols, Rows: 0, Color: false, ASCII: false})
			asciiFrame, _ := View(panel, Viewport{Cols: sz.cols, Rows: 0, Color: false, ASCII: true})

			unicodeLines := strings.Split(unicodeFrame, "\n")
			asciiLines := strings.Split(asciiFrame, "\n")
			if len(asciiLines) != len(unicodeLines) {
				t.Errorf("%s at %s: ASCII mode draws %d lines, Unicode mode draws %d — a row was lost falling back to ASCII",
					sit, sz.name, len(asciiLines), len(unicodeLines))
			}
		}
	}
}
