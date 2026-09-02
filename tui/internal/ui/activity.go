package ui

import (
	"strings"
	"time"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	tea "github.com/charmbracelet/bubbletea"
)

const activityDelay = 120 * time.Millisecond

type activityPhase string

const (
	activityReading   activityPhase = "reading"
	activityAssistant activityPhase = "assistant"
	activityMutation  activityPhase = "mutation"
	activityDelegated activityPhase = "delegated"
)

type activityState struct {
	generation     int
	phase          activityPhase
	text           string
	active         bool
	visible        bool
	blocksControls bool
}

type activityVisibleMsg struct{ generation int }

func (m Model) startActivity(phase activityPhase, progress string, blocks bool) (Model, tea.Cmd) {
	m.activityGeneration++
	m.activity = activityState{
		generation: m.activityGeneration, phase: phase, text: progress,
		active: true, blocksControls: blocks,
	}
	gen := m.activityGeneration
	return m, tea.Tick(activityDelay, func(time.Time) tea.Msg {
		return activityVisibleMsg{generation: gen}
	})
}

func (m Model) clearActivity(generation int) Model {
	if !m.activity.active || m.activity.generation != generation {
		return m
	}
	m.activity = activityState{}
	return m
}

func (m Model) presentationPanel() domain.PanelModel {
	panel := m.Panel
	panel.StatusLine = m.statusLine
	if m.activity.active && m.activity.blocksControls {
		panel.Busy = true
	}
	if m.activity.active && m.activity.visible {
		if panel.StatusLine != "" && m.activity.phase == activityReading {
			panel.StatusLine += " · " + m.activity.text
		} else {
			panel.StatusLine = m.activity.text
		}
	}
	return panel
}

type ProgressOverlay struct{ Text string }

func (o ProgressOverlay) Render(vp Viewport) string {
	st := stylesFor(vp.Color)
	lines := []string{st.heading.Render(o.Text)}
	if vp.Cols > 0 {
		lines = wrapLine(lines[0], vp.Cols)
	}
	if vp.Rows > 0 && len(lines) > vp.Rows {
		lines = lines[:vp.Rows]
	}
	return strings.Join(lines, "\n")
}
