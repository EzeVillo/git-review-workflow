// package tui_test: T062's rule needs to see cmd/git-review-ui/main.go
// alongside internal/host/, so it lives at the module root next to
// module_boundary_test.go's other whole-tree structural checks, not inside
// internal/host/ itself.
package tui_test

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestOnlyMainConstructsTheRealWatcher is T062's automated half: "ningún
// test puede esperar un evento de archivo real para sincronizarse" is
// enforced here by restricting WHERE the real Watcher can even be built.
// host.NewFsnotifyWatcher — the only door to it — may be named in exactly
// two places: its own definition (internal/host/watch_fsnotify.go) and the
// ONE composition root allowed to wire it into a running program
// (cmd/git-review-ui/main.go, per T054's "la elección se hace una sola
// vez"). watch_fsnotify_test.go, the deliberate exception that tests the
// real mechanism directly (T058/T059), never calls this constructor at
// all — being in the SAME package as fsnotifyWatcher, it builds the
// unexported struct literal directly, so it does not need naming here
// either. Any OTHER file naming this constructor would be a behavior test
// reaching for the real watcher instead of driving refresh with the
// watchMsg{} the contract requires (see watch.go's own comment on
// nopWatcher for the rest of this rule: the suite runs with nopWatcher by
// default, so a test that needed the real one to pass would turn the WHOLE
// suite red, not fail on its own).
func TestOnlyMainConstructsTheRealWatcher(t *testing.T) {
	allowed := map[string]bool{
		filepath.Join("internal", "host", "watch_fsnotify.go"): true,
		filepath.Join("cmd", "git-review-ui", "main.go"):       true,
	}

	fset := token.NewFileSet()
	var offenders []string
	checked := 0

	err := filepath.Walk(".", func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() || !strings.HasSuffix(path, ".go") {
			return nil
		}
		f, perr := parser.ParseFile(fset, path, nil, 0)
		if perr != nil {
			return perr
		}
		checked++
		rel := filepath.Clean(path)
		ast.Inspect(f, func(n ast.Node) bool {
			id, ok := n.(*ast.Ident)
			if !ok || id.Name != "NewFsnotifyWatcher" {
				return true
			}
			if !allowed[rel] {
				offenders = append(offenders, rel)
			}
			return true
		})
		return nil
	})
	if err != nil {
		t.Fatalf("walking tui/ for NewFsnotifyWatcher references: %v", err)
	}
	if checked == 0 {
		t.Fatal("no .go files found under tui/ (the walk is broken)")
	}
	if len(offenders) != 0 {
		t.Errorf("NewFsnotifyWatcher referenced outside the allowed files: %v", offenders)
	}
}
