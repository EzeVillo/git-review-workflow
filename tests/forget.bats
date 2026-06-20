#!/usr/bin/env bats
#
# Tests for git-review-forget — manage the --delta markers
# (reviewworkflow.<src>.reviewed) independently of any review branch.
#
# Three granularities: one branch, --all, and --stale (prune markers whose
# origin branch is gone). --dry-run previews --stale and only --stale.

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"

	git config --global user.email t@example.com
	git config --global user.name tester
	git config --global init.defaultBranch develop

	ORIGIN="$TMP/origin.git"
	WORK="$TMP/work"
	git init --quiet --bare "$ORIGIN"
	git init --quiet "$WORK"
	cd "$WORK"
	git remote add origin "$ORIGIN"
	git config reviewworkflow.base develop

	printf 'base\n' >f.txt
	git add f.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop

	# Two PR branches that still live on origin.
	for b in feature/x feature/y; do
		git switch --quiet -c "$b" develop
		printf '%s\n' "$b" >f.txt
		git add f.txt
		git commit --quiet -m "$b"
		git push --quiet -u origin "$b"
		git switch --quiet develop
	done
}

teardown() {
	rm -rf "$TMP"
}

# Set a delta marker for a branch to its current origin tip.
mark() {
	git config "reviewworkflow.$1.reviewed" "$(git rev-parse "origin/$1")"
}

# ── per-branch ────────────────────────────────────────────────────────────────

@test "review-forget <branch> forgets only that marker" {
	mark feature/x
	mark feature/y

	run git review-forget feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"feature/x"* ]]

	# the targeted marker is gone
	run git config reviewworkflow.feature/x.reviewed
	[ "$status" -ne 0 ]
	# the other one is untouched
	[ "$(git config reviewworkflow.feature/y.reviewed)" = "$(git rev-parse origin/feature/y)" ]
}

@test "review-forget <branch> handles a branch name containing a dot" {
	# A dotted name (e.g. release-1.2) is the fragile case: the marker key is
	# reviewworkflow.release-1.2.reviewed, and git config must round-trip the
	# subsection without splitting on the dot.
	git config "reviewworkflow.release-1.2.reviewed" deadbeef

	run git review-forget release-1.2
	[ "$status" -eq 0 ]
	[[ "$output" == *"release-1.2"* ]]

	run git config "reviewworkflow.release-1.2.reviewed"
	[ "$status" -ne 0 ]
}

@test "review-forget --all forgets a dotted-name marker too" {
	# --all reconstructs the source from the key; the dot must survive that.
	git config "reviewworkflow.release-1.2.reviewed" deadbeef

	run git review-forget --all
	[ "$status" -eq 0 ]
	[[ "$output" == *"release-1.2"* ]]
	run git config "reviewworkflow.release-1.2.reviewed"
	[ "$status" -ne 0 ]
}

@test "review-forget <branch> with no marker is a no-op note and exits 0" {
	# precondition: there is nothing to forget
	run git config reviewworkflow.feature/x.reviewed
	[ "$status" -ne 0 ]

	run git review-forget feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"no delta marker"* ]]
}

# ── --all ───────────────────────────────────────────────────────────────────

@test "review-forget --all forgets every marker" {
	mark feature/x
	mark feature/y

	run git review-forget --all
	[ "$status" -eq 0 ]

	run git config reviewworkflow.feature/x.reviewed
	[ "$status" -ne 0 ]
	run git config reviewworkflow.feature/y.reviewed
	[ "$status" -ne 0 ]
}

@test "review-forget --all leaves reviewworkflow.base untouched" {
	mark feature/x

	run git review-forget --all
	[ "$status" -eq 0 ]
	[ "$(git config reviewworkflow.base)" = "develop" ]
}

@test "review-forget --all with no markers reports nothing to forget" {
	# only reviewworkflow.base is set — it must not be counted as a marker
	run git review-forget --all
	[ "$status" -eq 0 ]
	[[ "$output" == *"no delta markers"* ]]
}

# ── --stale ───────────────────────────────────────────────────────────────────

@test "review-forget --stale forgets markers whose origin branch is gone, keeps live ones" {
	mark feature/x
	mark feature/y
	# feature/y is merged & deleted upstream; its remote-tracking ref still
	# lingers locally until the prune inside review-forget removes it.
	git push --quiet origin --delete feature/y

	run git review-forget --stale
	[ "$status" -eq 0 ]
	[[ "$output" == *"feature/y"* ]]

	# the orphaned marker is gone
	run git config reviewworkflow.feature/y.reviewed
	[ "$status" -ne 0 ]
	# the marker for the still-live branch survives
	[ "$(git config reviewworkflow.feature/x.reviewed)" = "$(git rev-parse origin/feature/x)" ]
}

@test "review-forget --stale --dry-run lists stale markers but removes nothing" {
	mark feature/x
	mark feature/y
	git push --quiet origin --delete feature/y

	run git review-forget --stale --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"would"* ]]
	[[ "$output" == *"feature/y"* ]]

	# dry-run must not touch anything
	[ -n "$(git config reviewworkflow.feature/y.reviewed)" ]
	[ -n "$(git config reviewworkflow.feature/x.reviewed)" ]
}

@test "review-forget --stale with no orphans removes nothing" {
	mark feature/x
	mark feature/y

	run git review-forget --stale
	[ "$status" -eq 0 ]
	[ -n "$(git config reviewworkflow.feature/x.reviewed)" ]
	[ -n "$(git config reviewworkflow.feature/y.reviewed)" ]
}

@test "review-forget --stale aborts on a failed fetch and removes nothing" {
	mark feature/x
	git remote remove origin

	run git review-forget --stale
	[ "$status" -ne 0 ]
	[[ "$output" == *"could not fetch"* ]]
	# a failed stale run must never drop markers on inference
	[ -n "$(git config reviewworkflow.feature/x.reviewed)" ]
}

# ── --dry-run only applies to --stale ──────────────────────────────────────────

@test "review-forget <branch> --dry-run is rejected" {
	mark feature/x
	run git review-forget feature/x --dry-run
	[ "$status" -ne 0 ]
	[[ "$output" == *"--dry-run only applies to --stale"* ]]
	# rejected before doing anything
	[ -n "$(git config reviewworkflow.feature/x.reviewed)" ]
}

@test "review-forget --all --dry-run is rejected" {
	mark feature/x
	run git review-forget --all --dry-run
	[ "$status" -ne 0 ]
	[[ "$output" == *"--dry-run only applies to --stale"* ]]
	[ -n "$(git config reviewworkflow.feature/x.reviewed)" ]
}

# ── argument validation ────────────────────────────────────────────────────────

@test "review-forget with no target prints usage and exits 1" {
	run git review-forget
	[ "$status" -eq 1 ]
	[[ "$output" == *"usage: git review-forget"* ]]
}

@test "review-forget rejects combining a branch with --all" {
	run git review-forget feature/x --all
	[ "$status" -ne 0 ]
	[[ "$output" == *"only one of"* ]]
}

@test "review-forget rejects combining --all with --stale" {
	run git review-forget --all --stale
	[ "$status" -ne 0 ]
	[[ "$output" == *"only one of"* ]]
}

@test "review-forget rejects an unknown option" {
	run git review-forget --bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unknown option --bogus"* ]]
}

@test "review-forget --help prints usage and exits 0" {
	run git-review-forget --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review-forget"* ]]
}
