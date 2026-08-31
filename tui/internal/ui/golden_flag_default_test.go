//go:build !goldenupdate

package ui

// shouldUpdateGolden is always false in the binary CI builds: the -update
// flag does not exist at all outside the goldenupdate build tag (FR-070),
// so passing it here is an unknown-flag error, never a silent no-op.
func shouldUpdateGolden() bool { return false }
