package ui

import (
	"os"
	"path/filepath"
	"testing"
)

// T050: 11 panel_layout: keys x 2 sizes x 3 modes (default, NO_COLOR forced,
// ASCII glyphs forced) = 66 files, plus the waiting frame at both sizes
// (waiting has no styled or icon content, so its default/-nocolor/-ascii
// renders are byte-identical — one file per size is the whole story) = 68.

type goldenSize struct {
	name       string
	cols, rows int
}

var goldenSizes = []goldenSize{
	{"80x24", 80, 24},
	{"120x40", 120, 40},
}

type goldenMode struct {
	suffix string
	color  bool
	ascii  bool
}

var goldenModes = []goldenMode{
	{suffix: "", color: true, ascii: false},
	{suffix: "-nocolor", color: false, ascii: false},
	{suffix: "-ascii", color: true, ascii: true},
}

func goldenDir() string {
	return filepath.Join("..", "..", "testdata", "golden")
}

func goldenPath(name string) string {
	return filepath.Join(goldenDir(), name+".txt")
}

// TestGoldenFrames renders every (situation, size, mode) combination and
// compares it byte-for-byte against its golden file — or, under `-tags
// goldenupdate -update`, writes it. NEVER derived from a sandbox or a real
// repository: fixtureFor builds every PanelModel by hand, so a golden file
// changes only when render.go or a fixture changes, never on its own.
func TestGoldenFrames(t *testing.T) {
	if shouldUpdateGolden() {
		if err := os.MkdirAll(goldenDir(), 0o755); err != nil {
			t.Fatal(err)
		}
	}

	count := 0
	for _, sit := range allFixtureSituations {
		panel := fixtureFor(sit)
		for _, sz := range goldenSizes {
			for _, mode := range goldenModes {
				if sit == "waiting" && mode.suffix != "" {
					continue
				}
				name := string(sit) + "-" + sz.name + mode.suffix
				count++
				t.Run(name, func(t *testing.T) {
					vp := Viewport{Cols: sz.cols, Rows: sz.rows, Color: mode.color, ASCII: mode.ascii}
					frame, _ := View(panel, vp)
					path := goldenPath(name)

					if shouldUpdateGolden() {
						if err := os.WriteFile(path, []byte(frame), 0o644); err != nil {
							t.Fatal(err)
						}
						return
					}

					want, err := os.ReadFile(path)
					if err != nil {
						t.Fatalf("reading golden file %s: %v\n(regenerate with: go test -tags goldenupdate ./internal/ui -update)", path, err)
					}
					if frame != string(want) {
						t.Errorf("frame does not match %s\n--- got ---\n%s\n--- want ---\n%s", path, frame, string(want))
					}
				})
			}
		}
	}
	if count != 68 {
		t.Fatalf("generated/compared %d golden combinations, want exactly 68", count)
	}
}

// TestGoldenDirHasExactly68Files is the same count, checked the other
// direction — a stray leftover file (a renamed situation, a typo'd suffix)
// would pass TestGoldenFrames (which only ever looks for the names it
// expects) but leave an orphan on disk.
func TestGoldenDirHasExactly68Files(t *testing.T) {
	if shouldUpdateGolden() {
		t.Skip("skipped while regenerating")
	}
	entries, err := os.ReadDir(goldenDir())
	if err != nil {
		t.Fatal(err)
	}
	n := 0
	for _, e := range entries {
		if !e.IsDir() && filepath.Ext(e.Name()) == ".txt" {
			n++
		}
	}
	if n != 68 {
		t.Fatalf("testdata/golden/ has %d .txt files, want exactly 68", n)
	}
}
