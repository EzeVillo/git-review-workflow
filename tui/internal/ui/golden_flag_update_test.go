//go:build goldenupdate

package ui

import "flag"

// -update exists ONLY under `go test -tags goldenupdate`. Regenerate with:
//
//	go test -tags goldenupdate ./internal/ui -update
//
// and review the diff — this is a build-tag guard rather than an
// os.Getenv("CI") check on purpose (tasks.md T051): a runtime guard depends
// on the executor remembering to set CI, and some runners never do; a
// build tag the normal `go test ./...` binary does not even compile cannot
// be forgotten into silently regenerating goldens in CI.
var updateGoldenFlag = flag.Bool("update", false, "regenerate golden files under testdata/golden")

func shouldUpdateGolden() bool { return *updateGoldenFlag }
