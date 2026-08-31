package host

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

// mustGitDirs resolves dir's real GitDir/GitCommonDir/Toplevel by actually
// asking git, the same way host.ReadState does — never assembled from a
// guess at dir's layout. t.Chdir is required because runProcess (invoke.go)
// spawns with the PROCESS's own cwd, exactly like gitdata_test.go's own
// TestResolveGitDirs* already rely on.
func mustGitDirs(t *testing.T, dir string) GitDirs {
	t.Helper()
	t.Chdir(dir)
	dirs, _, ok := ResolveGitDirs(context.Background(), dir)
	if !ok {
		t.Fatalf("ResolveGitDirs failed for %s", dir)
	}
	return dirs
}

// T055's own gate: outside a linked worktree, --git-dir and
// --git-common-dir resolve to the exact same directory, so BuildWatchSet
// must list it ONCE, with the UNION of root A's and root F's filters —
// never two entries, and never just one of the two filters surviving
// (contracts/refresh.md § Dedup).
func TestBuildWatchSetDedupsGitDirAndCommonDirOutsideWorktree(t *testing.T) {
	dir := initRepo(t)
	dirs := mustGitDirs(t, dir)
	if dirs.GitDir != dirs.GitCommonDir {
		t.Fatalf("test setup: expected GitDir == GitCommonDir outside a worktree, got %+v", dirs)
	}

	set := BuildWatchSet(dirs.GitDir, dirs.GitCommonDir, nil)

	var found *domain.WatchDir
	count := 0
	for i := range set.Dirs {
		if set.Dirs[i].Path == dirs.GitDir {
			count++
			found = &set.Dirs[i]
		}
	}
	if count != 1 {
		t.Fatalf("<git-dir> must appear exactly once in the watch set, found %d times", count)
	}

	got := map[string]bool{}
	for _, part := range strings.Split(found.NameFilter, "|") {
		got[part] = true
	}
	want := map[string]bool{"config": true, "packed-refs": true, "HEAD": true}
	if len(got) != len(want) {
		t.Fatalf("NameFilter = %q, want the union {config, packed-refs, HEAD}", found.NameFilter)
	}
	for k := range want {
		if !got[k] {
			t.Errorf("NameFilter %q is missing %q", found.NameFilter, k)
		}
	}
}

// FR-064: a root that does not exist on disk yet (reftable/ in a plain
// repo) must be skipped in silence, never cause an error or a panic.
func TestBuildWatchSetIgnoresANonexistentRootSilently(t *testing.T) {
	dir := initRepo(t)
	dirs := mustGitDirs(t, dir)

	set := BuildWatchSet(dirs.GitDir, dirs.GitCommonDir, nil)
	for _, d := range set.Dirs {
		if filepath.Base(d.Path) == "reftable" {
			t.Errorf("reftable/ must not be watched when it does not exist: %+v", d)
		}
	}
}

// FR-036: the D/E root's literal directory name comes from the reported
// draft path itself, and the root is only watched once it actually exists
// on disk — before that, BuildWatchSet must not error, just omit it.
func TestBuildWatchSetDraftRootComesFromReportedPath(t *testing.T) {
	dir := initRepo(t)
	dirs := mustGitDirs(t, dir)
	draftPath := filepath.Join(dirs.GitDir, "review-walkthrough", "feature", "foo.md")
	want := filepath.Join(dirs.GitDir, "review-walkthrough")

	set := BuildWatchSet(dirs.GitDir, dirs.GitCommonDir, []string{draftPath})
	for _, d := range set.Dirs {
		if d.Path == want {
			t.Fatalf("review-walkthrough/ does not exist yet and must not be added: %+v", d)
		}
	}

	if err := os.MkdirAll(want, 0o755); err != nil {
		t.Fatal(err)
	}
	set2 := BuildWatchSet(dirs.GitDir, dirs.GitCommonDir, []string{draftPath})
	found := false
	for _, d := range set2.Dirs {
		if d.Path == want {
			found = true
			if d.NameFilter != "*.md" {
				t.Errorf("review-walkthrough/ NameFilter = %q, want %q", d.NameFilter, "*.md")
			}
		}
	}
	if !found {
		t.Fatal("review-walkthrough/ must be watched once it exists on disk")
	}
}
