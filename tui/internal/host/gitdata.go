package host

import (
	"context"
	"path/filepath"
	"strings"
)

// GitDirs is the one `rev-parse` call's answer this whole client relies on
// (contracts/cli-invocation.md § Git de apoyo, contracts/refresh.md § Las
// seis raíces): the process's own gitdir, the common gitdir a linked
// worktree shares with its siblings, and the toplevel. Watching the wrong
// one of the first two leaves half the panel dead inside a worktree — they
// are genuinely different directories there, and only git can tell them
// apart.
type GitDirs struct {
	GitDir       string
	GitCommonDir string
	Toplevel     string
}

// ResolveGitDirs runs `git rev-parse --git-dir --git-common-dir
// --show-toplevel` — ONE invocation, never `--path-format=absolute` (git
// 2.31+; this project declares 2.23+) — and resolves whatever comes back
// relative against cwd. ok is false when the process is not standing inside
// a git repository at all, or the probe failed for any other reason
// (SituationForMissingRepo covers both: contracts/cli-invocation.md places
// "no repository" ahead of even the version probe).
func ResolveGitDirs(ctx context.Context, cwd string) (GitDirs, Result, bool) {
	res := InvokeSupportGit(ctx, []string{"rev-parse", "--git-dir", "--git-common-dir", "--show-toplevel"})
	if res.TimedOut || res.SpawnFailed || res.ExitCode != 0 {
		return GitDirs{}, res, false
	}
	lines := strings.Split(strings.ReplaceAll(strings.TrimRight(res.Stdout, "\n"), "\r\n", "\n"), "\n")
	if len(lines) != 3 {
		return GitDirs{}, res, false
	}
	resolve := func(p string) string {
		var resolved string
		if filepath.IsAbs(p) {
			resolved = filepath.Clean(p)
		} else {
			resolved = filepath.Clean(filepath.Join(cwd, p))
		}
		// Git may spell one physical Windows directory differently depending
		// on the worktree from which rev-parse ran (a long path in one result,
		// an equivalent DOS 8.3 alias in another). Watch roots and their
		// de-duplication need one physical spelling, so canonicalize each
		// existing rev-parse result at this host boundary. Keep the cleaned
		// path if the filesystem cannot resolve it: rev-parse already answered
		// successfully, and losing that useful result merely because a later
		// filesystem lookup failed would misclassify a repository as missing.
		if canonical, err := filepath.EvalSymlinks(resolved); err == nil {
			return canonical
		}
		return resolved
	}
	return GitDirs{
		GitDir:       resolve(lines[0]),
		GitCommonDir: resolve(lines[1]),
		Toplevel:     resolve(lines[2]),
	}, res, true
}
