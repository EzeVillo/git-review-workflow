package main

import (
	"os"
	"testing"
)

// clearLocaleEnv resets the three POSIX locale variables plus the ASCII
// override so each test below starts from a known, fully-unset state --
// the developer machine or CI runner's own LANG/LC_* would otherwise leak
// into these tests non-deterministically.
func clearLocaleEnv(t *testing.T) {
	t.Helper()
	for _, name := range []string{"LC_ALL", "LC_CTYPE", "LANG", asciiFallbackEnv} {
		t.Setenv(name, "")
	}
}

// unsetEnv makes name genuinely ABSENT (os.LookupEnv-false) for the
// duration of the test, restoring whatever it was before on cleanup --
// t.Setenv alone cannot express "absent" for a var like NO_COLOR whose own
// production check (noColorRequested) is presence-based, not value-based.
func unsetEnv(t *testing.T, name string) {
	t.Helper()
	old, had := os.LookupEnv(name)
	if err := os.Unsetenv(name); err != nil {
		t.Fatalf("unsetting %s: %v", name, err)
	}
	t.Cleanup(func() {
		if had {
			os.Setenv(name, old)
		}
	})
}

// T096: GIT_REVIEW_UI_ASCII=1 forces the fallback regardless of locale --
// the one thing that makes the -ascii golden set (T050) reproducible
// without a real non-UTF-8 terminal to generate it from.
func TestAsciiFallbackEnvOverrideForcesASCIIRegardlessOfLocale(t *testing.T) {
	clearLocaleEnv(t)
	t.Setenv(asciiFallbackEnv, "1")
	t.Setenv("LC_ALL", "en_US.UTF-8")
	if !asciiFallback() {
		t.Fatal("GIT_REVIEW_UI_ASCII=1 must force ASCII even with a UTF-8 locale")
	}
}

// NO_COLOR must never drive this decision (contracts/tui-surface.md §
// Iconos): it is a color switch, not a drawing one. Checked structurally,
// not by reading the real (uncontrollable, possibly non-UTF-8) console
// codepage of whatever machine runs this test: decideASCII's own signature
// has no color parameter at all, so a UTF-8 locale plus a UTF-8 codepage
// with NO_COLOR set still comes back false.
func TestAsciiFallbackIgnoresNOCOLOR(t *testing.T) {
	t.Setenv("NO_COLOR", "1")
	utf8Codepage := func() (uint32, bool) { return 65001, true }
	if decideASCII(false, false, utf8Codepage) {
		t.Fatal("NO_COLOR must never trigger the ASCII glyph fallback")
	}
}

func TestDecideASCIIForcedWins(t *testing.T) {
	if !decideASCII(true, false, func() (uint32, bool) { return 65001, true }) {
		t.Fatal("the GIT_REVIEW_UI_ASCII override must win regardless of locale/codepage")
	}
}

func TestDecideASCIIFallsBackToCodepage(t *testing.T) {
	if !decideASCII(false, false, func() (uint32, bool) { return 850, true }) {
		t.Fatal("a non-UTF-8 console codepage must trigger ASCII when the locale said nothing")
	}
	if decideASCII(false, false, func() (uint32, bool) { return 65001, true }) {
		t.Fatal("codepage 65001 (UTF-8) must not trigger ASCII")
	}
	if decideASCII(false, false, func() (uint32, bool) { return 0, false }) {
		t.Fatal("an unavailable codepage (ok=false) must not, on its own, trigger ASCII")
	}
}

func TestLocaleSaysNonUTF8ChecksLCAllFirst(t *testing.T) {
	clearLocaleEnv(t)
	t.Setenv("LC_ALL", "C")
	t.Setenv("LC_CTYPE", "en_US.UTF-8")
	t.Setenv("LANG", "en_US.UTF-8")
	if !localeSaysNonUTF8() {
		t.Fatal("LC_ALL=C must win over a UTF-8 LC_CTYPE/LANG (POSIX precedence)")
	}
}

func TestLocaleSaysNonUTF8FallsThroughToLCCTYPE(t *testing.T) {
	clearLocaleEnv(t)
	t.Setenv("LC_CTYPE", "POSIX")
	t.Setenv("LANG", "en_US.UTF-8")
	if !localeSaysNonUTF8() {
		t.Fatal("an unset LC_ALL must fall through to a non-UTF-8 LC_CTYPE")
	}
}

func TestLocaleSaysNonUTF8FallsThroughToLANG(t *testing.T) {
	clearLocaleEnv(t)
	t.Setenv("LANG", "en_US.UTF-8")
	if localeSaysNonUTF8() {
		t.Fatal("a UTF-8 LANG with nothing else set must not trigger ASCII")
	}
}

func TestLocaleSaysNonUTF8WithNothingSetIsNotASignal(t *testing.T) {
	clearLocaleEnv(t)
	if localeSaysNonUTF8() {
		t.Fatal("no locale variable set at all must not, on its own, trigger ASCII")
	}
}

func TestLocaleSaysNonUTF8AcceptsUTF8WithoutHyphen(t *testing.T) {
	clearLocaleEnv(t)
	t.Setenv("LANG", "en_US.utf8")
	if localeSaysNonUTF8() {
		t.Fatal("the hyphen-less UTF8 spelling must count as UTF-8 too")
	}
}

// NO_COLOR's presence, not its value, is what matters (https://no-color.org)
// -- "NO_COLOR=" and "NO_COLOR=0" both still mean "no color".
func TestNoColorRequestedIsPresenceNotValue(t *testing.T) {
	t.Setenv("NO_COLOR", "")
	if !noColorRequested() {
		t.Fatal(`NO_COLOR="" must still count as present, per no-color.org`)
	}
}

func TestNoColorNotRequestedWhenAbsent(t *testing.T) {
	unsetEnv(t, "NO_COLOR")
	if noColorRequested() {
		t.Fatal("an absent NO_COLOR must not be reported as requested")
	}
}
