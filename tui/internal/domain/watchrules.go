package domain

// WatchRootID names one of the six seed roots BuildWatchSet starts from
// (contracts/refresh.md § Las seis raíces, FR-033, FR-080). These are pure
// data: no filesystem, no fsnotify — internal/host/watchset.go (Phase 5)
// resolves them against real paths and applies the closure this file only
// describes the rules for.
type WatchRootID int

const (
	// RootGitCommonDir (A): <git-common-dir>/, filtered by name to
	// {config, packed-refs}.
	RootGitCommonDir WatchRootID = iota
	// RootRefs (B): <git-common-dir>/refs/, unfiltered by name but bounded
	// by PrefixAllowlist.
	RootRefs
	// RootReftable (C): <git-common-dir>/reftable/, only if it exists —
	// flat by design, so its own depth is 0.
	RootReftable
	// RootOwnDrafts (D): <git-dir>/review-walkthrough/, from the `draft`
	// record's own reported path (FR-036), filtered to *.md.
	RootOwnDrafts
	// RootSavedDrafts (E): <git-dir>/review-saved-walkthrough/, same shape
	// as D.
	RootSavedDrafts
	// RootGitDir (F): <git-dir>/, filtered by name to {HEAD}. Goes over
	// <git-dir> and NOT <git-common-dir> because each worktree has its own
	// HEAD, and the one that matters to the panel is the one for the
	// worktree the process is standing in (FR-080).
	RootGitDir
)

// WatchRootSpec is one seed root's closure shape: how deep it descends and,
// for the one root that needs it, which refs/-relative prefixes the
// closure is allowed to enter.
type WatchRootSpec struct {
	// Depth: 0 means the root directory alone, no descent.
	Depth int
	// PrefixAllowlist: non-empty only for RootRefs. A subdirectory whose
	// relative path (from the root) does not start with one of these is
	// never added to the watch set.
	PrefixAllowlist []string
	// NameFilter: the set of filenames (or "*.md" glob) this root's watch
	// reacts to. Empty means "no filename filtering" (used only for
	// RootRefs and RootReftable, which are watched as bare directories).
	NameFilter []string
}

// WatchRoots is every root's spec, keyed by WatchRootID.
var WatchRoots = map[WatchRootID]WatchRootSpec{
	RootGitCommonDir: {Depth: 0, NameFilter: []string{"config", "packed-refs"}},
	RootRefs:         {Depth: 3, PrefixAllowlist: []string{"heads/", "remotes/", "review-edits/", "review-saved-edits/"}},
	RootReftable:     {Depth: 0},
	RootOwnDrafts:    {Depth: 3, NameFilter: []string{"*.md"}},
	RootSavedDrafts:  {Depth: 3, NameFilter: []string{"*.md"}},
	RootGitDir:       {Depth: 0, NameFilter: []string{"HEAD"}},
}

// ExcludedRefPrefixes are refs/-relative prefixes the closure deliberately
// never enters: none of them participates in a review's state, and tags/
// alone can be half the directory budget in a large repository.
var ExcludedRefPrefixes = []string{"tags/", "notes/", "stash", "bisect/", "rewritten/"}

// MaxWatchedDirs is the closure's budget (contracts/refresh.md). Exceeding
// it keeps the seeds and the shallowest entries and leaves a note in the
// invocation log — it is NEVER an error (FR-064).
const MaxWatchedDirs = 512

// DebounceMillis / DebounceCeilingMillis: a pure trailing debounce starves
// under a continuous stream of writes — exactly what an agent filling a
// draft does (User Story 1). The ceiling is what keeps the panel updating
// roughly once a second during that instead of only once it stops.
const (
	DebounceMillis        = 200
	DebounceCeilingMillis = 1000
)

// MutationSilenceWindowMillis is how long watchMsg{} stays suppressed after
// a mutation ends, layered on top of the one immediate read the lock
// already does: long enough to cover the mutation's OWN trailing writes
// (debounce + half the ceiling, plus a margin) without leaving a real gap
// for a change that lands from somewhere else during that window.
const MutationSilenceWindowMillis = 600

func hasPrefix(s, prefix string) bool {
	return len(s) >= len(prefix) && s[:len(prefix)] == prefix
}

// IsExcludedRefPrefix reports whether a refs/-relative path falls under one
// of the deliberately excluded prefixes.
func IsExcludedRefPrefix(relPath string) bool {
	for _, p := range ExcludedRefPrefixes {
		if hasPrefix(relPath, p) {
			return true
		}
	}
	return false
}

// IsAllowedRefPrefix reports whether a refs/-relative path is inside
// RootRefs' closure allowlist.
func IsAllowedRefPrefix(relPath string) bool {
	for _, p := range WatchRoots[RootRefs].PrefixAllowlist {
		if hasPrefix(relPath, p) {
			return true
		}
	}
	return false
}
