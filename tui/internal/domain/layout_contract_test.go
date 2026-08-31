package domain

// The TUI's equivalent of JetBrains' PanelLayoutContractTest and Visual
// Studio's PanelLayoutContractTests (FR-047): it reads the canonical
// contracts/client-product-surface.yaml straight off disk and asserts
// layout.go's declared structure against it. Every assertion here is
// STRUCTURAL — a control-id sequence, a set of map keys, a declared
// constant — never a pixel or a rendered string: there is no renderer yet
// in this phase.

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

func readCanonicalYAML(t *testing.T) string {
	t.Helper()
	path := repoRoot() + "/contracts/client-product-surface.yaml"
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading canonical YAML at %s: %v", path, err)
	}
	return strings.ReplaceAll(string(b), "\r\n", "\n")
}

// topLevelYAMLBlock returns the body under `key:` at column 0, up to (but
// not including) the next column-0 key.
func topLevelYAMLBlock(yaml, key string) string {
	re := regexp.MustCompile(`(?m)^` + regexp.QuoteMeta(key) + `:\s*$`)
	loc := re.FindStringIndex(yaml)
	if loc == nil {
		return ""
	}
	rest := yaml[loc[1]:]
	nextKey := regexp.MustCompile(`(?m)^[a-z_][a-z0-9_]*:`)
	if nl := nextKey.FindStringIndex(rest); nl != nil {
		return rest[:nl[0]]
	}
	return rest
}

// situationYAMLBlock extracts one situation's body from panel_layout's
// text, up to the next 2-space-indented situation key.
func situationYAMLBlock(panelLayoutBlock, key string) string {
	marker := "  " + key + ":"
	start := strings.Index(panelLayoutBlock, marker)
	if start == -1 {
		return ""
	}
	rest := panelLayoutBlock[start+1:]
	nextKey := regexp.MustCompile(`(?m)^ {2}[a-z][a-z0-9-]*:`)
	if loc := nextKey.FindStringIndex(rest); loc != nil {
		return panelLayoutBlock[start : start+1+loc[0]]
	}
	return panelLayoutBlock[start:]
}

// extractControlSequence pulls every `{id: X` and `control: X` occurrence
// out of a situation's block, in document order — a textual mirror, not a
// simulation of which `when:` branch applies. It deliberately does not
// distinguish `when:` conditions, the same choice
// scripts/check-client-product-surface.mjs makes for the same reason: a
// control declared inside either branch of a mode split is still a control
// this client has to account for.
func extractControlSequence(block string) []string {
	type hit struct {
		pos int
		id  string
	}
	var hits []hit
	for _, m := range regexp.MustCompile(`\{id:\s*([A-Za-z][A-Za-z0-9]*)`).FindAllStringSubmatchIndex(block, -1) {
		hits = append(hits, hit{pos: m[0], id: block[m[2]:m[3]]})
	}
	for _, m := range regexp.MustCompile(`control:\s*([A-Za-z][A-Za-z0-9]*)`).FindAllStringSubmatchIndex(block, -1) {
		hits = append(hits, hit{pos: m[0], id: block[m[2]:m[3]]})
	}
	for i := 1; i < len(hits); i++ {
		for j := i; j > 0 && hits[j-1].pos > hits[j].pos; j-- {
			hits[j-1], hits[j] = hits[j], hits[j-1]
		}
	}
	ids := make([]string, len(hits))
	for i, h := range hits {
		ids[i] = h.id
	}
	return ids
}

// actionsNotInTUI reads `not_in:` off every action in the canonical's
// `actions:` block and returns the set that excludes "tui" (T006).
func actionsNotInTUI(yaml string) map[string]bool {
	block := topLevelYAMLBlock(yaml, "actions")
	excluded := map[string]bool{}
	headRe := regexp.MustCompile(`^ {2}([A-Za-z][A-Za-z0-9]*):\s*$`)
	notInRe := regexp.MustCompile(`^ {4}not_in:\s*\[([^\]]*)\]`)
	current := ""
	for _, line := range strings.Split(block, "\n") {
		if m := headRe.FindStringSubmatch(line); m != nil {
			current = m[1]
			continue
		}
		if m := notInRe.FindStringSubmatch(line); m != nil && current != "" {
			for _, c := range strings.Split(m[1], ",") {
				if strings.TrimSpace(c) == "tui" {
					excluded[current] = true
				}
			}
		}
	}
	return excluded
}

func equalControlSequences(a []ControlID, b []ControlID) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func TestLayoutDeclaresAllElevenSituations(t *testing.T) {
	if len(AllLayoutSituations) != 11 {
		t.Fatalf("expected 11 layout situations, got %d", len(AllLayoutSituations))
	}
	for _, sit := range AllLayoutSituations {
		if _, ok := Layout[sit]; !ok {
			t.Errorf("Layout has no entry for %q", sit)
		}
	}
}

// FR-047: layout.go's per-situation control sequence mirrors panel_layout:,
// with this client's own not_in: exclusions (today, only openAllChanges)
// filtered out of the canonical side before comparing.
func TestLayoutMirrorsCanonicalControlSequencePerSituation(t *testing.T) {
	yaml := readCanonicalYAML(t)
	panelLayoutBlock := topLevelYAMLBlock(yaml, "panel_layout")
	if panelLayoutBlock == "" {
		t.Fatal("canonical has no panel_layout: block")
	}
	notInTUI := actionsNotInTUI(yaml)

	for _, sit := range AllLayoutSituations {
		block := situationYAMLBlock(panelLayoutBlock, string(sit))
		if block == "" {
			t.Fatalf("canonical panel_layout has no %q block", sit)
		}
		var want []ControlID
		for _, id := range extractControlSequence(block) {
			if notInTUI[id] {
				continue
			}
			want = append(want, ControlID(id))
		}
		got := Layout[sit]
		if !equalControlSequences(got, want) {
			t.Errorf("situation %q:\n  layout.go declares  %v\n  canonical declares  %v", sit, got, want)
		}
	}
}

