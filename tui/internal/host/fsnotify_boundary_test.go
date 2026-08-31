// Package host will hold the process/filesystem/clock layer (invoke.go,
// gitdata.go, watch.go, watch_fsnotify.go, ...) starting in Phase 4. This
// phase (Foundational) only installs the one boundary test that has to be
// true from day one: fsnotify shows up in at most one file here, ever.
package host

import (
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// TestFsnotifyImportedInAtMostOneFile is the gate T056 (Phase 5) relies on:
// fsnotify is imported in ZERO or ONE file under internal/host/, and if it
// is one, that file is watch_fsnotify.go. Zero is the valid state right
// now — watch_fsnotify.go does not exist yet in this phase, and this test
// must keep passing until it does.
func TestFsnotifyImportedInAtMostOneFile(t *testing.T) {
	dir, err := os.Getwd()
	if err != nil {
		t.Fatalf("os.Getwd: %v", err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("reading %s: %v", dir, err)
	}

	fset := token.NewFileSet()
	var importers []string
	for _, entry := range entries {
		name := entry.Name()
		if entry.IsDir() || !strings.HasSuffix(name, ".go") {
			continue
		}
		path := filepath.Join(dir, name)
		f, err := parser.ParseFile(fset, path, nil, parser.ImportsOnly)
		if err != nil {
			t.Fatalf("parsing %s: %v", path, err)
		}
		for _, imp := range f.Imports {
			importPath, uerr := strconv.Unquote(imp.Path.Value)
			if uerr != nil {
				t.Fatalf("%s: malformed import %s: %v", path, imp.Path.Value, uerr)
			}
			if importPath == "github.com/fsnotify/fsnotify" {
				importers = append(importers, name)
			}
		}
	}

	switch len(importers) {
	case 0:
		// Valid today: watch_fsnotify.go does not exist yet.
	case 1:
		if importers[0] != "watch_fsnotify.go" {
			t.Errorf("fsnotify is imported by %q, must be watch_fsnotify.go", importers[0])
		}
	default:
		t.Errorf("fsnotify is imported by %d files, expected at most 1: %v", len(importers), importers)
	}
}
