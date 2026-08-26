#!/usr/bin/env bats
#
# Reading offers from git review config --porcelain (008-start-layout-offers).
#

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"

	git config --global user.email t@example.com
	git config --global user.name tester
	git config --global init.defaultBranch develop
	git config --global core.autocrlf false

	ORIGIN="$TMP/origin.git"
	WORK="$TMP/work"
	git init --quiet --bare "$ORIGIN"
	git init --quiet "$WORK"
	cd "$WORK"
	git remote add origin "$ORIGIN"
	git config reviewworkflow.base develop

	printf 'a1\n' >a.txt
	printf 'b1\n' >b.txt
	git add a.txt b.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop

	# feature/plain: changes, no walkthrough
	git switch --quiet -c feature/plain
	printf 'a1\na2\n' >a.txt
	git add a.txt
	git commit --quiet -m plain
	git push --quiet -u origin feature/plain

	# feature/walk: walkthrough, no keys
	git switch --quiet develop
	git switch --quiet -c feature/walk
	printf 'a1\na2\n' >a.txt
	printf 'b1\nb2\n' >b.txt
	git add a.txt b.txt
	git commit --quiet -m walk-files
	mkdir -p .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. a.txt
why a

## 2. b.txt
why b
EOF
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough
	git push --quiet -u origin feature/walk

	# feature/keys: walkthrough with keys
	git switch --quiet develop
	git switch --quiet -c feature/keys
	printf 'a1\na2\n' >a.txt
	printf 'b1\nb2\n' >b.txt
	mkdir -p src
	printf 'c\n' >src/c.txt
	git add a.txt b.txt src/c.txt
	git commit --quiet -m keys-files
	mkdir -p .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. src/c.txt
> key
key file

## 2. a.txt
> key
also key

## 3. b.txt
not key
EOF
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough-keys
	git push --quiet -u origin feature/keys

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

offer_lines() {
	printf '%s\n' "$output" | awk -F'\t' '$1=="offer" {print $2"\t"$3}'
}

@test "offers without walkthrough: draft, step and whole available only" {
	run git review config --porcelain -- feature/plain
	[ "$status" -eq 0 ]
	[ "$(offer_lines)" = "$(printf 'draft\tavailable\nstep\tavailable\nwhole\tavailable')" ]
}

@test "offers with walkthrough no keys: walk recommended, no keys" {
	run git review config --porcelain -- feature/walk
	[ "$status" -eq 0 ]
	[ "$(offer_lines)" = "$(printf 'walk\trecommended\nstep\tavailable\nwhole\tavailable')" ]
}

@test "offers with keys: walk recommended plus keys available" {
	run git review config --porcelain -- feature/keys
	[ "$status" -eq 0 ]
	[ "$(offer_lines)" = "$(printf 'walk\trecommended\nkeys\tavailable\nstep\tavailable\nwhole\tavailable')" ]
}

@test "offers --local uses local tip" {
	# Remote tip keeps walkthrough; force local feature/walk to plain (no walk).
	git branch -f feature/walk origin/feature/plain
	run git review config --porcelain --local -- feature/walk
	[ "$status" -eq 0 ]
	[ "$(offer_lines)" = "$(printf 'draft\tavailable\nstep\tavailable\nwhole\tavailable')" ]
	run git review config --porcelain -- feature/walk
	[ "$status" -eq 0 ]
	[ "$(offer_lines)" = "$(printf 'walk\trecommended\nstep\tavailable\nwhole\tavailable')" ]
}

@test "offers --delta without marker fails" {
	run git review config --porcelain --delta -- feature/plain
	[ "$status" -ne 0 ]
	# Contractual diagnostic (single phrase); no review branch as side effect.
	[[ "$output" == *"no previous review of feature/plain recorded for this origin"* ]]
	run git rev-parse --verify --quiet refs/heads/review/feature/plain
	[ "$status" -ne 0 ]
	# Zero offer rows even if something leaked to stdout before the die.
	n="$(printf '%s\n' "$output" | grep -c '^offer' || true)"
	[ "$n" -eq 0 ]
}

@test "offers --delta with marker and no intersecting walk degrades to step+whole" {
	# First full review tip at keys tip; then add a commit with only non-key path
	# is hard. Simpler: record marker at current tip then add commits that are
	# only outside walkthrough paths... Use marker at tip of keys, push new
	# commit that only touches uncovered file so guided keys still apply.
	# Instead: marker after first commit of walk branch before walkthrough
	# landed — delta range may exclude walkthrough entries.
	git switch --quiet feature/keys
	# Parent of walkthrough commit has files but walkthrough is only on tip.
	# Marker at commit before walkthrough: range tip.. has walkthrough only as
	# new file - walk_sequence should still see entries for a,b,c in range.
	# Better stale case: walkthrough lists paths not in delta range.
	git switch --quiet develop
	git switch --quiet -c feature/stale
	printf 'x\n' >only.txt
	git add only.txt
	git commit --quiet -m only
	mkdir -p .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. missing.txt
> key
gone
EOF
	git add .review/walkthrough.md
	git commit --quiet -m wt-stale
	git push --quiet -u origin feature/stale
	# Delta from first commit: only walkthrough.md added; missing.txt not in range
	first="$(git rev-parse feature/stale^)"
	git config "reviewworkflow.feature/stale.reviewed" "$first"
	run git review config --porcelain --delta -- feature/stale
	[ "$status" -eq 0 ]
	# walk_sequence empty for missing path -> no walk/keys
	[ "$(offer_lines)" = "$(printf 'draft\tavailable\nstep\tavailable\nwhole\tavailable')" ]
}

