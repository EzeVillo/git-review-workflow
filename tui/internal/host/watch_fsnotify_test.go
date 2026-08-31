// This is the ONLY test file allowed to instantiate the real watcher
// (contracts/refresh.md § Cómo se apaga entera) — it runs with the
// vigilancia explicitly on, against real git repositories under
// t.TempDir(). See T062 / watch.go's own comment for the rule this file is
// the deliberate exception to: nowhere ELSE in this module may a test wait
// on a real filesystem event to synchronize.
package host

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func startFsnotifyWatcher(t *testing.T, gitDir, gitCommonDir string, draftPaths []string) <-chan struct{} {
	t.Helper()
	w := &fsnotifyWatcher{}
	ch, err := w.Start(context.Background(), gitDir, gitCommonDir, draftPaths)
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { _ = w.Stop() })
	return ch
}

// expectEvent waits up to timeout for one coalesced signal. 2s comfortably
// clears DebounceCeilingMillis (1s) plus scheduling slack in a container,
// while staying well short of what would make the suite slow.
func expectEvent(t *testing.T, ch <-chan struct{}, timeout time.Duration) {
	t.Helper()
	select {
	case <-ch:
	case <-time.After(timeout):
		t.Fatal("timed out waiting for a watch event")
	}
}

// expectNoEvent confirms coalescing: nothing arrives within wait, which
// only needs to clear DebounceMillis (200ms) with a margin, never seconds.
func expectNoEvent(t *testing.T, ch <-chan struct{}, wait time.Duration) {
	t.Helper()
	select {
	case <-ch:
		t.Fatal("received an unexpected extra watch event")
	case <-time.After(wait):
	}
}

// drainSettled consumes any further signals until the channel has been
// quiet for `quiet`. Used only where a test needs a clean slate before a
// NEGATIVE assertion right after a positive one: a single real git
// operation can occasionally straddle the debounce ceiling under a slow
// filesystem (a bind-mounted Docker volume, most commonly) and produce a
// second coalesced signal for what is logically one mutation — draining
// here keeps that timing noise from being misread as the NEXT step's
// mutation firing when it should not have.
func drainSettled(t *testing.T, ch <-chan struct{}, quiet time.Duration) {
	t.Helper()
	for {
		select {
		case <-ch:
		case <-time.After(quiet):
			return
		}
	}
}

// --- agujero 1: rename atómico ----------------------------------------------

// git config rewrites .git/config via a temp file + rename, which replaces
// the watched file's inode rather than writing into it — a watch on the
// FILE itself would go silently dead after the first rename. Doing this
// twice is the actual gate: the second rename proves the watch on the
// DIRECTORY survived the first one.
func TestRenameAtomicGitConfigFiresTwice(t *testing.T) {
	dir := initRepo(t)
	dirs := mustGitDirs(t, dir)
	ch := startFsnotifyWatcher(t, dirs.GitDir, dirs.GitCommonDir, nil)

	runGit(t, dir, "config", "reviewworkflow.base", "main")
	expectEvent(t, ch, 2*time.Second)

	runGit(t, dir, "config", "reviewworkflow.base", "develop")
	expectEvent(t, ch, 2*time.Second)
}

// --- agujero 2: refs empaquetados --------------------------------------------

func TestPackedRefsCreateAndDelete(t *testing.T) {
	dir := initRepo(t)
	sha := strings.TrimSpace(runGit(t, dir, "rev-parse", "HEAD"))
	runGit(t, dir, "update-ref", "refs/heads/review/feature", sha)

	dirs := mustGitDirs(t, dir)
	ch := startFsnotifyWatcher(t, dirs.GitDir, dirs.GitCommonDir, nil)

	runGit(t, dir, "pack-refs", "--all")
	expectEvent(t, ch, 2*time.Second)

	runGit(t, dir, "update-ref", "-d", "refs/heads/review/feature")
	expectEvent(t, ch, 2*time.Second)
}

// --- agujero 3: anidamiento ---------------------------------------------------

