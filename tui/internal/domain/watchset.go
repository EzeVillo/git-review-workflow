package domain

// WatchDir is one directory internal/host's watcher should hold an
// fsnotify watch on, plus the filenames inside it that actually matter
// (contracts/refresh.md § Debounce y coalescencia: the watch itself is
// never selective, only the decision to count an event towards the
// coalesced signal is). Two plain strings, so a WatchDir is comparable
// with == — no filesystem, no fsnotify, just data, same as PorcelainResult
// or ConfigPorcelainResult elsewhere in this package.
type WatchDir struct {
	// Path: absolute, cleaned.
	Path string
	// NameFilter: the root's WatchRootSpec.NameFilter (watchrules.go),
	// canonicalized to a single sorted "|"-joined string so two WatchDir
	// values are comparable with == (a []string field would not be).
	// Empty means "no filtering by name" — RootRefs and RootReftable are
	// watched as bare directories, so any entry inside them counts.
	// "*.md" is a literal member for RootOwnDrafts/RootSavedDrafts: a
	// suffix match, not a filename.
	NameFilter string
}

// WatchSet is the closed, deduplicated set BuildWatchSet
// (internal/host/watchset.go) resolves from the six seed roots. Ordered by
// Path (see Sort) so that "did the set change" is a slice comparison, never
// a directory walk (contracts/refresh.md § Cómo se arma y se rearma).
type WatchSet struct {
	Dirs []WatchDir
}

// Sort orders Dirs by Path, in place. BuildWatchSet always returns an
// already-sorted WatchSet; exported so a test assembling one by hand can
// match that order before comparing.
func (s *WatchSet) Sort() {
	// Insertion sort: WatchSet sizes are bounded by MaxWatchedDirs (512)
	// and, for every test and every real repository this client watches,
	// far smaller — a stdlib sort import is not worth it for this.
	for i := 1; i < len(s.Dirs); i++ {
		for j := i; j > 0 && s.Dirs[j].Path < s.Dirs[j-1].Path; j-- {
			s.Dirs[j], s.Dirs[j-1] = s.Dirs[j-1], s.Dirs[j]
		}
	}
}

// Equal reports whether two sets name the same directories with the same
// filters, in the same order. Both sides are expected to already be
// sorted (Sort) — Equal does not sort for you, so that comparing is always
// the cheap, allocation-free walk the contract asks for.
func (s WatchSet) Equal(other WatchSet) bool {
	if len(s.Dirs) != len(other.Dirs) {
		return false
	}
	for i := range s.Dirs {
		if s.Dirs[i] != other.Dirs[i] {
			return false
		}
	}
	return true
}