@test "offers --local and --offline are mutually exclusive" {
	run git review config --porcelain --local --offline -- feature/plain
	[ "$status" -ne 0 ]
	[[ "$output" == *"--local and --offline are mutually exclusive"* ]]
	run git rev-parse --verify --quiet refs/heads/review/feature/plain
	[ "$status" -ne 0 ]
}

@test "offers without fetch: remote URL is unreachable but tracking ref exists" {
	# Point origin at a path that cannot be fetched, keep tracking ref.
	git remote set-url origin "$TMP/does-not-exist.git"
	run git review config --porcelain -- feature/keys
	[ "$status" -eq 0 ]
	[ "$(offer_lines)" = "$(printf 'walk\trecommended\nkeys\tavailable\nstep\tavailable\nwhole\tavailable')" ]
}

@test "offers --local missing branch fails hard" {
	run git review config --porcelain --local -- no-such-branch
	[ "$status" -ne 0 ]
	[[ "$output" == *"no-such-branch not found"* ]]
	run git rev-parse --verify --quiet refs/heads/review/no-such-branch
	[ "$status" -ne 0 ]
}

@test "offers default remote hard-fails when tracking ref is absent (local-only branch)" {
	git switch --quiet -c feature/local-only
	printf 'loc\n' >loc.txt
	git add loc.txt
	git commit --quiet -m local-only
	git switch --quiet develop

	run git review config --porcelain -- feature/local-only
	[ "$status" -ne 0 ]
	[[ "$output" == *"origin/feature/local-only not found"* ]]
	n="$(printf '%s\n' "$output" | grep -c '^offer' || true)"
	[ "$n" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review/feature/local-only
	[ "$status" -ne 0 ]
}

@test "config --porcelain does not create review lower bound commits when fold would apply" {
	# Fold only fires when the range start is not an ancestor of the tip's
	# merge-base with base (typical --delta after base was merged into the PR).
	# Offers must use the tree-only path (no commit-tree 'review lower bound').
	# rev-list --all misses dangling commits, so scan every commit object.
	git switch --quiet -c feature/merged
	printf 'f1\n' >feature.txt
	git add feature.txt
	git commit --quiet -m c1
	git push --quiet -u origin feature/merged

	git switch --quiet develop
	printf 'DEV\n' >dev-only.txt
	git add dev-only.txt
	git commit --quiet -m "develop D2"
	git push --quiet origin develop
	git switch --quiet feature/merged
	git merge --quiet --no-edit develop
	printf 'f2\n' >>feature.txt
	git add feature.txt
	git commit --quiet -m c3
	git push --quiet origin feature/merged

	# Marker at current tip; then merge more base content so delta start is
	# older than the new merge-base (forces fold_lower / resolve_lower_bound).
	marker="$(git rev-parse feature/merged)"
	git config "reviewworkflow.feature/merged.reviewed" "$marker"

	git switch --quiet develop
	printf 'DEV2\n' >dev-only2.txt
	git add dev-only2.txt
	git commit --quiet -m "develop D3"
	git push --quiet origin develop
	git switch --quiet feature/merged
	git merge --quiet --no-edit develop
	printf 'f4\n' >>feature.txt
	git add feature.txt
	git commit --quiet -m c5
	git push --quiet origin feature/merged
	git switch --quiet develop

	list_commits() {
		git cat-file --batch-check='%(objecttype) %(objectname)' --batch-all-objects |
			awk '$1 == "commit" { print $2 }' | LC_ALL=C sort
	}
	count_lower_bound_msgs() {
		list_commits | while IFS= read -r c; do
			[ -n "$c" ] || continue
			if [ "$(git log -1 --format=%s "$c" 2>/dev/null || true)" = "review lower bound" ]; then
				printf '%s\n' "$c"
			fi
		done | grep -c . || true
	}

	before_list="$(list_commits)"
	before_lb="$(count_lower_bound_msgs)"
	[ "$before_lb" -eq 0 ]

	run git review config --porcelain --delta -- feature/merged
	[ "$status" -eq 0 ]
	[ "$(offer_lines)" = "$(printf 'draft\tavailable\nstep\tavailable\nwhole\tavailable')" ]
	run git review config --porcelain --delta -- feature/merged
	[ "$status" -eq 0 ]
	run git review config --porcelain --delta -- feature/merged
	[ "$status" -eq 0 ]

	after_list="$(list_commits)"
	after_lb="$(count_lower_bound_msgs)"
	# No new commits at all (trees from merge-tree --write-tree are fine).
	[ "$after_list" = "$before_list" ]
	[ "$after_lb" -eq 0 ]

	# start --delta still materializes a real lower-bound commit when folding.
	run git review start feature/merged --delta
	[ "$status" -eq 0 ]
	after_start_lb="$(count_lower_bound_msgs)"
	[ "$after_start_lb" -gt 0 ]
}

# ── the draft's own two offers ───────────────────────────────────────────────
#
# Which of them is emitted answers "does this reading order still cover the
# range?", which is a question only this side can answer: it needs the tip the
# draft was written against AND the tip today. The draft records cannot stand in
# for it -- their <state> answers "has this order been read?", deliberately, so a
# branch that moved after its review still reports `reviewed`.
#
# Left to the client the two cases arrived identical, and the start assistant
# asked with a modal which one it was. Answering "reconcile" on a range that had
# not moved was a no-op that left the reviewer on a spent row with neither Copy
# for agent nor Validate and start: a wizard step whose only outcome was a dead
# end.

# Fill in every placeholder of the draft for <branch>: numbers the "## ?." entries
# and replaces the heads-up and why comments with prose, which is what build
# demands and what makes the pair read N/N.
fill_draft() {
	_fd_path="$(git rev-parse --git-dir)/review-walkthrough/$1.md"
	awk '
		/^<!-- heads-up/ { print "Read the payment state first."; if (index($0, "-->") == 0) hu = 1; next }
		hu { if (index($0, "-->")) hu = 0; next }
		/^## [?][.] / { n++; sub(/^## [?][.] /, "## " n ". "); print; next }
		/^<!-- why/ { print "REVIEWER: this is the why."; if (index($0, "-->") == 0) w = 1; next }
		w { if (index($0, "-->")) w = 0; next }
		{ print }
	' "$_fd_path" >"$_fd_path.filled"
	mv "$_fd_path.filled" "$_fd_path"
}

@test "a half-written draft is offered as draft-resume, never as an update" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]

	run git review config --porcelain -- feature/plain
	[ "$status" -eq 0 ]
	# The skeleton covers today's range, so there is nothing to reconcile: what
	# is left is finishing it.
	[ "$(offer_lines)" = "$(printf 'draft-resume\tavailable\nstep\tavailable\nwhole\tavailable')" ]
}

