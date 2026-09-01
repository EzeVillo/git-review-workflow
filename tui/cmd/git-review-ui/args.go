package main

import (
	"fmt"
	"strings"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

// The argv surface of the binary, mirroring the dispatcher's own
// (bin/git-review): -h/--h/--help print usage, -V/--version print the
// version, everything else is refused.
//
// REFUSED, not ignored. `git review ui` passes every argument through
// unchanged, so before this existed a typo — `git review ui --setp` — was
// swallowed in silence and the TUI came up as if nothing had been asked.
// The dispatcher answers an unknown verb with `error:` on stderr and a
// non-zero exit; this is the same answer one level down, and the same
// discipline the POSIX verbs follow: refuse with an actionable hint rather
// than guess (see § Reglas duras in CLAUDE.md).
//
// --version matters more here than in a client that ships inside an IDE:
// the TUI is released on its own tag (`tui-v*`) and its own Homebrew
// formula, so `git-review-ui --version` is the only way a bug report can
// say which build is running.

type argsOutcome int

const (
	// argsRun: start the TUI.
	argsRun argsOutcome = iota
	// argsPrint: write Text to stdout and exit 0.
	argsPrint
	// argsReject: write Text to stderr and exit non-zero.
	argsReject
)

type argsResult struct {
	Outcome argsOutcome
	Text    string
}

const usageText = `usage: git-review-ui [-h | -V]

Terminal interface for the git review workflow. Run it from inside a git
repository; it reads the CLI's porcelain records and never derives repository
state on its own.

  -h, --help     print this message
  -V, --version  print the terminal client's version

Also reachable as ` + "`git review ui`" + ` and ` + "`git review-ui`" + `.

Environment:
  GIT_REVIEW_UI_WATCH=0  turn filesystem-event acceleration off; keys, focus,
                         mutations and explicit refresh keep reading the CLI
  GIT_REVIEW_UI_ASCII=1  force the ASCII glyph set
  NO_COLOR               any value disables colour (https://no-color.org)

Configuration (git config, local overrides global):
  reviewui.startsource   preselect the start assistant's source
  reviewui.pollseconds   opt-in read floor for network mounts that lose events`

// parseArgs is the OS-free core: it takes the arguments after the program
// name and says what the process should do with them.
func parseArgs(argv []string) argsResult {
	if len(argv) == 0 {
		return argsResult{Outcome: argsRun}
	}
	// One flag at a time. There is no combination of these that means
	// anything, and accepting `-h -V` would only raise the question of which
	// one wins.
	if len(argv) == 1 {
		switch argv[0] {
		case "-h", "--h", "--help":
			return argsResult{Outcome: argsPrint, Text: usageText}
		case "-V", "--version":
			return argsResult{Outcome: argsPrint, Text: domain.TUIVersion}
		}
	}
	return argsResult{
		Outcome: argsReject,
		Text: fmt.Sprintf(
			"git-review-ui: unrecognised argument %q. See 'git-review-ui -h'.",
			strings.Join(argv, " "),
		),
	}
}
