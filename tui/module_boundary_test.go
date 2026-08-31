// Package tui_test holds whole-module boundary checks that do not belong
// to any one internal package: the module's own dependency list, and the
// absence of any import naming a sibling client. There is no non-test .go
// file at this level — the module root is just go.mod plus the cmd/ and
// internal/ trees — so this file is the package for this directory.
package tui_test

import (
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// TestGoModDeclaresExactlyFourDirectDependencies is FR-075/SC-014's first
// half: `go.mod`'s DIRECT requires (the ones with no `// indirect`
// trailer) are exactly the four this module is allowed — bubbletea,
// lipgloss, bubbles, fsnotify — and nothing else, however many transitive
// modules those four pull in.
//
// This parses go.mod with a small regex rather than importing
// golang.org/x/mod/modfile: pulling in a parser library, even test-only,
// would itself be a fifth dependency of this module — exactly the property
// this test exists to guard.
func TestGoModDeclaresExactlyFourDirectDependencies(t *testing.T) {
	b, err := os.ReadFile("go.mod")
	if err != nil {
		t.Fatalf("reading go.mod: %v", err)
	}
	text := string(b)

	reqBlockRe := regexp.MustCompile(`(?s)require \(\n(.*?)\n\)`)
	blocks := reqBlockRe.FindAllStringSubmatch(text, -1)
	if len(blocks) == 0 {
		t.Fatal("go.mod has no require ( ... ) block — the format changed, update this test's parser")
	}

	lineRe := regexp.MustCompile(`^\s*(\S+)\s+v\S+(\s*//\s*indirect)?\s*$`)
	var direct []string
	for _, block := range blocks {
		for _, line := range strings.Split(block[1], "\n") {
			m := lineRe.FindStringSubmatch(line)
			if m == nil {
				continue
			}
			if m[2] == "" {
				direct = append(direct, m[1])
			}
		}
	}

	want := map[string]bool{
		"github.com/charmbracelet/bubbletea": true,
		"github.com/charmbracelet/bubbles":   true,
		"github.com/charmbracelet/lipgloss":  true,
		"github.com/fsnotify/fsnotify":       true,
	}
	if len(direct) != len(want) {
		t.Fatalf("expected exactly %d direct dependencies, found %d: %v", len(want), len(direct), direct)
	}
	for _, d := range direct {
		if !want[d] {
			t.Errorf("go.mod declares unexpected direct dependency %q", d)
		}
	}
}

// TestNoImportNamesASiblingClient is FR-075/SC-014's second half. It is
// impossible for a Go import path to literally resolve to
// "vscode-extension" or the like — this is a safety net, not a real attack
// surface, and it says so on purpose: Go was chosen specifically so that
// sharing a parser with vscode-extension/ would be a whole new module
// import away, not one line changed in an existing one (research.md, the
// "frontera de lenguaje" rationale in plan.md). This test is what makes
// that boundary something other than a design intention.
func TestNoImportNamesASiblingClient(t *testing.T) {
	forbidden := []string{"vscode-extension", "jetbrains-plugin", "visualstudio-extension"}
	fset := token.NewFileSet()
	checked := 0

	err := filepath.Walk(".", func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		if !strings.HasSuffix(path, ".go") {
			return nil
		}
		f, perr := parser.ParseFile(fset, path, nil, parser.ImportsOnly)
		if perr != nil {
			return perr
		}
		checked++
		for _, imp := range f.Imports {
			importPath, uerr := strconv.Unquote(imp.Path.Value)
			if uerr != nil {
				return uerr
			}
			for _, name := range forbidden {
				if strings.Contains(importPath, name) {
					t.Errorf("%s imports %q, which names another client of the monorepo", path, importPath)
				}
			}
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walking tui/ for imports: %v", err)
	}
	if checked == 0 {
		t.Fatal("no .go files found under tui/ (the walk is broken)")
	}
}
