package domain

import (
	"regexp"
	"strings"
)

var stateGuardPattern = regexp.MustCompile(`^(?:[0-9a-f]{40}|[0-9a-f]{64})$`)

func ParseStateGuard(output string) string {
	var found []string
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSuffix(line, "\r")
		if strings.HasPrefix(line, "guard\t") {
			found = append(found, strings.TrimPrefix(line, "guard\t"))
		}
	}
	if len(found) == 1 && stateGuardPattern.MatchString(found[0]) {
		return found[0]
	}
	return ""
}

// StateToken is the fingerprint {branch?, tip?, situation} captured when a
// confirmation overlay opens and revalidated INSIDE the mutation lock,
// right before the spawn (data-model.md § StateToken). It is what stops a
// mutation from firing against stale data when the repository changed
// between the gesture and the "yes" — a real window in a TUI with
// watching, more than in an IDE, because the panel may have already
// repainted while the overlay sat open.
type StateToken struct {
	ContinueGuard string
	Guard         string
	Branch        string
	HasBranch     bool
	Tip           string
	HasTip        bool
	Situation     Situation
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
	return a.Guard == b.Guard && a.ContinueGuard == b.ContinueGuard
}
