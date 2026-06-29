#!/usr/bin/env bats
#
# A release bumps the version in several places at once. The files that ship
# *inside* the tarball (VERSION, bin/git-review, package.json) must be bumped in
# the tagged commit; the file that points *at* the tarball (the Homebrew formula)
# is pinned afterwards by the release workflow. If any of them drift out of sync,
# the tag would ship — or advertise, or publish to npm — the wrong version.
#
# These tests assert that single invariant directly, so a partial bump fails
# loudly and names exactly which file lagged behind.

setup() {
	REPO="$BATS_TEST_DIRNAME/.."
	VERSION="$(cat "$REPO/VERSION")"
}

@test "version: VERSION file is a bare semver with no trailing junk" {
	[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "version: bin/git-review embeds the same version as the VERSION file" {
	embedded="$(sed -nE 's#^VERSION="([^"]*)".*#\1#p' "$REPO/bin/git-review")"
	[ "$embedded" = "$VERSION" ]
}

@test "version: Homebrew formula matches the VERSION file" {
	pinned="$(sed -nE 's#^  version "([^"]*)".*#\1#p' "$REPO/Formula/git-review-workflow.rb")"
	[ "$pinned" = "$VERSION" ]
}

@test "version: package.json matches the VERSION file" {
	# The npm package publishes whatever version package.json carries, so it must
	# agree with the VERSION file shipped alongside it in the tagged commit.
	pinned="$(sed -nE 's#^  "version": "([^"]*)".*#\1#p' "$REPO/package.json")"
	[ "$pinned" = "$VERSION" ]
}

@test "version: README does not hardcode a version number" {
	# The README points at the VERSION file instead of repeating the number,
	# so it can never go stale. Guard against the old hardcoded form coming back.
	! grep -qE '\*\*Version:\*\* +`[0-9]' "$REPO/README.md"
}
