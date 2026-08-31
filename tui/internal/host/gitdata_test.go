package host

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func runGit(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return string(out)
}

func initRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	runGit(t, dir, "init", "-q", "-b", "main")
	runGit(t, dir, "config", "user.email", "t@example.com")
	runGit(t, dir, "config", "user.name", "T")
	if err := os.WriteFile(filepath.Join(dir, "f.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, dir, "add", "f.txt")
	runGit(t, dir, "commit", "-q", "-m", "init")
	return dir
}

func TestResolveGitDirsInPlainRepo(t *testing.T) {
	dir := initRepo(t)
	t.Chdir(dir) // the underlying exec spawn uses the PROCESS's cwd, not a param
	dirs, _, ok := ResolveGitDirs(context.Background(), dir)
	if !ok {
		t.Fatal("expected ok for a real repository")
	}
	wantGitDir, err := filepath.EvalSymlinks(filepath.Join(dir, ".git"))
	if err != nil {
		t.Fatal(err)
	}
	gotGitDir, err := filepath.EvalSymlinks(dirs.GitDir)
	if err != nil {
		t.Fatal(err)
	}
	if gotGitDir != wantGitDir {
		t.Errorf("GitDir = %q, want %q", gotGitDir, wantGitDir)
	}
	if dirs.GitDir != dirs.GitCommonDir {
		t.Errorf("outside a linked worktree, GitDir and GitCommonDir must be equal: %+v", dirs)
	}
}

func TestResolveGitDirsOutsideARepository(t *testing.T) {
	dir := t.TempDir() // not a git repository at all
	t.Chdir(dir)
	_, _, ok := ResolveGitDirs(context.Background(), dir)
	if ok {
		t.Fatal("expected ok=false outside a repository")
	}
}

// FR-080: a linked worktree's --git-dir and --git-common-dir are genuinely
// different directories, and watching the wrong one leaves half the panel
// dead — this is the test that would catch swapping them or collapsing them
// into one.
func TestResolveGitDirsDistinguishesLinkedWorktree(t *testing.T) {
	main := initRepo(t)
	wtParent := t.TempDir()
	wt := filepath.Join(wtParent, "wt")
	runGit(t, main, "worktree", "add", "-q", wt, "-b", "wt-branch")

	t.Chdir(wt)
	dirs, _, ok := ResolveGitDirs(context.Background(), wt)
	if !ok {
		t.Fatal("expected ok inside the linked worktree")
	}
	if dirs.GitDir == dirs.GitCommonDir {
		t.Fatalf("inside a linked worktree, GitDir must differ from GitCommonDir: %+v", dirs)
	}
	t.Chdir(main)
	mainDirs, _, ok := ResolveGitDirs(context.Background(), main)
	if !ok {
		t.Fatal("expected ok in the main worktree")
	}
	if dirs.GitCommonDir != mainDirs.GitCommonDir {
		t.Errorf("the two worktrees must share one GitCommonDir: %q vs %q", dirs.GitCommonDir, mainDirs.GitCommonDir)
	}
	if dirs.GitDir == mainDirs.GitDir {
		t.Error("the two worktrees must NOT share GitDir")
	}
}
