#!/usr/bin/env bats
#
# Tests for PR branches that have merged the base branch (develop) into
# themselves. A review must show the author's own changes, not the base content
# that the merge brought in.
#
# The PR: c1 adds feature.txt, then `git merge develop` brings in dev-only.txt,
# then c3 edits feature.txt.

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

	printf 'base\n' >base.txt
	git add base.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop

	git switch --quiet -c feature/x
	printf 'f1\n' >feature.txt
	git add feature.txt
	git commit --quiet -m c1
	git push --quiet -u origin feature/x

	# develop gains a file; the author merges it into feature/x, then keeps going.
	git switch --quiet develop
	printf 'DEV\n' >dev-only.txt
	git add dev-only.txt
	git commit --quiet -m "develop D2"
	git push --quiet origin develop
	git switch --quiet feature/x
	git merge --quiet --no-edit develop
	printf 'f2\n' >>feature.txt
	git add feature.txt
	git commit --quiet -m c3
	git push --quiet origin feature/x

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

# Add a second develop file, merge it into feature/x again, plus one commit.
second_merge() {
	git switch --quiet develop
	printf 'DEV2\n' >dev-only2.txt
	git add dev-only2.txt
	git commit --quiet -m "develop D3"
	git push --quiet origin develop
	git switch --quiet feature/x
	git merge --quiet --no-edit develop
	printf 'f4\n' >>feature.txt
	git add feature.txt
	git commit --quiet -m c5
	git push --quiet origin feature/x
	git switch --quiet develop
}

@test "whole review excludes base content merged into the PR" {
	run git review-pr feature/x
	[ "$status" -eq 0 ]
	run git diff --cached --name-only
	[[ "$output" == *"feature.txt"* ]]
	[[ "$output" != *"dev-only.txt"* ]]
}

@test "--step skips the base merge and never shows base content" {
	git review-pr feature/x --step
	# only the author's own two commits (c1, c3), not the merge commit
	[ "$(git config branch.review/feature/x.reviewcount)" = "2" ]
	out="$(git review-next 2>&1)"
	[[ "$out" != *"dev-only.txt"* ]]
	[[ "$out" == *"c3"* ]]
}

@test "--delta excludes base content merged since the last review" {
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x)"
	second_merge
	run git review-pr feature/x --delta
	[ "$status" -eq 0 ]
	run git diff --cached --name-only
	[[ "$output" == *"feature.txt"* ]]
	[[ "$output" != *"dev-only2.txt"* ]]
}

@test "--from excludes base content merged after the given commit" {
	from="$(git rev-parse origin/feature/x)"
	second_merge
	run git review-pr feature/x --from "$from"
	[ "$status" -eq 0 ]
	run git diff --cached --name-only
	[[ "$output" == *"feature.txt"* ]]
	[[ "$output" != *"dev-only2.txt"* ]]
}

@test "--delta --step walks only the author's new commit, not the base merge" {
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x)"
	second_merge
	git review-pr feature/x --delta --step
	[ "$(git config branch.review/feature/x.reviewcount)" = "1" ]
	out="$(git review-status 2>&1)"
	[[ "$out" == *"c5"* ]]
}

@test "--step finish-review with a merge in the PR extracts only reviewer edits" {
	git review-pr feature/x --step     # starts at c1 (step 1)
	git review-next                    # advances to c3 (step 2)
	printf 'f1\nf2\nFIX\n' >feature.txt
	run git finish-review
	[ "$status" -eq 0 ]
	run git diff --cached
	[[ "$output" == *"+FIX"* ]]
	# f2 is the author's own change in c3; must not appear in the reviewer diff
	[[ "$output" != *"+f2"* ]]
}

@test "finish-review on a merged branch extracts only the reviewer edits" {
	git review-pr feature/x
	printf 'f1\nf2\nFIX\n' >feature.txt
	run git finish-review
	[ "$status" -eq 0 ]
	run git diff --cached
	[[ "$output" == *"+FIX"* ]]
	[[ "$output" != *"DEV"* ]]
}

@test "finish-review --onto-source on a merged branch stages only reviewer edits" {
	git review-pr feature/x
	printf 'f1\nf2\nFIX\n' >feature.txt
	run git finish-review --onto-source
	[ "$status" -eq 0 ]
	# The fix is staged on the PR branch itself.
	[ "$(git rev-parse --abbrev-ref HEAD)" = "feature/x" ]
	run git diff --cached
	[[ "$output" == *"+FIX"* ]]
	# Anti-false-positive: the author's own change (f2, an added line in c3) and
	# the merged base content (DEV) must not be re-introduced by these edits.
	[[ "$output" != *"+f2"* ]]
	[[ "$output" != *"DEV"* ]]
}

@test "review degrades gracefully when merge-tree is unavailable" {
	# Simulate a git without `merge-tree --write-tree` (the plumbing the exclusion
	# relies on) by shadowing git with a shim that fails only on `merge-tree` and
	# delegates everything else to the real git.
	#
	# The shim must be hit by git-review-pr's *internal* git calls. When invoked
	# as `git review-pr`, the parent git prepends its own bindir to PATH for the
	# subprocess, so the real git wins and the shim is bypassed. Invoking the
	# script directly leaves our PATH intact — which is exactly the code path an
	# old real git would take, so the fallback branch is exercised faithfully.
	real="$(command -v git)"
	shim="$TMP/shim"
	mkdir -p "$shim"
	cat >"$shim/git" <<EOF
#!/usr/bin/env sh
[ "\$1" = "merge-tree" ] && exit 1
exec "$real" "\$@"
EOF
	chmod +x "$shim/git"

	# --from with a later base merge forces the merge-tree exclusion path: the
	# range start predates the merge, so the base content can only be excluded by
	# folding the merge-base into the lower bound (the merge-tree call).
	from="$(git rev-parse origin/feature/x)"
	second_merge

	out="$(PATH="$shim:$PATH" git-review-pr feature/x --from "$from" 2>&1)"
	[[ "$out" == *"could not exclude merged base content"* ]]

	# Anti-false-positive: with the exclusion disabled the lower bound stays at
	# the range start, so the merged base file (dev-only2.txt) leaks into the
	# diff. That proves the note reflects the real degraded behavior, not a no-op.
	run git diff --cached --name-only
	[[ "$output" == *"feature.txt"* ]]
	[[ "$output" == *"dev-only2.txt"* ]]
}