func TestReviewWholeExcludesOpenAllChanges(t *testing.T) {
	for _, id := range Layout[LayoutReviewWhole] {
		if id == "openAllChanges" {
			t.Fatal("review-whole must not draw openAllChanges: contracts/client-product-surface.yaml marks it not_in: [tui] (T006)")
		}
	}
}

// directMapKeys reads the 2-space-indented keys declared straight under a
// top-level map (inventory_controls:, draft_controls:) — no nested
// `controls:` wrapper.
func directMapKeys(yaml, rootKey string) []string {
	block := topLevelYAMLBlock(yaml, rootKey)
	var keys []string
	for _, m := range regexp.MustCompile(`(?m)^ {2}([A-Za-z][A-Za-z0-9]*):`).FindAllStringSubmatch(block, -1) {
		keys = append(keys, m[1])
	}
	return keys
}

// nestedControlKeys reads the 4-space-indented keys under a top-level map's
// own `controls:` sub-block (guide_rows.controls:, walkthrough_row.controls:,
// fixes_rows.controls:).
func nestedControlKeys(yaml, rootKey string) []string {
	block := topLevelYAMLBlock(yaml, rootKey)
	idx := strings.Index(block, "\n  controls:")
	if idx == -1 {
		return nil
	}
	rest := block[idx+1:]
	if nl := strings.Index(rest, "\n"); nl != -1 {
		rest = rest[nl+1:]
	}
	if loc := regexp.MustCompile(`(?m)^ {2}[a-z_]`).FindStringIndex(rest); loc != nil {
		rest = rest[:loc[0]]
	}
	var keys []string
	for _, m := range regexp.MustCompile(`(?m)^ {4}([A-Za-z][A-Za-z0-9]*):`).FindAllStringSubmatch(rest, -1) {
		keys = append(keys, m[1])
	}
	return keys
}

func TestRowControlMapsMirrorCanonical(t *testing.T) {
	yaml := readCanonicalYAML(t)
	checks := []struct {
		name string
		got  map[ControlID]RowControlSpec
		want []string
	}{
		{"inventory_controls", InventoryControls, directMapKeys(yaml, "inventory_controls")},
		{"draft_controls", DraftControls, directMapKeys(yaml, "draft_controls")},
		{"guide_rows.controls", GuideRowControls, nestedControlKeys(yaml, "guide_rows")},
		{"walkthrough_row.controls", WalkthroughRowControls, nestedControlKeys(yaml, "walkthrough_row")},
		{"fixes_rows.controls", FixesRowControls, nestedControlKeys(yaml, "fixes_rows")},
	}
	for _, c := range checks {
		if len(c.want) == 0 {
			t.Fatalf("%s: extracted no keys from the canonical (the parser broke)", c.name)
		}
		wantSet := map[string]bool{}
		for _, k := range c.want {
			wantSet[k] = true
		}
		for k := range wantSet {
			if _, ok := c.got[ControlID(k)]; !ok {
				t.Errorf("%s: layout.go is missing control %q", c.name, k)
			}
		}
		for k := range c.got {
			if !wantSet[string(k)] {
				t.Errorf("%s: layout.go declares %q, which the canonical does not", c.name, k)
			}
		}
	}
}

func TestFooterCapAndSingleScrollbar(t *testing.T) {
	if FooterCapPercent != 55 {
		t.Errorf("FooterCapPercent = %d, want 55 (FR-022)", FooterCapPercent)
	}
	if ScrollbarCount != 1 {
		t.Errorf("ScrollbarCount = %d, want exactly 1", ScrollbarCount)
	}
}

func TestRowHeaderOrderMatchesCanonical(t *testing.T) {
	yaml := readCanonicalYAML(t)
	block := topLevelYAMLBlock(yaml, "row_shape")
	m := regexp.MustCompile(`header:\s*\[([^\]]*)\]`).FindStringSubmatch(block)
	if m == nil {
		t.Fatal("canonical row_shape.header not found")
	}
	var want []string
	for _, tok := range strings.Split(m[1], ",") {
		want = append(want, strings.Trim(strings.TrimSpace(tok), `"`))
	}
	if strings.Join(want, ",") != strings.Join(RowHeaderOrder, ",") {
		t.Errorf("RowHeaderOrder = %v, canonical row_shape.header = %v", RowHeaderOrder, want)
	}
	if RowHeaderOrder[len(RowHeaderOrder)-1] != "badge" {
		t.Fatal("the badge must always close the row header line")
	}
}

func TestRowActionLayoutMatchesCanonical(t *testing.T) {
	yaml := readCanonicalYAML(t)
	block := topLevelYAMLBlock(yaml, "row_shape")
	if !strings.Contains(block, "two_labelled: even_columns") {
		t.Error("canonical row_shape.actions.two_labelled must be even_columns")
	}
	if !strings.Contains(block, "otherwise: left_at_label_width") {
		t.Error("canonical row_shape.actions.otherwise must be left_at_label_width")
	}
	if RowActionLayoutFor(2) != EvenColumns {
		t.Error("exactly two labelled controls must lay out as even columns")
	}
	for _, n := range []int{0, 1, 3, 4} {
		if RowActionLayoutFor(n) != LeftAtLabelWidth {
			t.Errorf("RowActionLayoutFor(%d) should be left_at_label_width", n)
		}
	}
}
