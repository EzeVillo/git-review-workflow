// Command git-review-ui is the TUI's composition root: the askpass
// sentinel, the (still trivial) reviewui.* config read, watcher choice, and
// the bubbletea program itself.
package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	"github.com/EzeVillo/git-review-workflow/tui/internal/ui"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/fsnotify/fsnotify"
)

// bubbles and fsnotify have no functional use yet in this phase (textinput
// lands with the start assistant in Phase 6; fsnotify with the watcher in
// Phase 5) — referenced here only so `go mod tidy` keeps both as direct
// dependencies, per module_boundary_test.go. lipgloss and bubbletea already
// have real callers in internal/ui.
var (
	_ = textinput.New
	_ = fsnotify.NewWatcher
	_ = lipgloss.NewStyle
)

// reviewUIConfig reads one `reviewui.<name>` key defensively — the Go
// mirror of the shell verbs' `git config --get ... || true`: an absent key
// or any git failure reads as "unset", never as an error. Bare `git config
// --get` already resolves local over global on its own, which is what
// FR-061's "global as the preference, local as the override" means in
// practice — there is no separate two-step merge to write here.
//
// No `reviewui.*` key exists yet: this client's config surface starts
// empty on purpose. The mechanism exists now so the start assistant's
// `reviewui.startsource` (Phase 6) and the rest have somewhere to call.
func reviewUIConfig(name string) (string, bool) {
	out, err := exec.Command("git", "config", "--get", "reviewui."+name).Output()
	if err != nil {
		return "", false
	}
	return strings.TrimRight(string(out), "\n"), true
}

func main() {
	// The askpass sentinel is checked FIRST, before anything else — before
	// reading a single byte of terminal state, before bubbletea, before even
	// the reviewui.* config read above. An askpass helper that touches the
	// terminal in any way corrupts the screen of the `git` process that
	// spawned it (contracts/cli-invocation.md § Entorno de red).
	if host.IsAskpassSentinel() {
		os.Exit(1)
	}

	// Watcher choice (T054, Phase 5): a real `internal/host.Watcher`
	// doesn't exist yet — its interface takes a WatchSet (T055), which
	// doesn't either — so there is nothing to construct honestly today.
	// GIT_REVIEW_UI_WATCH is read here so the switch is already wired to
	// this exact point; Phase 5 plugs the two implementations in without
	// touching anything above or below this comment.
	_ = os.Getenv("GIT_REVIEW_UI_WATCH")

	_, _ = reviewUIConfig("startsource") // exercised for real starting Phase 6

	p := tea.NewProgram(ui.NewModel(),
		tea.WithAltScreen(),
		tea.WithMouseCellMotion(),
		tea.WithReportFocus(),
	)
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "git-review-ui:", err)
		os.Exit(1)
	}
}
