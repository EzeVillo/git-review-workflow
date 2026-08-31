package host

import (
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/EzeVillo/git-review-workflow/tui/internal/domain"
)

// BuildWatchSet resolves the six roots of contracts/refresh.md § Las seis
// raíces against a REAL gitdir pair into a closed, deduplicated, sorted
// domain.WatchSet: it applies domain/watchrules.go's PURE rules (depth,
// prefix allowlist, budget, name filters) against the actual filesystem —
// os.Stat for root C's existence check, os.ReadDir for the directory
// closure. That filesystem work is exactly why this function lives in
// internal/host and not internal/domain (see tasks.md T055's design note):
// watchrules.go stays free of any os/exec/fsnotify/filesystem call, and
// this is the one place that turns its tables into concrete paths.
//
// draftPaths are absolute .md file paths exactly as the CLI already
// reported them (host.ReadResult's Config.Drafts[].Path / Status.DraftPath)
// — never reassembled from a guess at the gitdir's layout (FR-036). Each
// one's watched root is derived by walking up to the path component
// directly under gitDir (".../review-walkthrough/feature/foo.md" yields
// ".../review-walkthrough"), so the literal directory name comes from what
// the CLI told us, never from a string this package hardcodes.
//
// A root that does not exist on disk — root C most commonly, or D/E before
// any draft was ever created anywhere in the repository — is dropped
// silently and never stops the others from being built (FR-064).
func BuildWatchSet(gitDir, gitCommonDir string, draftPaths []string) domain.WatchSet {
	type seedInfo struct {
		spec      domain.WatchRootSpec
		filterKey string
	}
	var seedOrder []string
	seedByPath := map[string]seedInfo{}

	addSeed := func(path string, spec domain.WatchRootSpec) {
		if path == "" {
			return
		}
		path = filepath.Clean(path)
		key := nameFilterKey(spec.NameFilter)
		if existing, ok := seedByPath[path]; ok {
			// Dedup: the raíz repetida's filter joins the one already
			// there (contracts/refresh.md § Dedup) — A and F outside a
			// linked worktree is the case this exists for.
			existing.filterKey = mergeFilterKeys(existing.filterKey, key)
			seedByPath[path] = existing
			return
		}
		seedByPath[path] = seedInfo{spec: spec, filterKey: key}
		seedOrder = append(seedOrder, path)
	}

	addSeed(gitCommonDir, domain.WatchRoots[domain.RootGitCommonDir])
	addSeed(filepath.Join(gitCommonDir, "refs"), domain.WatchRoots[domain.RootRefs])
	if reftableDir := filepath.Join(gitCommonDir, "reftable"); dirExists(reftableDir) {
		addSeed(reftableDir, domain.WatchRoots[domain.RootReftable])
	}
	for _, root := range draftRoots(gitDir, draftPaths) {
		// D and E share one closure shape (Depth 3, *.md) — which of the
		// two a given draftPath structurally belongs to only matters for
		// documentation, never for how it gets watched.
		addSeed(root, domain.WatchRoots[domain.RootOwnDrafts])
	}
	addSeed(gitDir, domain.WatchRoots[domain.RootGitDir])

	type frontierItem struct {
		path, rel string
		depth     int
		spec      domain.WatchRootSpec
		filterKey string
	}
	var frontier []frontierItem
	for _, p := range seedOrder {
		info := seedByPath[p]
		frontier = append(frontier, frontierItem{path: p, rel: "", depth: 0, spec: info.spec, filterKey: info.filterKey})
	}

	var dirs []domain.WatchDir
	budget := domain.MaxWatchedDirs

	// Breadth-first over the whole forest of seeds together (not seed by
	// seed): "al pasarse [el presupuesto], se conservan las semillas y las
	// entradas más someras" (contracts/refresh.md § Presupuesto) means
	// shallow wins globally, not per root.
	for len(frontier) > 0 && budget > 0 {
		var next []frontierItem
		for _, it := range frontier {
			if budget <= 0 {
				break
			}
			if !dirExists(it.path) {
				continue // FR-064: ignored in silence, does not block the rest
			}
			dirs = append(dirs, domain.WatchDir{Path: it.path, NameFilter: it.filterKey})
			budget--

			if it.depth >= it.spec.Depth {
				continue
			}
			entries, err := os.ReadDir(it.path)
			if err != nil {
				continue
			}
			for _, e := range entries {
				if !e.IsDir() {
					continue
				}
				childRel := it.rel + e.Name() + "/"
				if len(it.spec.PrefixAllowlist) > 0 && !domain.IsAllowedRefPrefix(childRel) {
					// Default-deny under refs/: an unlisted or explicitly
					// excluded prefix is never descended into
					// (TestAnUnlistedRefPrefixIsNeitherExcludedNorAllowed's
					// domain-level guarantee, applied here).
					continue
				}
				next = append(next, frontierItem{
					path:      filepath.Join(it.path, e.Name()),
					rel:       childRel,
					depth:     it.depth + 1,
					spec:      it.spec,
					filterKey: it.filterKey,
				})
			}
		}
		frontier = next
	}

	set := domain.WatchSet{Dirs: dirs}
	set.Sort()
	return set
}

// dirExists reports whether path exists AND is a directory — a plain file
// (or a dangling symlink) is not something the watcher can Add.
func dirExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

// draftRoots derives the D/E seed directories straight from the CLI-reported
// draft paths (FR-036): a root is whatever path component sits directly
// under gitDir. This function never spells out "review-walkthrough" or
// "review-saved-walkthrough" itself — it reads whichever one applies off
// the reported path, so a rename of either directory on the CLI side would
// not require a change here. Paths that do not resolve under gitDir at all
// are skipped defensively; that should never happen with a well-formed
// report.
func draftRoots(gitDir string, draftPaths []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, p := range draftPaths {
		if p == "" {
			continue
		}
		rel, err := filepath.Rel(gitDir, p)
		if err != nil || rel == "." || strings.HasPrefix(rel, "..") {
			continue
		}
		first, _, _ := strings.Cut(filepath.ToSlash(rel), "/")
		if first == "" {
			continue
		}
		root := filepath.Join(gitDir, first)
		if !seen[root] {
			seen[root] = true
			out = append(out, root)
		}
	}
	return out
}

// nameFilterKey canonicalizes a WatchRootSpec.NameFilter into WatchDir's
// comparable string form: sorted and "|"-joined. "|" cannot appear inside a
// single path segment on Windows, macOS or Linux, so it can never collide
// with a real filter entry ("config", "packed-refs", "HEAD", "*.md").
func nameFilterKey(filter []string) string {
	if len(filter) == 0 {
		return ""
	}
	sorted := append([]string(nil), filter...)
	sort.Strings(sorted)
	return strings.Join(sorted, "|")
}

// mergeFilterKeys unions two canonical filter keys back into one,
// deduplicated and re-sorted — the "unión de filtros" a directory gets when
// two seed roots resolve to the same path (contracts/refresh.md § Dedup).
// An empty key means "no filtering" and is absorbing: unioning it with
// anything else must still mean "no filtering", or A merging with a
// hypothetical unfiltered root would wrongly start filtering it.
func mergeFilterKeys(a, b string) string {
	if a == "" || b == "" {
		return ""
	}
	if a == b {
		return a
	}
	set := map[string]bool{}
	for _, part := range strings.Split(a, "|") {
		set[part] = true
	}
	for _, part := range strings.Split(b, "|") {
		set[part] = true
	}
	out := make([]string, 0, len(set))
	for k := range set {
		out = append(out, k)
	}
	sort.Strings(out)
	return strings.Join(out, "|")
}
