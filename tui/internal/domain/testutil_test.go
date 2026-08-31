package domain

import (
	"os"
	"path/filepath"
	"runtime"
)

// moduleRoot returns the tui/ module root, anchored to this source file via
// runtime.Caller rather than the process's working directory: `go test` sets
// cwd to the package under test, but nothing guarantees that from every
// invocation (an IDE runner, `go test ./...` from the repo root with
// `-run`), so anchoring to the file itself is the portable form.
func moduleRoot() string {
	_, file, _, _ := runtime.Caller(0)
	// this file: tui/internal/domain/testutil_test.go
	return filepath.Join(filepath.Dir(file), "..", "..")
}

// repoRoot returns the monorepo root, two levels above the tui/ module.
func repoRoot() string {
	return filepath.Join(moduleRoot(), "..")
}

func readFixture(elems ...string) string {
	p := append([]string{moduleRoot(), "testdata", "porcelain"}, elems...)
	b, err := os.ReadFile(filepath.Join(p...))
	if err != nil {
		panic(err)
	}
	return string(b)
}
