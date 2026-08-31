// Command git-review-ui is the TUI's composition root. Phase 3 only proves
// the module wires its four direct dependencies (FR-045 forbids any of them
// under internal/domain); the real program — watcher choice, config read,
// bubbletea startup — lands in Phase 4 (T044-T049).
package main

import (
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/fsnotify/fsnotify"
)

// Referencian los cuatro imports directos sin llamarlos: go.mod solo marca
// "directo" lo que el codigo usa de verdad, y go mod tidy degradaria estas
// cuatro entradas a indirectas si nada las nombrara todavia.
var (
	_ = tea.NewProgram
	_ = textinput.New
	_ = lipgloss.NewStyle
	_ = fsnotify.NewWatcher
)

func main() {}
