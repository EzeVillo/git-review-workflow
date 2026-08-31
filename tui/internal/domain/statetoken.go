package domain

// StateToken is the fingerprint {branch?, tip?, situation} captured when a
// confirmation overlay opens and revalidated INSIDE the mutation lock,
// right before the spawn (data-model.md § StateToken). It is what stops a
// mutation from firing against stale data when the repository changed
// between the gesture and the "yes" — a real window in a TUI with
// watching, more than in an IDE, because the panel may have already
// repainted while the overlay sat open.
type StateToken struct {
	Branch    string
	HasBranch bool
	Tip       string
	HasTip    bool
	Situation Situation
}

// Matches reports whether two tokens describe the same state. Two absent
// branches (or tips) compare equal to each other; an absent one never
// matches a present one, even an empty string — HasBranch/HasTip exist so
// "no branch" and "branch is the empty string" cannot be confused.
func (a StateToken) Matches(b StateToken) bool {
	if a.Situation != b.Situation {
		return false
	}
	if a.HasBranch != b.HasBranch || (a.HasBranch && a.Branch != b.Branch) {
		return false
	}
	if a.HasTip != b.HasTip || (a.HasTip && a.Tip != b.Tip) {
		return false
	}
	return true
}
