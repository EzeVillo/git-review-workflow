//go:build windows

package main

import "testing"

// consoleCodepage must never panic and must return a plausible codepage
// number whenever it claims ok=true -- CI's own windows runner may or may
// not have a real console attached (go test's own output is often
// redirected to a pipe), so this cannot assert a specific codepage or a
// specific ok value, only that the call is safe and self-consistent.
func TestConsoleCodepageDoesNotPanicAndIsSelfConsistent(t *testing.T) {
	cp, ok := consoleCodepage()
	if !ok && cp != 0 {
		t.Fatalf("consoleCodepage() = (%d, false), want (0, false) when unavailable", cp)
	}
	if ok && cp == 0 {
		t.Fatal("consoleCodepage() reported ok=true with codepage 0, which GetConsoleOutputCP never returns on success")
	}
}
