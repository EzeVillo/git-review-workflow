package domain

import (
	"strings"
	"testing"
)

func TestIconVocabularyHasExactlyTheFiveCanonicalNames(t *testing.T) {
	if len(IconVocabulary) != 5 {
		t.Fatalf("expected 5 icons, got %d", len(IconVocabulary))
	}
	for _, name := range []IconName{IconPrev, IconNext, IconFile, IconTrash, IconDiff} {
		if _, ok := IconVocabulary[name]; !ok {
			t.Errorf("IconVocabulary is missing %q", name)
		}
	}
}

func TestIconVocabularyMatchesCanonical(t *testing.T) {
	yaml := readCanonicalYAML(t)
	if !strings.Contains(yaml, "icon_vocabulary: [prev, next, file, trash, diff]") {
		t.Fatal("canonical icon_vocabulary must be exactly [prev, next, file, trash, diff]")
	}
}

// Gate 1: every Unicode glyph in the vocabulary occupies exactly one
// terminal cell.
func TestEveryUnicodeGlyphIsSafe(t *testing.T) {
	for name, icon := range IconVocabulary {
		if !IsSafeTerminalGlyph(icon.Unicode) {
			t.Errorf("icon %q: %q (U+%04X) is not Narrow/Neutral", name, icon.Unicode, icon.Unicode)
		}
	}
}

// Gate 2: every ASCII fallback is a plain printable character.
func TestEveryASCIIGlyphIsPrintableASCII(t *testing.T) {
	for name, icon := range IconVocabulary {
		if !IsASCIIGlyph(icon.ASCII) {
			t.Errorf("icon %q: ASCII fallback %q is outside U+0020..U+007E", name, icon.ASCII)
		}
	}
}

// The table must actually classify things, not default everything to safe:
// a CJK character is Wide, and the arrow pair naive intuition reaches for
// first (← U+2190, → U+2192) is Ambiguous, not Narrow — this is exactly the
// trap contracts/tui-surface.md warns about ("prohibir emoji no alcanza"),
// and why prev/next use the angle quotation marks instead.
func TestWidthTableActuallyRejectsUnsafeGlyphs(t *testing.T) {
	unsafe := []rune{
		'中', // U+4E2D, a CJK ideograph: Wide
		'←', // U+2190, LEFTWARDS ARROW: Ambiguous
		'→', // U+2192, RIGHTWARDS ARROW: Ambiguous
		'≡', // U+2261, IDENTICAL TO: Ambiguous
		'▶', // U+25B6, BLACK RIGHT-POINTING TRIANGLE: Ambiguous
		'😀', // U+1F600: Wide (also emoji, doubly disqualified)
	}
	for _, r := range unsafe {
		if IsSafeTerminalGlyph(r) {
			t.Errorf("%q (U+%04X) must not be classified as a safe one-cell glyph", r, r)
		}
	}
}

func TestWidthTableAcceptsOrdinaryLatinAndTheChosenGlyphs(t *testing.T) {
	safe := []rune{'a', 'Z', '0', '!', '‹', '›', '☐', '✗', '≷'}
	for _, r := range safe {
		if !IsSafeTerminalGlyph(r) {
			t.Errorf("%q (U+%04X) should classify as a safe one-cell glyph", r, r)
		}
	}
}

func TestIsASCIIGlyphBoundaries(t *testing.T) {
	if !IsASCIIGlyph(0x20) || !IsASCIIGlyph(0x7E) {
		t.Error("0x20 and 0x7E are the inclusive boundaries and must be accepted")
	}
	if IsASCIIGlyph(0x1F) || IsASCIIGlyph(0x7F) {
		t.Error("bytes outside 0x20..0x7E must be rejected")
	}
}
