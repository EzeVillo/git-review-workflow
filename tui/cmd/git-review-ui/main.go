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

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"github.com/EzeVillo/git-review-workflow/tui/internal/host"
	"github.com/EzeVillo/git-review-workflow/tui/internal/ui"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// bubbles has no functional use yet in this phase (textinput lands with
// the start assistant in Phase 6) — referenced here only so `go mod tidy`
// keeps it as a direct dependency, per module_boundary_test.go. lipgloss
// and bubbletea already have real callers in internal/ui, and fsnotify's
// sole caller is internal/host/watch_fsnotify.go as of Phase 5.
var (
	_ = textinput.New
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
	// the reviewui.* config read below. An askpass helper that touches the
	// terminal in any way corrupts the screen of the `git` process that
	// spawned it (contracts/cli-invocation.md § Entorno de red).
	if host.IsAskpassSentinel() {
		os.Exit(1)
	}

	// Watcher choice (T054): made exactly ONCE, here. "1" turns disparador
	// 2 on; anything else — including absence, which is the whole test
	// suite's default — is nopWatcher. This is a support/suite lever, not a
	// `reviewui.*` key: see internal/host/watch.go's comment on nopWatcher
	// for why turning the acceleration mechanism off is not reviewer
	// product surface.
	var watcher host.Watcher
	if os.Getenv("GIT_REVIEW_UI_WATCH") == "1" {
		watcher = host.NewFsnotifyWatcher()
	} else {
		watcher = host.NewNopWatcher()
	}

	_, _ = reviewUIConfig("startsource") // exercised for real starting Phase 6

	// FR-039's opt-in poll floor: `reviewui.pollseconds` has no default, so
	// an absent/invalid key leaves pollSeconds at 0, which
	// NewModelWithPollFloor treats as "off" — identical to plain
	// NewModel().
	pollSeconds := 0
	if d, ok := host.PollSecondsConfig(); ok {
		pollSeconds = int(d.Seconds())
	}

	p := tea.NewProgram(ui.NewModelWithPollFloor(pollSeconds),
		tea.WithAltScreen(),
		tea.WithMouseCellMotion(),
		tea.WithReportFocus(),
	)

	watchCtx, stopWatching := context.WithCancel(context.Background())
	go forwardWatchTicks(watchCtx, watcher, p)

	_, runErr := p.Run()
	stopWatching()
	_ = watcher.Stop()
	if runErr != nil {
		fmt.Fprintln(os.Stderr, "git-review-ui:", runErr)
		os.Exit(1)
	}
}

// forwardWatchTicks resolves the gitdir pair once, runs ONE read purely to
// learn whatever draft paths the CLI already reports (initialDraftPaths),
// and starts disparador 2 pointed at all of that — forwarding every
// coalesced signal into the running program as ui.WatchTick(), the one
// function outside internal/ui allowed to know that message exists at all
// (it deliberately does not export watchMsg's own type).
//
// Keeping draftPaths in sync as a SESSION progresses (a draft born after
// the TUI started, for a branch that had none at launch) needs a place
// that already sees every subsequent host.ReadResult — Phase 6's mutation
// cycle, not this one-shot startup path. A review whose draft association
// predates the TUI's own start (`reviewdraft` is written by
// `start`/`compare` long before any .md content exists) is already covered
// by the one-shot read below (contracts/refresh.md § Cómo se arma y se
// rearma); the anidamiento scenario itself — a brand-new draft appearing
// under a directory that already exists — is exactly what T058's own test
// exercises directly against the watcher, without this composition root.
//
// With the default nopWatcher, w.Start's channel is never sent to, so this
// goroutine simply parks on ctx.Done() for the program's whole lifetime —
// no extra process, no extra wakeup (T061/SC-002).
func forwardWatchTicks(ctx context.Context, w host.Watcher, p *tea.Program) {
	cwd, err := os.Getwd()
	if err != nil {
		return
	}
	dirs, _, ok := host.ResolveGitDirs(ctx, cwd)
	if !ok {
		return
	}
	ch, err := w.Start(ctx, dirs.GitDir, dirs.GitCommonDir, initialDraftPaths(ctx, cwd))
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
		}
	}
}

// initialDraftPaths runs one best-effort read cycle purely to seed the
// watcher's D/E roots with whatever the CLI already reports at startup
// (FR-036: never guessed, only ever what was reported). Any failure here
// just means the watcher starts without a D/E root — exactly how FR-064
// already treats a root that plain does not exist yet — and disparadores
// 1/3/4 still cover it from there.
func initialDraftPaths(ctx context.Context, cwd string) []string {
	result := host.ReadState(ctx, cwd, domain.MinCLIVersion)
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
	return paths
}
