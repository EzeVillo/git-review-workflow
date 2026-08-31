package ui

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	tea "github.com/charmbracelet/bubbletea"
)

// T045's gate: Update never blocks on I/O itself. program.go must not
// import os/exec at all (the only package in this module allowed to is
// internal/host/invoke.go), and Model.Update must never call an
// internal/host function directly — only readCmd()/mutation helpers, which
// return a tea.Cmd for bubbletea to run later.
func TestUpdateNeverImportsOSExecOrCallsHostSynchronously(t *testing.T) {
	fset := token.NewFileSet()
	path := "program.go"
	f, err := parser.ParseFile(fset, path, nil, parser.AllErrors)
	if err != nil {
		t.Fatalf("parsing %s: %v", path, err)
	}
	for _, imp := range f.Imports {
		importPath, uerr := strconv.Unquote(imp.Path.Value)
		if uerr != nil {
			t.Fatalf("malformed import: %v", uerr)
		}
		if importPath == "os/exec" {
			t.Fatalf("%s imports os/exec directly — all spawning must go through internal/host via a tea.Cmd", path)
		}
	}

	// Find Update/handleKey/handleMouse and confirm none of their bodies
	// contain a CallExpr of the form host.<Identifier>(...) EXCEPT inside a
	// nested FuncLit (a closure that will run LATER, as a Cmd) — readCmd()
	// is defined as returning exactly such a closure, and any of these three
	// calling readCmd() (not a host function) is the allowed shape.
	watched := map[string]bool{"Update": true, "handleKey": true, "handleMouse": true}
	var offenders []string
	for _, decl := range f.Decls {
		fd, ok := decl.(*ast.FuncDecl)
		if !ok || fd.Recv == nil || !watched[fd.Name.Name] {
			continue
		}
		ast.Inspect(fd.Body, func(n ast.Node) bool {
			if _, ok := n.(*ast.FuncLit); ok {
				return false // do not descend into closures
			}
			call, ok := n.(*ast.CallExpr)
			if !ok {
				return true
			}
			sel, ok := call.Fun.(*ast.SelectorExpr)
			if !ok {
				return true
			}
			pkgIdent, ok := sel.X.(*ast.Ident)
			if !ok {
				return true
			}
			if pkgIdent.Name == "host" {
				offenders = append(offenders, fd.Name.Name+" -> host."+sel.Sel.Name)
			}
			return true
		})
	}
	if len(offenders) != 0 {
		t.Fatalf("calls internal/host functions directly (synchronously): %v", offenders)
	}
}

// T046: the very first frame — a Model fresh from NewModel(), with no Msg
// processed at all — draws waiting_text and nothing that names a resolved
// situation. This is the exact bug waiting_text exists to prevent in the
// other three clients.
func TestInitialFrameShowsWaitingTextOnly(t *testing.T) {
	m := NewModel()
	view := m.View()
	if !strings.Contains(view, domain.WaitingText) {
		t.Fatalf("initial View() = %q, want it to contain %q", view, domain.WaitingText)
	}
	for _, forbidden := range []string{
		domain.CliMissingTitle, domain.CliOutdatedTitle, domain.ErrorMessage, domain.OutOfRangeMessage,
	} {
		if strings.Contains(view, forbidden) {
			t.Fatalf("initial View() must not announce a resolved situation, found %q in %q", forbidden, view)
		}
	}
}

func TestFocusMsgTriggersARefreshCmd(t *testing.T) {
	m := NewModel()
	_, cmd := m.Update(tea.FocusMsg{})
	if cmd == nil {
		t.Fatal("FocusMsg must return a non-nil Cmd (disparador 3)")
	}
}

func TestRefreshKeyTriggersACmd(t *testing.T) {
	m := NewModel()
	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'r'}})
	if cmd == nil {
		t.Fatal("the 'r' key must return a non-nil Cmd (disparador 4, FR-038)")
	}
}

func TestWindowSizeMsgUpdatesViewport(t *testing.T) {
	m := NewModel()
	newM, _ := m.Update(tea.WindowSizeMsg{Width: 120, Height: 40})
	got := newM.(Model)
	if got.Viewport.Cols != 120 || got.Viewport.Rows != 40 {
		t.Fatalf("Viewport = %+v, want 120x40", got.Viewport)
	}
}

// Ensures the walk we just wrote actually looked at a real file, so the
// test cannot pass vacuously if program.go moves or is renamed later.
func TestProgramGoExistsAtExpectedPath(t *testing.T) {
	if _, err := os.Stat(filepath.Join(".", "program.go")); err != nil {
		t.Fatalf("program.go not found next to this test: %v", err)
	}
}