@test "a complete draft on an unmoved range offers neither: walk already reads it" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	fill_draft feature/plain
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 0 ]

	run git review config --porcelain -- feature/plain
	[ "$status" -eq 0 ]
	# This is the case the modal used to mishandle: the order is written and it
	# covers the range, so reconciling it would change nothing and finishing it
	# is already done. walk carries it.
	[ "$(offer_lines)" = "$(printf 'walk\trecommended\nstep\tavailable\nwhole\tavailable')" ]
}

@test "a draft whose branch moved is offered as draft-update, alongside walk" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	fill_draft feature/plain
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 0 ]

	git switch --quiet feature/plain
	printf 'new\n' >c.txt
	git add c.txt
	git commit --quiet -m "one more file"
	git push --quiet origin feature/plain
	git switch --quiet develop

	run git review config --porcelain -- feature/plain
	[ "$status" -eq 0 ]
	[ "$(offer_lines)" = "$(printf 'walk\trecommended\ndraft-update\tavailable\nstep\tavailable\nwhole\tavailable')" ]

	# And it is not decoration: the update really does reconcile, keeping the why
	# that was already written and adding the file that came in.
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"1 kept, 1 added, 0 dropped"* ]]

	# Which puts the offer back to draft-resume: the order now covers the range
	# and has an entry still to write.
	run git review config --porcelain -- feature/plain
	[ "$status" -eq 0 ]
	[ "$(offer_lines)" = "$(printf 'walk\trecommended\ndraft-resume\tavailable\nstep\tavailable\nwhole\tavailable')" ]
}

@test "a draft with no instruction block never claims to be out of range" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	fill_draft feature/plain
	# Deleting the block by hand is legal, and it takes the recorded tip with it.
	# Without a tip the range question has no answer, so the safe reading is "not
	# drifted": offering an update whose outcome cannot be predicted is worse
	# than offering to finish what is there.
	_p="$(git rev-parse --git-dir)/review-walkthrough/feature/plain.md"
	awk '/^<!-- git-review-range:/ { skip = 1 } skip { if (index($0, "-->")) skip = 0; next } { print }' "$_p" >"$_p.x"
	mv "$_p.x" "$_p"

	run git review config --porcelain -- feature/plain
	[ "$status" -eq 0 ]
	[[ "$(offer_lines)" != *"draft-update"* ]]
}
