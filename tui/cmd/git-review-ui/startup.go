package main

import (
	"os"
	"strings"
)

// asciiFallbackEnv is the support override (contracts/tui-surface.md §
// Iconos): forcing it is what makes the golden `-ascii` set possible (T050)
// without needing a real non-UTF-8 terminal to generate it from.
const asciiFallbackEnv = "GIT_REVIEW_UI_ASCII"

// asciiFallback decides the glyph set at STARTUP ONLY (T096): a one-shot
// call from main(), never re-evaluated while the program runs -- unlike
// Color (T095), there is no live trigger for this at all, the same way
// none of the other three clients watch a live locale/codepage change
// either.
//
// NO_COLOR never enters this decision, and that is structural, not just
// documented: decideASCII's own signature below has no color input at all
// (contracts/tui-surface.md § Iconos) -- a terminal that sets NO_COLOR
// should not also lose its box glyphs, and a terminal stuck on a legacy
// codepage should not also lose color.
func asciiFallback() bool {
	return decideASCII(os.Getenv(asciiFallbackEnv) == "1", localeSaysNonUTF8(), consoleCodepage)
}

// decideASCII is asciiFallback's OS-state-free core: forced (the
// GIT_REVIEW_UI_ASCII override) and localeNonUTF8 (already resolved) are
// plain bools, and codepage is a function rather than an already-resolved
// value so a test can hand it a fixed, fake console codepage instead of
// asking the real one this process may or may not even have.
func decideASCII(forced, localeNonUTF8 bool, codepage func() (uint32, bool)) bool {
	if forced {
		return true
	}
	if localeNonUTF8 {
		return true
	}
	if cp, ok := codepage(); ok && cp != 65001 {
		return true
	}
	return false
}

// localeSaysNonUTF8 checks LC_ALL, then LC_CTYPE, then LANG -- POSIX's own
// precedence order -- and stops at the FIRST one that is actually set: an
// explicit LC_ALL=C wins over an ignored LANG=en_US.UTF-8, exactly as it
// would for any other locale-aware program. Nothing set at all is not a
// signal either way (most Windows consoles never set any of the three), so
// asciiFallback's own codepage check gets the final word there.
func localeSaysNonUTF8() bool {
	for _, name := range []string{"LC_ALL", "LC_CTYPE", "LANG"} {
		v := os.Getenv(name)
		if v == "" {
			continue
		}
		upper := strings.ToUpper(v)
		return !strings.Contains(upper, "UTF-8") && !strings.Contains(upper, "UTF8")
	}
	return false
}

// noColorRequested implements https://no-color.org (T095): NO_COLOR's mere
// PRESENCE disables color, regardless of its value -- "NO_COLOR=" and
// "NO_COLOR=0" both still mean "no color" -- so this checks presence with
// LookupEnv rather than treating an empty string as absence.
func noColorRequested() bool {
	_, present := os.LookupEnv("NO_COLOR")
	return present
}
