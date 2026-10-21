package ui

import (
	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
	"strings"
	"testing"
)

func TestComparisonEndpointsRenderedInEveryMode(t *testing.T) {
	for _, mode := range []string{"whole", "step", "walk"} {
		p, ok := domain.ParsePorcelain("state\treview/f\tf\t" + strings.Repeat("2", 40) + "\t" + mode + "\tnone\t1\t1\t1\tapp.txt\t0\ncomparison-target\trefs/remotes/upstream/f\ncomparison\t" + strings.Repeat("1", 40) + "\t" + strings.Repeat("2", 40) + "\ncomparison-base\trefs/heads/main")
		if !ok {
			t.Fatal("comparison status did not parse")
		}
		panel := domain.Project(domain.ProjectInput{Situation: domain.SituationReview, Status: p, HasStatus: true})
		m := Model{Panel: panel, Viewport: Viewport{Cols: 80, Rows: 30}}
		view := m.View()
		for _, want := range []string{"Base: main (1111111)", "Inspect: upstream/f (2222222)"} {
			if !strings.Contains(view, want) {
				t.Fatalf("%s omitted %q: %s", mode, want, view)
			}
		}
	}
}
