package domain

import "strings"

// FooterField packs one footer row's cells into a single tab-separated
// string. PanelModel must stay comparable by value (no slices, no maps —
// panelmodel_test.go's compile-time `==` check), so a variable-length list
// of structured rows (drafts, guides, fixes branches, the review inventory)
// cannot travel as a []struct the way it would in host/domain code that
// never has to satisfy that constraint. Packing each row as one string and
// the whole list as newline-joined rows keeps the field a plain string while
// still carrying everything ControlsFor and render.go need to draw and
// activate it — the same shape `git review status --porcelain` already uses
// for its own tab-separated records, reused here for a list that has to
// survive an `==` comparison instead of being printed.
func FooterField(cells ...string) string {
	return strings.Join(cells, "\t")
}

// FooterRows splits a FooterField-joined list back into its rows, each
// already split into its tab-separated cells. Empty input yields no rows
// (never one row of one empty cell) — the same "empty means nothing" shape
// splitLines already uses for status/list output.
func FooterRows(joined string) [][]string {
	if joined == "" {
		return nil
	}
	lines := strings.Split(joined, "\n")
	rows := make([][]string, len(lines))
	for i, l := range lines {
		rows[i] = strings.Split(l, "\t")
	}
	return rows
}

// boolCell / cellBool round-trip a bool through FooterField's "0"/"1" cells.
func boolCell(b bool) string {
	if b {
		return "1"
	}
	return "0"
}

func cellBool(s string) bool { return s == "1" }
