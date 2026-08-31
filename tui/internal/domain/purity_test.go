package domain

// This is the domain layer: parsing, projection, copy, the confirmation
// table, the icon map, the keymap. FR-045 forbids a terminal library, a
// filesystem watcher or a process spawner anywhere under here — applied to
// PRODUCTION code only, so this test skips _test.go files: this file itself
// is allowed to use go/parser, and any future test helper is allowed to
// reach for os/exec if it ever needs to.

import (
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"testing"
)

var forbiddenImportPrefixes = []string{
	"github.com/charmbracelet/bubbletea",
	"github.com/charmbracelet/lipgloss",
	"github.com/charmbracelet/bubbles",
	"github.com/fsnotify/fsnotify",
	"os/exec",
}

func TestDomainPackageImportsNothingForbidden(t *testing.T) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	dir := filepath.Dir(thisFile)

	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("reading %s: %v", dir, err)
	}

	fset := token.NewFileSet()
	checked := 0
	for _, entry := range entries {
		name := entry.Name()
		if entry.IsDir() || !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			continue
		}
		path := filepath.Join(dir, name)
		f, err := parser.ParseFile(fset, path, nil, parser.ImportsOnly)
		if err != nil {
			t.Fatalf("parsing %s: %v", path, err)
		}
		checked++
		for _, imp := range f.Imports {
			importPath, err := strconv.Unquote(imp.Path.Value)
			if err != nil {
				t.Fatalf("%s: malformed import %s: %v", path, imp.Path.Value, err)
			}
			for _, forbidden := range forbiddenImportPrefixes {
				if importPath == forbidden || strings.HasPrefix(importPath, forbidden+"/") {
					t.Errorf("%s imports %q, forbidden under internal/domain/ (FR-045)", path, importPath)
				}
			}
		}
	}
	if checked == 0 {
		t.Fatal("no non-test .go files found under internal/domain/ (the walk is broken)")
	}
}
