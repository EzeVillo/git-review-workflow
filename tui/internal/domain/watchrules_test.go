package domain

import "testing"

// tags/ in a large repository is half the directory budget on its own —
// this is the one exclusion the contract calls out by name.
func TestExcludedRefPrefixes(t *testing.T) {
	excluded := []string{
		"tags/v1.0.0",
		"notes/commits",
		"stash",
		"bisect/log",
		"rewritten/abc123",
	}
	for _, p := range excluded {
		if !IsExcludedRefPrefix(p) {
			t.Errorf("%q should be excluded from the watch closure", p)
		}
		if IsAllowedRefPrefix(p) {
			t.Errorf("%q must not ALSO be in the refs/ allowlist", p)
		}
	}
}

func TestAllowedRefPrefixes(t *testing.T) {
	allowed := []string{
		"heads/review/feature",
		"remotes/origin/main",
		"review-edits/feature/2",
		"review-saved-edits/feature/1",
	}
	for _, p := range allowed {
		if !IsAllowedRefPrefix(p) {
			t.Errorf("%q should be in the refs/ closure allowlist", p)
		}
		if IsExcludedRefPrefix(p) {
			t.Errorf("%q must not ALSO be excluded", p)
		}
	}
}

func TestAnUnlistedRefPrefixIsNeitherExcludedNorAllowed(t *testing.T) {
	// A future git ref namespace this table does not know about yet: the
	// closure simply does not descend into it (unmentioned is not the same
	// as excluded, and it is definitely not the same as allowed).
	if IsAllowedRefPrefix("some-future-namespace/x") {
		t.Error("an unlisted prefix must not be treated as allowed")
	}
}

func TestBudgetAndTimingConstants(t *testing.T) {
	if MaxWatchedDirs != 512 {
		t.Errorf("MaxWatchedDirs = %d, want 512", MaxWatchedDirs)
	}
	if DebounceMillis != 200 {
		t.Errorf("DebounceMillis = %d, want 200", DebounceMillis)
	}
	if DebounceCeilingMillis != 1000 {
		t.Errorf("DebounceCeilingMillis = %d, want 1000", DebounceCeilingMillis)
	}
	if MutationSilenceWindowMillis != 600 {
		t.Errorf("MutationSilenceWindowMillis = %d, want 600", MutationSilenceWindowMillis)
	}
}

func TestSixRootsDeclared(t *testing.T) {
	if len(WatchRoots) != 6 {
		t.Fatalf("expected 6 watch roots, got %d", len(WatchRoots))
	}
	// A and F are both depth 0 with a name filter — the same shape, not a
	// new mechanism, per contracts/refresh.md.
	if WatchRoots[RootGitCommonDir].Depth != 0 || WatchRoots[RootGitDir].Depth != 0 {
		t.Error("RootGitCommonDir and RootGitDir must both be depth 0")
	}
	if len(WatchRoots[RootGitDir].NameFilter) != 1 || WatchRoots[RootGitDir].NameFilter[0] != "HEAD" {
		t.Errorf("RootGitDir must filter to exactly {HEAD}, got %v", WatchRoots[RootGitDir].NameFilter)
	}
	// refs/ is the only root with a prefix allowlist.
	for id, spec := range WatchRoots {
		if id == RootRefs {
			continue
		}
		if len(spec.PrefixAllowlist) != 0 {
			t.Errorf("root %v must not carry a prefix allowlist, only RootRefs does", id)
		}
	}
}
