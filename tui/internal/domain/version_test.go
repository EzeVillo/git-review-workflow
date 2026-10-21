package domain

import "testing"

func TestCommentsRequiresUpdatingAnOlderCLI(t *testing.T) {
	for _, version := range []string{"0.9.0", "0.9.99"} {
		if !IsOutdated(version, MinCLIVersion) {
			t.Errorf("CLI %s lacks comments and must require an update", version)
		}
	}
	if IsOutdated("0.10.0", MinCLIVersion) {
		t.Error("CLI 0.10.0 supplies the comments contract")
	}
}

func TestParseVersion(t *testing.T) {
	if v, ok := ParseVersion("0.8.0"); !ok || v != (Version{0, 8, 0}) {
		t.Errorf("ParseVersion(0.8.0) = %+v, %v", v, ok)
	}
	for _, bad := range []string{"", "1.2", "1.2.3.4", "1.2.x", "-1.2.3", "1.2.-3"} {
		if _, ok := ParseVersion(bad); ok {
			t.Errorf("ParseVersion(%q) should not parse", bad)
		}
	}
}

func TestIsOutdatedIsAStrictFloorWithNoCeiling(t *testing.T) {
	if !IsOutdated("0.7.9", "0.8.0") {
		t.Error("0.7.9 should be outdated against a 0.8.0 floor")
	}
	if IsOutdated("0.8.0", "0.8.0") {
		t.Error("exactly the floor is not outdated")
	}
	// No ceiling: a much newer CLI is never reported outdated.
	if IsOutdated("99.0.0", "0.8.0") {
		t.Error("a newer CLI must never be reported outdated")
	}
	if !IsOutdated("not-a-version", "0.8.0") {
		t.Error("an unparsable version is treated as outdated")
	}
}

func TestMinCLIVersionParses(t *testing.T) {
	if _, ok := ParseVersion(MinCLIVersion); !ok {
		t.Fatalf("MinCLIVersion %q must itself be a valid X.Y.Z", MinCLIVersion)
	}
}
