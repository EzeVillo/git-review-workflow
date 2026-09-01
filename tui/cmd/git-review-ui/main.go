// Command git-review-ui is the TUI's composition root: the askpass
// sentinel, the (still trivial) reviewui.* config read, watcher choice, and
// the bubbletea program itself.
package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	"github.com/EzeVillo/git-review-workflow/tui/internal/ui"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// bubbles/textinput still has no functional use: Phase 6's start assistant
// and setBase/setRemote/finish-destination pickers are all list choices
// (internal/ui/select.go's SelectOverlay), never free text, so nothing
// under internal/ui imports bubbles either. Referenced here only so `go mod
// tidy` keeps it as a direct dependency, per module_boundary_test.go.
// lipgloss and bubbletea already have real callers in internal/ui, and
// fsnotify's sole caller is internal/host/watch_fsnotify.go as of Phase 5.
var (
	_ = textinput.New
	_ = lipgloss.NewStyle
)

const watcherEnv = "GIT_REVIEW_UI_WATCH"

type watcherKind uint8

const (
	watcherFsnotify watcherKind = iota
	watcherNop
)

// watcherKindFromEnv keeps the real watcher as the runtime default. The
// explicit zero value is the deterministic support/test opt-out; no missing
// or malformed environment value can silently disable release behavior.
func watcherKindFromEnv() watcherKind {
	if os.Getenv(watcherEnv) == "0" {
		return watcherNop
	}
	return watcherFsnotify
}

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
	// the reviewui.* config read below. An askpass helper that touches the
	// terminal in any way corrupts the screen of the `git` process that
	// spawned it (contracts/cli-invocation.md § Entorno de red).
	if host.IsAskpassSentinel() {
		os.Exit(1)
	}

	// Watcher choice (T054): made exactly ONCE, here. The real watcher is the
	// runtime default; GIT_REVIEW_UI_WATCH=0 is the explicit deterministic
	// support/test opt-out. This is a support/suite lever, not a `reviewui.*`
	// key: see internal/host/watch.go's comment on nopWatcher for why turning
	// the acceleration mechanism off is not reviewer product surface.
	var watcher host.Watcher
	if watcherKindFromEnv() == watcherFsnotify {
		watcher = host.NewFsnotifyWatcher()
	} else {
		watcher = host.NewNopWatcher()
	}

	// FR-061: the start assistant's SOURCE question pre-positions its
	// cursor on this when present, and otherwise never hides an option the
	// CLI itself did not rule out — see ui.Model.WithPreferredStartSource.
	startSource, _ := reviewUIConfig("startsource")

	// FR-039's opt-in poll floor: `reviewui.pollseconds` has no default, so
	// an absent/invalid key leaves pollSeconds at 0, which
	// NewModelWithPollFloor treats as "off" — identical to plain
	// NewModel().
	pollSeconds := 0
	if d, ok := host.PollSecondsConfig(); ok {
		pollSeconds = int(d.Seconds())
	}

	// T095/T096: the two Viewport capabilities decided once at startup and
	// never re-evaluated -- NO_COLOR's mere presence (contracts/tui-
	// surface.md § El pane real) and the ASCII glyph fallback (locale/
	// codepage, or the GIT_REVIEW_UI_ASCII override that makes the -ascii
	// golden set possible). Cols/Rows are left at their construction-time
	// placeholder: bubbletea's own first tea.WindowSizeMsg overwrites them
	// with the real terminal size before the first real frame draws.
	acceptedReads := make(chan host.ReadResult, 16)
	model := ui.NewModelWithPollFloor(pollSeconds).
		WithPreferredStartSource(startSource).
		WithViewportCapabilities(!noColorRequested(), asciiFallback()).
		WithAcceptedReadCallback(func(result host.ReadResult) {
			acceptedReads <- result
		})

	p := tea.NewProgram(model,
		tea.WithAltScreen(),
		tea.WithMouseCellMotion(),
		tea.WithReportFocus(),
	)

	watchCtx, stopWatching := context.WithCancel(context.Background())
	go forwardWatchTicks(watchCtx, watcher, p, acceptedReads)

	_, runErr := p.Run()
	stopWatching()
	_ = watcher.Stop()
	if runErr != nil {
		fmt.Fprintln(os.Stderr, "git-review-ui:", runErr)
		os.Exit(1)
	}
}

// forwardWatchTicks resolves the gitdir pair once, starts disparador 2,
// forwards every coalesced filesystem signal into Bubble Tea, and rebuilds
// the watch closure after every read the model accepted. Draft paths enter
// only through the status/config porcelain fields in that accepted result;
// no startup-only duplicate ReadState call or guessed draft root exists.
func forwardWatchTicks(ctx context.Context, w host.Watcher, p *tea.Program, acceptedReads <-chan host.ReadResult) {
	cwd, err := os.Getwd()
	if err != nil {
		return
	}
	dirs, _, ok := host.ResolveGitDirs(ctx, cwd)
	if !ok {
		return
	}
	ch, err := w.Start(ctx, dirs.GitDir, dirs.GitCommonDir, nil)
	if err != nil {
		return
	}
	for {
		select {
		case <-ctx.Done():
			return
		case _, chOK := <-ch:
			if !chOK {
				return
			}
			p.Send(ui.WatchTick())
		case result := <-acceptedReads:
			_ = rebuildWatcher(w, dirs, result)
		}
	}
}

// rebuildWatcher is the testable accepted-read boundary. Its only draft
// inputs are the two porcelain result families ReadState retained.
func rebuildWatcher(w host.Watcher, dirs host.GitDirs, result host.ReadResult) error {
	var paths []string
	if result.HasStatus && result.Status.DraftPath != "" {
		paths = append(paths, result.Status.DraftPath)
	}
	if result.HasConfig {
		for _, d := range result.Config.Drafts {
			if d.Path != "" {
				paths = append(paths, d.Path)
			}
		}
	}
	return w.Rebuild(dirs.GitDir, dirs.GitCommonDir, paths)
}
