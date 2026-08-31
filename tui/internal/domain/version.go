package domain

import (
	"strconv"
	"strings"
)

// MinCLIVersion is this client's own floor (min_cli_version.tui in
// contracts/client-product-surface.yaml, FR-028). It is a floor and nothing
// else: the four clients are expected to diverge, and no gate — here or in
// scripts/check-client-product-surface.mjs — may require them to match.
const MinCLIVersion = "0.8.0"

// Version is a parsed X.Y.Z.
type Version struct {
	Major, Minor, Patch int
}

// ParseVersion parses "X.Y.Z" with non-negative integers. Anything else —
// missing a component, a negative number, trailing garbage — is not a
// version this client can compare, and ok is false.
func ParseVersion(s string) (Version, bool) {
	parts := strings.Split(strings.TrimSpace(s), ".")
	if len(parts) != 3 {
		return Version{}, false
	}
	nums := make([]int, 3)
	for i, p := range parts {
		n, err := strconv.Atoi(p)
		if err != nil || n < 0 {
			return Version{}, false
		}
		nums[i] = n
	}
	return Version{Major: nums[0], Minor: nums[1], Patch: nums[2]}, true
}

// CompareVersions returns -1, 0 or 1 as a is less than, equal to or greater
// than b.
func CompareVersions(a, b Version) int {
	if a.Major != b.Major {
		return sign(a.Major - b.Major)
	}
	if a.Minor != b.Minor {
		return sign(a.Minor - b.Minor)
	}
	return sign(a.Patch - b.Patch)
}

func sign(n int) int {
	switch {
	case n < 0:
		return -1
	case n > 0:
		return 1
	default:
		return 0
	}
}

// IsOutdated reports whether version is older than minVersion, or is not a
// valid X.Y.Z at all. The comparison is a strict FLOOR: there is no
// ceiling, so a CLI newer than the minimum is never reported outdated
// (contracts/cli-invocation.md § Probe de versión).
func IsOutdated(version, minVersion string) bool {
	v, ok := ParseVersion(version)
	if !ok {
		return true
	}
	min, ok := ParseVersion(minVersion)
	if !ok {
		// An unparsable floor is this client's own bug, not the CLI's — but
		// with nothing valid to compare against, "cannot confirm current"
		// is the honest answer, same as an unparsable CLI version.
		return true
	}
	return CompareVersions(v, min) < 0
}
