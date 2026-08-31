//go:build windows

package main

import "syscall"

// GetConsoleOutputCP via the raw Win32 API, stdlib-only (syscall): pulling
// in a package for this would be a fifth direct dependency of the module,
// exactly what module_boundary_test.go's exactly-four-dependencies gate
// exists to catch.
var (
	kernel32               = syscall.NewLazyDLL("kernel32.dll")
	procGetConsoleOutputCP = kernel32.NewProc("GetConsoleOutputCP")
)

// consoleCodepage answers the second half of T096's trigger: a Windows
// console codepage other than 65001 (UTF-8). ok is false when there is no
// console to ask at all (output redirected to a file or pipe with nothing
// attached, or running under a terminal emulator that never allocates a
// real Win32 console, like some mintty/MSYS setups) -- the same "could not
// learn X, so do not claim to know" shape every other probe in this client
// already uses; asciiFallback then falls back to whatever localeSaysNonUTF8
// already decided.
func consoleCodepage() (uint32, bool) {
	r, _, _ := procGetConsoleOutputCP.Call()
	if r == 0 {
		return 0, false
	}
	return uint32(r), true
}
