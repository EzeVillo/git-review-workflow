package domain

import "testing"

func TestUnquotePathLeavesPlainPathsUntouched(t *testing.T) {
	for _, raw := range []string{"file.txt", "src/main.go", "a b/c.txt", ""} {
		if got := UnquotePath(raw); got != raw {
			t.Errorf("UnquotePath(%q) = %q, want unchanged", raw, got)
		}
	}
}

func TestUnquotePathHandlesEscapedTabAndQuote(t *testing.T) {
	cases := map[string]string{
		`"con\ttab.txt"`:    "con\ttab.txt",
		`"say \"hi\".txt"`:  `say "hi".txt`,
		`"back\\slash.txt"`: `back\slash.txt`,
	}
	for raw, want := range cases {
		if got := UnquotePath(raw); got != want {
			t.Errorf("UnquotePath(%q) = %q, want %q", raw, got, want)
		}
	}
}

// A non-ASCII path is what git's default core.quotePath actually produces:
// each byte of the multi-byte UTF-8 sequence as its own three-digit octal
// escape, concatenated. "año.txt" is 'a', then U+00F1 (0xC3 0xB1 in UTF-8),
// then "o.txt".
func TestUnquotePathReassemblesMultiByteOctalEscapes(t *testing.T) {
	raw := `"a\303\261o.txt"`
	want := "año.txt"
	if got := UnquotePath(raw); got != want {
		t.Errorf("UnquotePath(%q) = %q, want %q", raw, got, want)
	}
}

func TestUnquotePathHostileBytes(t *testing.T) {
	// A NUL byte inside a quoted path (octal \000), and a lone backslash right
	// at the closing quote — both edge cases a naive index-by-2 walker could
	// step past the end of the string on.
	if got := UnquotePath(`"a\000b.txt"`); got != "a\x00b.txt" {
		t.Errorf("NUL byte: got %q", got)
	}
	if got := UnquotePath(`"trailing\\"`); got != `trailing\` {
		t.Errorf("trailing backslash: got %q", got)
	}
}

// PathRef does not stop a caller from swapping Raw and Display at runtime —
// see the doc comment on PathRef for why that is enforced by convention and
// by there being no third way to read a path out of porcelain, not by a
// runtime check. What this test locks in is the precondition that makes the
// convention meaningful: for any path that actually needed quoting, Raw and
// Display are genuinely different strings, so confusing them is observable
// and not an accidental no-op.
func TestPathRefRawAndDisplayDivergeWhenQuoted(t *testing.T) {
	ref := NewPathRef(`"a\303\261o.txt"`)
	if ref.Raw != `"a\303\261o.txt"` {
		t.Errorf("Raw must be exactly what porcelain printed, got %q", ref.Raw)
	}
	if ref.Display != "año.txt" {
		t.Errorf("Display must be the de-quoted form, got %q", ref.Display)
	}
	if ref.Raw == ref.Display {
		t.Fatal("Raw and Display must diverge for a quoted path, or mixing them up is invisible")
	}
}

func TestPathRefRawAndDisplayMatchWhenUnquoted(t *testing.T) {
	ref := NewPathRef("plain.txt")
	if ref.Raw != "plain.txt" || ref.Display != "plain.txt" {
		t.Errorf("plain path should be identical on both sides, got Raw=%q Display=%q", ref.Raw, ref.Display)
	}
}
