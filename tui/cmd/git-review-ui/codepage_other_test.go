//go:build !windows

package main

import "testing"

// Outside Windows there is no console codepage concept: consoleCodepage
// must always report ok=false so asciiFallback falls through to the locale
// check alone.
func TestConsoleCodepageIsUnavailableOutsideWindows(t *testing.T) {
	if _, ok := consoleCodepage(); ok {
		t.Fatal("consoleCodepage must report ok=false on a non-Windows build")
	}
}
