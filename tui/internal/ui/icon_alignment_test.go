package ui

import (
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

// TestIconColumnsAlignAcrossGlyphSets is T099's own gate: for every control
// drawn with an icon, switching between the Unicode and ASCII glyph sets
// (T096) must never move where that control's rectangle starts. A glyph
// that is not exactly one terminal cell wide (East Asian Width `Wide` or
// `Ambiguous` — the failure icons_test.go's own gate already rules out for
// the vocabulary itself) is exactly what would shift everything after it:
// one cell in this terminal, two in another, and the whole row's columns
// stop lining up with its neighbors. Checked with Rows: 0 (unbounded) so
// the 55%-footer cap (a separate concern, exercised by resize_test.go and
// the golden files) never hides a row this test wants to compare.
func TestIconColumnsAlignAcrossGlyphSets(t *testing.T) {
	situations := []domain.LayoutSituation{
		domain.LayoutNoReview,
		domain.LayoutReviewWalk,
		domain.LayoutReviewStep,
	}
	for _, sit := range situations {
		panel := fixtureFor(sit)
		for _, sz := range goldenSizes {
			_, hmUnicode := View(panel, Viewport{Cols: sz.cols, Rows: 0, Color: false, ASCII: false})
			_, hmASCII := View(panel, Viewport{Cols: sz.cols, Rows: 0, Color: false, ASCII: true})

			checked := 0
			for _, h := range hmUnicode.hits {
				rect, ok := hmASCII.Rect(h.id, h.variant)
				if !ok {
					t.Errorf("%s at %s: control %s/%s is drawn in Unicode mode but missing in ASCII mode", sit, sz.name, h.id, h.variant)
					continue
				}
				if rect.Row != h.rect.Row || rect.Col != h.rect.Col {
					t.Errorf("%s at %s: control %s/%s sits at (row %d, col %d) in Unicode but (row %d, col %d) in ASCII — a glyph-width mismatch shifted the column",
						sit, sz.name, h.id, h.variant, h.rect.Row, h.rect.Col, rect.Row, rect.Col)
				}
				checked++
			}
			if checked == 0 {
				t.Fatalf("%s at %s: no controls were drawn at all — fixture or View() regressed", sit, sz.name)
			}
		}
	}
}

// TestIconRowsStartAtColumnZero is the other half of "cae en la misma
// columna": every icon that OPENS its own footer row (a single-icon row, or
// the first of a pair — openDraft/openGuide/openWalkthrough/discardFixes/
// prev/next: render.go's iconRow/iconButton always start a fresh line)
// lands at column 0, at both reference sizes and both glyph sets.
func TestIconRowsStartAtColumnZero(t *testing.T) {
	leading := map[domain.ControlID]bool{
		"openDraft": true, "openGuide": true, "openWalkthrough": true,
		"discardFixes": true, "prev": true, "next": true,
	}
	for _, sit := range []domain.LayoutSituation{domain.LayoutNoReview, domain.LayoutReviewWalk, domain.LayoutReviewStep} {
		panel := fixtureFor(sit)
		for _, sz := range goldenSizes {
			for _, ascii := range []bool{false, true} {
				_, hm := View(panel, Viewport{Cols: sz.cols, Rows: 0, Color: false, ASCII: ascii})
				for _, h := range hm.hits {
					if !leading[h.id] {
						continue
					}
					if h.rect.Col != 0 {
						t.Errorf("%s at %s (ascii=%v): icon control %s/%s starts at column %d, want 0",
							sit, sz.name, ascii, h.id, h.variant, h.rect.Col)
					}
				}
			}
		}
	}
}

// TestPairedRowIconsShareOneColumn covers the trailing half of a two-icon
// row (discardDraft/discardGuide, drawn right after openDraft/openGuide on
// the SAME line): every row of that shape puts its second icon at the
// SAME column as every other row of that shape, in both glyph sets — a
// draft row and a guide row use the same leading hint ("open"), so their
// second icon has to land in the same place, or the footer's columns would
// visibly zigzag.
func TestPairedRowIconsShareOneColumn(t *testing.T) {
	trailing := map[domain.ControlID]bool{"discardDraft": true, "discardGuide": true}
	for _, sz := range goldenSizes {
		for _, ascii := range []bool{false, true} {
			panel := fixtureFor(domain.LayoutNoReview)
			_, hm := View(panel, Viewport{Cols: sz.cols, Rows: 0, Color: false, ASCII: ascii})
			col := -1
			for _, h := range hm.hits {
				if !trailing[h.id] {
					continue
				}
				if col == -1 {
					col = h.rect.Col
					continue
				}
				if h.rect.Col != col {
					t.Errorf("no-review at %s (ascii=%v): %s/%s is at column %d, want %d (every second-icon-in-a-row control)",
						sz.name, ascii, h.id, h.variant, h.rect.Col, col)
				}
			}
			if col == -1 {
				t.Fatalf("no-review at %s (ascii=%v): no paired-row icon controls were drawn at all", sz.name, ascii)
			}
		}
	}
}
