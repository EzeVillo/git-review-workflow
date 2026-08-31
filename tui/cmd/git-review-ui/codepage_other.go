//go:build !windows

package main

// consoleCodepage does not apply outside Windows: there is no console
// codepage concept on macOS/Linux terminals, only the locale environment
// variables asciiFallback already checks first.
func consoleCodepage() (uint32, bool) { return 0, false }