// Writing a brand-new draft for a slash-bearing branch creates
// review-walkthrough/ AND review-walkthrough/feature/ in one go — neither
// exists when the watcher starts. The single event this asserts is the
// whole point: the closure discovers the new subdirectories and re-reads,
// it does not explode into one event per level of nesting.
func TestNestedDraftDirectoryOneEvent(t *testing.T) {
	dir := initRepo(t)
	dirs := mustGitDirs(t, dir)
	draftPath := filepath.Join(dirs.GitDir, "review-walkthrough", "feature", "foo.md")

	ch := startFsnotifyWatcher(t, dirs.GitDir, dirs.GitCommonDir, []string{draftPath})

	if err := os.MkdirAll(filepath.Dir(draftPath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(draftPath, []byte("# draft\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	expectEvent(t, ch, 2*time.Second)
	expectNoEvent(t, ch, 400*time.Millisecond)
}

// Same shape, on the refs/ side: refs/review-edits/<src>/<step> with a
// slash-bearing <src> nests three levels deep, exactly at RootRefs' depth
// budget — advancing one step in step mode must still coalesce to one
// event, not one per created directory.
func TestNestedReviewEditsRefOneEvent(t *testing.T) {
	dir := initRepo(t)
	sha := strings.TrimSpace(runGit(t, dir, "rev-parse", "HEAD"))
	dirs := mustGitDirs(t, dir)

	ch := startFsnotifyWatcher(t, dirs.GitDir, dirs.GitCommonDir, nil)

	runGit(t, dir, "update-ref", "refs/review-edits/feature/foo/1", sha)
	expectEvent(t, ch, 2*time.Second)
	expectNoEvent(t, ch, 400*time.Millisecond)
}

// --- agujero 4: backend reftable ---------------------------------------------

func TestReftableBackendStartsWithoutErrorAndFires(t *testing.T) {
	dir := t.TempDir()
	cmd := exec.Command("git", "init", "-q", "-b", "main", "--ref-format=reftable", ".")
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Skipf("this git does not support --ref-format=reftable (documented limitation, not a failure): %v\n%s", err, out)
	}
	runGit(t, dir, "config", "user.email", "t@example.com")
	runGit(t, dir, "config", "user.name", "T")
	if err := os.WriteFile(filepath.Join(dir, "f.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, dir, "add", "f.txt")
	runGit(t, dir, "commit", "-q", "-m", "init")

	dirs := mustGitDirs(t, dir)
	ch := startFsnotifyWatcher(t, dirs.GitDir, dirs.GitCommonDir, nil)

	runGit(t, dir, "config", "reviewworkflow.base", "main")
	expectEvent(t, ch, 2*time.Second)
}

// --- T059: la sexta raíz ------------------------------------------------------

// Two checkouts in a row must each produce their OWN event: the second is
// the actual gate, proving the watch on <git-dir> survived HEAD's own
// rename (HEAD.lock -> HEAD), the same mechanism as agujero 1.
func TestHeadCheckoutFiresTwice(t *testing.T) {
	dir := initRepo(t)
	runGit(t, dir, "branch", "other")

	dirs := mustGitDirs(t, dir)
	ch := startFsnotifyWatcher(t, dirs.GitDir, dirs.GitCommonDir, nil)

	runGit(t, dir, "checkout", "-q", "other")
	expectEvent(t, ch, 2*time.Second)

	runGit(t, dir, "checkout", "-q", "main")
	expectEvent(t, ch, 2*time.Second)
}

// --- T059: worktree enlazado ---------------------------------------------------

// The three-part gate from contracts/refresh.md: common-dir events reach a
// linked worktree's watcher, the draft root comes from the WORKTREE's own
// gitdir, and root F tracks <git-dir> — never <git-common-dir> — so a
// checkout in the worktree fires while the same kind of checkout in the
// main worktree does not.
func TestLinkedWorktreeRootFTracksItsOwnGitDir(t *testing.T) {
	main := initRepo(t)
	runGit(t, main, "branch", "wtbranch")
	runGit(t, main, "branch", "wtbranch2")
	runGit(t, main, "branch", "second-branch")

	wtPath := filepath.Join(t.TempDir(), "wt")
	runGit(t, main, "worktree", "add", "-q", wtPath, "wtbranch")

	wtDirs := mustGitDirs(t, wtPath)
	if wtDirs.GitDir == wtDirs.GitCommonDir {
		t.Fatalf("expected a linked worktree to have GitDir != GitCommonDir, got both = %s", wtDirs.GitDir)
	}

	draftPath := filepath.Join(wtDirs.GitDir, "review-walkthrough", "wtbranch.md")
	ch := startFsnotifyWatcher(t, wtDirs.GitDir, wtDirs.GitCommonDir, []string{draftPath})

	// (a) the shared common directory's events reach this worktree's watcher.
	runGit(t, main, "config", "reviewworkflow.base", "main")
	expectEvent(t, ch, 2*time.Second)

	// (b) the draft root is resolved against the WORKTREE's own gitdir, not
	// the main one — writing it must be seen.
	if err := os.MkdirAll(filepath.Dir(draftPath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(draftPath, []byte("# draft\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	expectEvent(t, ch, 2*time.Second)

	// (c) a checkout of an EXISTING branch in THIS worktree touches only
	// its own HEAD (no refs/ mutation) and fires...
	runGit(t, wtPath, "checkout", "-q", "wtbranch2")
	expectEvent(t, ch, 2*time.Second)
	// A first checkout inside a freshly-added worktree can lazily create
	// its own logs/ directory alongside HEAD's rename, occasionally
	// splitting into a second coalesced signal under a slow bind-mounted
	// Docker volume. Settling here — strictly longer than
	// DebounceCeilingMillis — keeps that timing noise from being
	// misattributed to the NEGATIVE check right below.
	drainSettled(t, ch, 1100*time.Millisecond)

	// ...but the same kind of checkout in the MAIN worktree does not: it
	// rewrites main's own HEAD, a file this worktree's watcher never
	// watches (FR-080 — root F is <git-dir>, never <git-common-dir>).
	runGit(t, main, "checkout", "-q", "second-branch")
	expectNoEvent(t, ch, 700*time.Millisecond)
}
