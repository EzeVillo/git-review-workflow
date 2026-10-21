package ui

import (
	"fmt"
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	tea "github.com/charmbracelet/bubbletea"
)

func overflowingCommentReview(mode domain.ReviewMode) Model {
	m := commentFixture("both")
	m.Viewport = Viewport{Cols: 80, Rows: 24, ASCII: true}
	m.Panel.Mode = mode
	m.Panel.MouseEnabled = true
	for i := 0; i < 60; i++ {
		m.Panel.Files += fmt.Sprintf("src/file-%02d.go\n", i)
	}
	m.Panel.Total, m.Panel.EntryCount = 60, 60
	if mode == domain.ModeWalk {
		m.Panel.CurrentPath = domain.NewPathRef("src/file-00.go")
		m.Panel.WhyState = domain.WhyPresent
		m.Panel.Why = strings.Repeat("Read this explanation before changing the shared state. ", 60)
	}
	return m
}

func TestReviewCommentControlsStayVisibleDuringKeyboardNavigation(t *testing.T) {
	for _, mode := range []domain.ReviewMode{domain.ModeWhole, domain.ModeStep, domain.ModeWalk} {
		for _, size := range goldenSizes {
			t.Run(string(mode)+"/"+size.name, func(t *testing.T) {
				m := overflowingCommentReview(mode)
				m.Viewport.Cols, m.Viewport.Rows = size.cols, size.rows
				controls := ControlsFor(m.Panel)
				for _, key := range []tea.KeyType{tea.KeyDown, tea.KeyUp} {
					for step := 0; step <= len(controls); step++ {
						updated, _ := m.Update(tea.KeyMsg{Type: key})
						m = updated.(Model)
						focused := controls[m.FocusIndex]
						frame, hits, _ := viewWithState(m.presentationPanel(), m.Viewport, m.presentationState())
						if _, ok := hits.Rect(focused.ID, focused.Variant); !ok {
							t.Fatalf("focused %s/%s is clipped after %s:\n%s", focused.ID, focused.Variant, key, frame)
						}
						if !strings.Contains(frame, "q:quit") || len(strings.Split(frame, "\n")) > size.rows {
							t.Fatalf("scrolling lost the key bar or overflowed the viewport:\n%s", frame)
						}
					}
				}
			})
		}
	}
}

func TestReviewMouseWheelRevealsCommentsAndPreservesClickTargets(t *testing.T) {
	m := overflowingCommentReview(domain.ModeWhole)
	before := m.View()
	for i := 0; i < 30; i++ {
		updated, _ := m.Update(tea.MouseMsg{Action: tea.MouseActionPress, Button: tea.MouseButtonWheelDown})
		m = updated.(Model)
	}
	frame, hits, _ := viewWithState(m.presentationPanel(), m.Viewport, m.presentationState())
	if frame == before || !strings.Contains(frame, "Shared") || !strings.Contains(frame, "q:quit") {
		t.Fatalf("wheel did not expose the comments while keeping the key bar:\n%s", frame)
	}
	rect, ok := hits.Rect("openCommentDiff", "0")
	if !ok {
		t.Fatal("Local browser has no visible click target after scrolling")
	}
	if id, variant, ok := hits.At(rect.Col, rect.Row); !ok || id != "openCommentDiff" || variant != "0" {
		t.Fatalf("scrolled click points at %s/%s instead of the Local browser", id, variant)
	}
	for i := 0; i < 30; i++ {
		updated, _ := m.Update(tea.MouseMsg{Action: tea.MouseActionPress, Button: tea.MouseButtonWheelUp})
		m = updated.(Model)
	}
	if m.View() != before {
		t.Fatal("scrolling back did not restore the first review frame")
	}
}

func TestReviewResizeKeepsFocusedCommentVisible(t *testing.T) {
	m := overflowingCommentReview(domain.ModeWhole)
	controls := ControlsFor(m.Panel)
	m.FocusIndex = len(controls) - 1
	m = m.keepFocusedControlVisible(1)
	focused := controls[m.FocusIndex]
	for _, size := range []tea.WindowSizeMsg{{Width: 80, Height: 12}, {Width: 120, Height: 100}} {
		updated, _ := m.Update(size)
		m = updated.(Model)
		frame, hits, _ := viewWithState(m.presentationPanel(), m.Viewport, m.presentationState())
		if _, ok := hits.Rect(focused.ID, focused.Variant); !ok || !strings.Contains(frame, "q:quit") {
			t.Fatalf("resize hid the focused comment or key bar:\n%s", frame)
		}
	}
	if m.bodyOffset != 0 {
		t.Fatal("expanding the terminal kept an obsolete scroll offset")
	}
}
