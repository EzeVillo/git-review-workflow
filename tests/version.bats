#!/usr/bin/env bats
#
# Every command reports the same version, and it matches the VERSION file.

setup() {
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"
	VERSION="$(cat "$BATS_TEST_DIRNAME/../VERSION")"
	export VERSION
}

@test "VERSION file holds a semver-looking string" {
	[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "every command's --version matches the VERSION file" {
	for c in review-pr review-next review-prev review-status review-abort finish-review clean-review; do
		run git "$c" --version
		[ "$status" -eq 0 ]
		[ "$output" = "git $c $VERSION" ]
		# the short flag prints the same thing
		run git "$c" -V
		[ "$status" -eq 0 ]
		[ "$output" = "git $c $VERSION" ]
	done
}
