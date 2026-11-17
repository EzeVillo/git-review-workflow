#!/usr/bin/env bats
#
# State-dependent error and side-effect tests that the per-command files did not
# already cover: wrong-branch guards, missing metadata, branch-already-exists,
# the "previously reviewed" note and the force-push / no-new-commits delta
# guards.

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"

	git config --global user.email t@example.com
	git config --global user.name tester
	git config --global core.autocrlf false
	git config --global init.defaultBranch develop

	ORIGIN="$TMP/origin.git"
	WORK="$TMP/work"
	git init --quiet --bare "$ORIGIN"
	git init --quiet "$WORK"
	cd "$WORK"
	git remote add origin "$ORIGIN"
	git config reviewworkflow.base develop

	printf 'a\nb\nc\n' >app.txt
	git add app.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop

	git switch --quiet -c feature/x
	printf 'a\nB\nc\nd\n' >app.txt
	git add app.txt
	git commit --quiet -m pr1
	git push --quiet -u origin feature/x

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

# Push a second PR commit that appends a line; leaves you on develop.
push_pr2() {
	git switch --quiet feature/x
	printf 'a\nB\nc\nd\ne\n' >app.txt
	git add app.txt
	git commit --quiet -m pr2
	git push --quiet origin feature/x
	git switch --quiet develop
}

# Rewrite origin/feature/x onto develop so its previous commits become orphaned —
# a force-push that drops the old history. The original commits still exist as
# objects locally (callers capture their SHAs first). Leaves you on develop.
force_push_feature() {
	git switch --quiet feature/x
	git reset --hard --quiet develop
	printf 'alt\n' >alt.txt
	git add alt.txt
	git commit --quiet -m rewritten
	git push --quiet --force origin feature/x
	git switch --quiet develop
}

# A feature branch with two independent commits: c1 adds a.txt, c2 adds b.txt.
# Two commits give a step review a banked edit on step 1 and a live edit on
# step 2, and leave step 1 short of the tip so a whole-mode fallback would leak
# c2 into the reviewer's diff. Leaves you on develop.
make_two_commit_feature() {
	git switch --quiet -c feature/two develop
	printf 'a2\n' >a.txt
	git add a.txt
	git commit --quiet -m c1-touch-a
	printf 'b2\n' >b.txt
	git add b.txt
	git commit --quiet -m c2-touch-b
	git push --quiet -u origin feature/two
	git switch --quiet develop
}

# Start a step review of that two-commit feature, bank an edit (FIXA) on step 1
# and leave a live edit (FIXB) on step 2 — the working state review finish's step
# replay must not silently discard when its metadata is corrupt. Leaves you on the
# review branch, on step 2.
step_review_two_with_edits() {
	make_two_commit_feature
	git review start feature/two --step
	printf 'a2\nFIXA\n' >a.txt
	git review next                # bank step 1 (FIXA), now on step 2
	printf 'b2\nFIXB\n' >b.txt     # current step edit, not yet banked
}

# ── wrong-branch guards (run on develop, not a review/* branch) ───────────────

@test "review next off a review branch errors" {
	run git review next
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}

@test "review prev off a review branch errors" {
	run git review prev
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}

@test "review status off a review branch errors" {
	run git review status
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}

@test "review abort off a review branch errors" {
	run git review abort
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}

@test "review finish off a review branch errors" {
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}

# ── exact exit codes (FR-017/FR-023, Decision 5) ───────────────────────────────
#
# The wrong-branch guards above only assert status -ne 0; these fix the exact
# codes the contract promises across the whole CLI, not just status
# --porcelain: 2 for "no review active", 1 for "something is broken" (missing
# metadata, not a git repository). The walk-drift exit 3 case is covered in
# tests/walk.bats, next to the fixture that already sets up a walkthrough.

@test "status off a review branch exits exactly 2" {
	run git review status
	[ "$status" -eq 2 ]
}

@test "abort off a review branch exits exactly 2" {
	run git review abort
	[ "$status" -eq 2 ]
}

@test "finish off a review branch exits exactly 2" {
	run git review finish
	[ "$status" -eq 2 ]
}

@test "preview off a review branch exits exactly 2" {
	run git review preview
	[ "$status" -eq 2 ]
}

@test "save off a review branch exits exactly 2" {
	run git review save
	[ "$status" -eq 2 ]
}

@test "status on a hand-made review branch without metadata exits exactly 1" {
	git switch --quiet -c review/orphan
	run git review status
	[ "$status" -eq 1 ]
}

@test "status outside a git repository exits exactly 1" {
	norepo="$(mktemp -d)"
	cd "$norepo"
	run git review status
	[ "$status" -eq 1 ]
	[[ "$output" == *"not a git repository"* ]]
	cd "$WORK"
	rm -rf "$norepo"
}

@test "review prev requires step mode on a whole review" {
	git review start feature/x
	run git review prev
	[ "$status" -ne 0 ]
	[[ "$output" == *"not started with git review start --step"* ]]
}

@test "review next requires step mode on a whole review, even after listing its files" {
	# A whole review now lists the files it touches (FR-001), but that listing is
	# an inventory, not a cursor: next must keep rejecting it exactly as before
	# (FR-008), and the listing must not have created any config next could latch
	# onto.
	git review start feature/x
	git review status --porcelain >/dev/null
	run git review next
	[ "$status" -ne 0 ]
	[[ "$output" == *"not started with git review start --step"* ]]
}

# ── missing review metadata on a hand-made review/* branch ────────────────────

@test "review status reports missing metadata" {
	git switch --quiet -c review/orphan
	run git review status
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
	# No reviewsource: abort cannot run — tell how to leave and drop the branch.
	[[ "$output" == *"git branch -D review/orphan"* ]]
}

@test "review abort reports missing metadata" {
	git switch --quiet -c review/orphan
	run git review abort
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
	[[ "$output" == *"git branch -D review/orphan"* ]]
}

@test "review finish reports missing metadata" {
	git switch --quiet -c review/orphan
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
	[[ "$output" == *"git branch -D review/orphan"* ]]
}

# ── review start guards ──────────────────────────────────────────────────────────

@test "review start refuses when the review branch already exists" {
	git review start feature/x
	git switch --quiet develop
	git reset --hard --quiet
	run git review start feature/x
	[ "$status" -ne 0 ]
	[[ "$output" == *"already exists"* ]]
}

@test "review start rejects an unknown explicit base" {
	# The base is a commit-ish (branch, tag or commit), so a failed lookup is no
	# longer labelled origin/<base> — it was tried as a tag and a commit too. The
	# label is the base as given.
	run git review start feature/x nosuchbase
	[ "$status" -ne 0 ]
	[[ "$output" == *"nosuchbase not found"* ]]
	[[ "$output" != *"origin/nosuchbase"* ]]
}

@test "review start --from= equals form stages the same range as --from" {
	push_pr2
	c1="$(git rev-parse origin/feature/x~1)"
	run git review start feature/x --from="$c1"
	[ "$status" -eq 0 ]
	run git diff --cached
	[[ "$output" == *"+e"* ]]
}

@test "review start notes new commits since the last full review" {
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x~1)"
	run git review start feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"previously reviewed"* ]]
	[[ "$output" == *"--delta"* ]]
}

@test "review start --delta with no new commits fails" {
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x)"
	run git review start feature/x --delta
	[ "$status" -ne 0 ]
	[[ "$output" == *"no new commits"* ]]
}

@test "review start --delta after a force-push fails" {
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x)"
	# Rewrite feature/x so the recorded tip is no longer an ancestor.
	git switch --quiet feature/x
	git reset --hard --quiet develop
	printf 'alt\n' >alt.txt
	git add alt.txt
	git commit --quiet -m rewritten
	git push --quiet --force origin feature/x
	git switch --quiet develop
	run git review start feature/x --delta
	[ "$status" -ne 0 ]
	[[ "$output" == *"force-pushed"* ]]
}

@test "review start --delta --step after a force-push fails" {
	# The force-push guard lives in the --delta range resolution, before the
	# --step layout runs; --step must not let a rewritten history slip through.
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x)"
	force_push_feature

	run git review start feature/x --delta --step
	# Fails for the force-push reason specifically, not some other guard.
	[ "$status" -ne 0 ]
	[[ "$output" == *"force-pushed"* ]]

	# The guard must fire before --step creates the review branch or advances the
	# recorded tip — otherwise we'd be reviewing rewritten commits as "new".
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "review start --from after a force-push rejects the now-orphaned commit" {
	# A --from commit that is a genuine ancestor of origin/feature/x today.
	push_pr2
	from="$(git rev-parse origin/feature/x~1)"
	git merge-base --is-ancestor "$from" origin/feature/x

	# Rewrite the branch so that commit is no longer in its history.
	force_push_feature

	# The commit object still exists locally, so --from resolves it and the
	# failure is the ancestry check — not "unknown commit".
	run git rev-parse --verify --quiet "$from^{commit}"
	[ "$status" -eq 0 ]

	run git review start feature/x --from "$from"
	[ "$status" -ne 0 ]
	[[ "$output" == *"not an ancestor"* ]]
	[[ "$output" != *"unknown commit"* ]]

	# The guard fires before any review branch is created.
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "review start --delta after a genuine rebase fails" {
	# The existing force-push guard test rewrites with reset --hard; this exercises
	# the same guard via a real `git rebase`, the way a PR is rebased in practice.
	git config reviewworkflow.feature/x.reviewed "$(git rev-parse origin/feature/x)"
	old="$(git rev-parse origin/feature/x)"

	# Advance develop, then replay feature/x onto it so the PR commit gets a new
	# SHA and the recorded tip is no longer an ancestor of the rebased branch.
	git switch --quiet develop
	printf 'newdev\n' >newdev.txt
	git add newdev.txt
	git commit --quiet -m "develop advance"
	git push --quiet origin develop
	git switch --quiet feature/x
	git rebase --quiet develop
	git push --quiet --force origin feature/x
	git switch --quiet develop

	# Sanity: it really was rebased — the old tip is no longer an ancestor.
	run git merge-base --is-ancestor "$old" origin/feature/x
	[ "$status" -ne 0 ]

	run git review start feature/x --delta
	[ "$status" -ne 0 ]
	[[ "$output" == *"force-pushed"* ]]

	# The guard fires before any review branch is created or the tip advances.
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

# ── review finish side effects and guards ─────────────────────────────────────

@test "review finish refuses when review-fixes already exists" {
	git branch review-fixes/feature/x develop
	git review start feature/x
	printf 'a\nB\nc\nd\nfix\n' >app.txt
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"already exists"* ]]
	# Refused before record_undo: no stuck undo, pre-existing branch survives.
	[ -z "$(git config branch.review/feature/x.reviewundohead || true)" ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -eq 0 ]
}

@test "review start refuses untracked files as local changes" {
	printf 'orphan\n' >orphan.txt
	run git review start feature/x
	[ "$status" -ne 0 ]
	[[ "$output" == *"local changes"* ]]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
}

@test "review finish --onto-source refuses a local branch behind the tip" {
	# Advance origin, then leave the local feature/x behind the reviewed tip.
	push_pr2
	git branch -f feature/x origin/feature/x~1
	git review start feature/x
	printf 'a\nB\nc\nd\ne\nfix\n' >app.txt
	run git review finish --onto-source
	[ "$status" -ne 0 ]
	[[ "$output" == *"not at the reviewed tip"* ]]
	[ -z "$(git for-each-ref refs/review-undo/feature/x/)" ]
	[ "$(git branch --show-current)" = review/feature/x ]
}

@test "finish offers an explicit fast-forward and undo restores the old local PR tip" {
	push_pr2
	git branch -f feature/x origin/feature/x~1
	before=$(git rev-parse refs/heads/feature/x)
	git review start feature/x
	tip=$(git config branch.review/feature/x.reviewtip)
	printf 'a\nB\nc\nd\ne\nfix\n' >app.txt
	run git review finish --destinations --porcelain
	[ "$status" -eq 0 ]
	[ "$output" = "$(printf 'finish-destination\tseparate\nfinish-destination\tupdate-source')" ]
	run git review finish --update-source
	[ "$status" -eq 0 ]
	[ "$(git branch --show-current)" = feature/x ]
	[ "$(git rev-parse HEAD)" = "$tip" ]
	[ "$(git diff --cached --name-only)" = app.txt ]
	run git review finish --abort
	[ "$status" -eq 0 ]
	[ "$(git branch --show-current)" = review/feature/x ]
	[ "$(git rev-parse refs/heads/feature/x)" = "$before" ]
	[ "$(tail -n 1 app.txt)" = fix ]
}

@test "finish offers only a separate branch when the local PR branch has other commits" {
	git review start feature/x
	tip=$(git config branch.review/feature/x.reviewtip)
	ahead=$(git commit-tree "$tip^{tree}" -p "$tip" -m 'local work')
	git update-ref refs/heads/feature/x "$ahead"
	run git review finish --destinations --porcelain
	[ "$status" -eq 0 ]
	[ "$output" = "$(printf 'finish-destination\tseparate')" ]
	run git review finish --update-source
	[ "$status" -eq 1 ]
	[[ "$output" == *"not at the reviewed tip"* ]]
	[ -z "$(git for-each-ref refs/review-undo/feature/x/)" ]
	[ "$(git rev-parse refs/heads/feature/x)" = "$ahead" ]
}

@test "prepared start resolves mapped remote source and base branches" {
	bats_require_minimum_version 1.5.0
	make_two_commit_feature
	tip=$(git rev-parse feature/two)
	base=$(git rev-parse feature/two^)
	git push -q origin "$base:refs/heads/integration"
	git config --replace-all remote.origin.fetch '+refs/heads/feature/*:refs/remotes/origin/reviewable/*'
	git config --add remote.origin.fetch '+refs/heads/integration:refs/remotes/origin/develop'
	git config reviewworkflow.base origin/develop
	git fetch -q origin
	tracking=$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes)
	git push -q origin develop:refs/heads/reviewable/two

	run git review start --prepare -- reviewable/two
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
	[ -n "$token" ]
	run git review start "--prepared=$token" --no-walk -- reviewable/two
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/reviewable/two.reviewtip)" = "$tip" ]
	[ "$(git config branch.review/reviewable/two.reviewbasecommit)" = "$base" ]
	[ "$(git diff --cached --name-only)" = b.txt ]
	[ "$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes)" = "$tracking" ]
}

@test "start fetches a newly published base tag without updating public refs" {
	make_two_commit_feature
	base=$(git rev-parse feature/two^)
	git -c protocol.file.allow=always clone -q --branch develop "$ORIGIN" "$TMP/reader"
	git tag -a v-next -m 'next release' "$base"
	git tag unrelated develop
	git push -q origin refs/tags/v-next refs/tags/unrelated
	cd "$TMP/reader"
	tracking=$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes)

	for selector in v-next refs/tags/v-next 'refs/tags/v-next^{}' 'tags/v-next^{}'; do
		git config reviewworkflow.base "$selector"
		run git review start --no-walk feature/two
		[ "$status" -eq 0 ]
		[ "$(git config branch.review/feature/two.reviewbasecommit)" = "$base" ]
		[ "$(git diff --cached --name-only)" = b.txt ]
		[ -z "$(git tag --list)" ]
		[ "$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes)" = "$tracking" ]
		run git review abort
		[ "$status" -eq 0 ]
		[ -z "$(git for-each-ref --format='%(refname)' refs/worktree/review-start/)" ]
	done
}

@test "start resolves a base object introduced by the same fetch" {
	make_two_commit_feature
	git clone -q --branch develop "$ORIGIN" "$TMP/reader"
	git switch -q feature/two
	printf 'third\n' >c.txt
	git add c.txt
	git commit -qm third
	base=$(git rev-parse HEAD)
	selector=$(git rev-parse --short "$base")
	printf 'fourth\n' >d.txt
	git add d.txt
	git commit -qm fourth
	git push -q origin feature/two
	cd "$TMP/reader"
	! git cat-file -e "$base^{commit}" 2>/dev/null
	tracking=$(git rev-parse refs/remotes/origin/feature/two)
	run git review start --prepare --base "$selector" -- feature/two
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
	[ -n "$token" ]
	run git review start "--prepared=$token" --base "$selector" --no-walk -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/two.reviewbasecommit)" = "$base" ]
	[ "$(git diff --cached --name-only)" = d.txt ]
	[ "$(git rev-parse refs/remotes/origin/feature/two)" = "$tracking" ]
}

@test "start follows a fresh remote HEAD for both range selectors" {
	make_two_commit_feature
	base=$(git rev-parse feature/two^)
	tracking=$(git rev-parse refs/remotes/origin/develop)
	git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
	git --git-dir="$ORIGIN" update-ref refs/heads/develop "$base"
	git config --unset reviewworkflow.base

	for kind in --base --from; do
		run git review start "$kind" origin --no-walk -- feature/two
		[ "$status" -eq 0 ]
		[ "$(git rev-parse HEAD)" = "$base" ]
		[ "$(git diff --cached --name-only)" = b.txt ]
		[ "$(git rev-parse refs/remotes/origin/develop)" = "$tracking" ]
		git review abort
	done

	git update-ref -d refs/remotes/origin/develop
	run git review start --from origin --no-walk -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$base" ]
	[ "$(git diff --cached --name-only)" = b.txt ]
	! git show-ref --verify --quiet refs/remotes/origin/develop
}

@test "start resolves and pins a new lower bound tag despite a local branch of the same name" {
	make_two_commit_feature
	lower=$(git rev-parse feature/two^)
	git clone -q --branch develop "$ORIGIN" "$TMP/reader"
	git tag -a checkpoint -m checkpoint "$lower"
	git push -q origin refs/tags/checkpoint
	cd "$TMP/reader"
	git branch checkpoint develop
	tracking=$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes)

	for selector in checkpoint refs/tags/checkpoint; do
		run git review start --prepare --from "$selector" -- feature/two
		[ "$status" -eq 0 ]
		token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
		[ -n "$token" ]
		run git review start "--prepared=$token" --from "$selector" --no-walk -- feature/two
		[ "$status" -eq 0 ]
		[ "$(git rev-parse HEAD)" = "$lower" ]
		[ "$(git diff --cached --name-only)" = b.txt ]
		[ -z "$(git tag --list)" ]
		[ "$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes)" = "$tracking" ]
		git review abort
		git review start --release -- "$token"
	done
}

@test "an excluded optional base does not block an incremental prepared range or draft" {
	make_two_commit_feature
	lower=$(git rev-parse feature/two^)
	git config reviewworkflow.feature/two.reviewed "$lower"
	git config --add remote.origin.fetch '^refs/heads/develop'
	git update-ref -d refs/remotes/origin/develop
	git switch -qc reader-work
	git branch -D develop

	run git review start --from "$lower" --no-walk -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git diff --cached --name-only)" = b.txt ]
	git review abort

	run git review start --prepare --delta -- feature/two
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
	[ -n "$token" ]
	run git review walkthrough draft --delta "--start-prepared=$token" -- feature/two
	[ "$status" -eq 0 ]
	[ "$(sed -n '/^## ?\. /p' .git/review-walkthrough/feature/two.md)" = '## ?. b.txt' ]
	git review start --release -- "$token"
	run git review start --from-draft --delta --no-walk -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$lower" ]
	[ "$(git diff --cached --name-only)" = b.txt ]
	! git show-ref --verify --quiet refs/remotes/origin/develop
}

@test "start compare and forget honor remote PR refspecs" {
	make_two_commit_feature
	previous=$(git rev-parse feature/two^)
	tip=$(git rev-parse feature/two)
	git --git-dir="$ORIGIN" update-ref refs/pull/42/head "$tip"
	git config --add remote.origin.fetch '+refs/pull/*/head:refs/remotes/origin/pr/*'
	git update-ref refs/remotes/origin/pr/42 "$previous"
	git config reviewworkflow.pr/42.reviewed "$previous"
	git fetch -q origin develop
	fetch_head=$(cat .git/FETCH_HEAD)

	run git review forget --delta --stale
	[ "$status" -eq 0 ]
	[ "$(git config reviewworkflow.pr/42.reviewed)" = "$previous" ]

	run git review compare --prepare --porcelain -- refs/remotes/origin/pr/42 fetch:origin:pr/42
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comparison-prepared" {print $2}')
	[ -n "$token" ]
	[ "$(git rev-parse "refs/worktree/review-compare/pending/$token^2")" = "$tip" ]
	git review compare --release -- "$token"

	run git review start --delta --no-walk -- pr/42
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/pr/42.reviewtip)" = "$tip" ]
	[ "$(git diff --cached --name-only)" = b.txt ]
	[ "$(git rev-parse refs/remotes/origin/pr/42)" = "$previous" ]
	[ "$(cat .git/FETCH_HEAD)" = "$fetch_head" ]
}

@test "an abbreviated source in a fetch refspec uses Git ref precedence" {
	make_two_commit_feature
	tip=$(git rev-parse feature/two)
	git --git-dir="$ORIGIN" update-ref refs/heads/checkpoint develop
	git --git-dir="$ORIGIN" update-ref refs/tags/checkpoint "$tip"
	git config --add remote.origin.fetch '+checkpoint:refs/remotes/origin/batch'

	run git review start --no-walk batch
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/batch.reviewtip)" = "$tip" ]
	[ "$(git diff --cached --name-only)" = $'a.txt\nb.txt' ]
	! git show-ref --verify --quiet refs/tags/checkpoint
	! git show-ref --verify --quiet refs/remotes/origin/batch
}

@test "start resolves ancestry of a fresh remote base without updating tracking refs" {
	make_two_commit_feature
	base=$(git rev-parse feature/two^)
	git push -q origin "$base:refs/heads/integration"
	git config --add remote.origin.fetch '+refs/heads/integration:refs/remotes/origin/baseline'
	git fetch -q origin
	tracking=$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes)
	git --git-dir="$ORIGIN" update-ref refs/heads/integration "$(git rev-parse feature/two)"

	for selector in origin/baseline~1 refs/remotes/origin/baseline^; do
		run git review start feature/two --base "$selector" --no-walk
		[ "$status" -eq 0 ]
		[ "$(git config branch.review/feature/two.reviewbasecommit)" = "$base" ]
		[ "$(git diff --cached --name-only)" = b.txt ]
		[ "$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes)" = "$tracking" ]
		git review abort
		[ -z "$(git for-each-ref refs/worktree/review-start/)" ]
	done
}

@test "base branch names take precedence over abbreviated Git namespaces" {
	make_two_commit_feature
	base=$(git rev-parse feature/two^)
	git tag release develop
	for name in tags/release heads/stable remotes/stable origin/stable; do
		git --git-dir="$ORIGIN" update-ref "refs/heads/$name" "$base"
		git fetch -q origin
		git config reviewworkflow.base "$name"

		run git review config --porcelain -- feature/two
		[ "$status" -eq 0 ]
		[[ "$output" == *$'offer\twhole\tavailable'* ]]
		run git review start --no-walk -- feature/two
		[ "$status" -eq 0 ]
		[ "$(git config branch.review/feature/two.reviewbasecommit)" = "$base" ]
		[ "$(git diff --cached --name-only)" = b.txt ]
		git review abort

		run git review start --prepare -- feature/two
		[ "$status" -eq 0 ]
		token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
		[ -n "$token" ]
		run git review walkthrough draft --force "--start-prepared=$token" -- feature/two
		[ "$status" -eq 0 ]
		[ "$(sed -n '/^## ?\. /p' .git/review-walkthrough/feature/two.md)" = '## ?. b.txt' ]
		run git review start "--prepared=$token" --no-walk -- feature/two
		[ "$status" -eq 0 ]
		[ "$(git config branch.review/feature/two.reviewbasecommit)" = "$base" ]
		[ "$(git diff --cached --name-only)" = b.txt ]
		git review abort
		git review start --release -- "$token"
	done
}

@test "start resolves a fetched reflog tip without changing the cached compare or reflog" {
	bats_require_minimum_version 1.5.0
	make_two_commit_feature
	cached=$(git rev-parse feature/two^)
	lower=$(git rev-parse develop)
	git --git-dir="$ORIGIN" update-ref refs/heads/checkpoint "$lower"
	git config --add remote.origin.fetch '+refs/heads/checkpoint:refs/remotes/origin/boundary'
	tracking=refs/remotes/origin/boundary
	selector='origin/boundary@{0}'
	git -c core.logAllRefUpdates=false update-ref "$tracking" "$cached"
	! git reflog exists "$tracking"
	run --separate-stderr git -c core.logAllRefUpdates=false review start --from "$selector" --no-walk -- feature/two
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'unknown commit: origin/boundary@{0}'* ]]
	[ "$(git branch --show-current)" = develop ]

	run git review start --from "$selector" --no-walk -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$lower" ]
	[ "$(git diff --cached --name-only)" = $'a.txt\nb.txt' ]
	git review abort
	! git reflog exists "$tracking"

	git update-ref -d "$tracking"
	git update-ref --create-reflog "$tracking" "$cached"
	before=$(git reflog show --format='%H %gs' "$tracking")

	run git review compare --prepare --porcelain -- "$selector" fetch:origin:boundary
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comparison-prepared" {print $2}')
	[ -n "$token" ]
	[ "$(git rev-parse "refs/worktree/review-compare/pending/$token^1")" = "$cached" ]
	[ "$(git rev-parse "refs/worktree/review-compare/pending/$token^2")" = "$lower" ]
	git review compare --release -- "$token"

	run git review start --base "$selector" --no-walk -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/two.reviewbasecommit)" = "$lower" ]
	[ "$(git diff --cached --name-only)" = $'a.txt\nb.txt' ]
	git review abort

	run git review start --prepare --from "$selector" -- feature/two
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
	[ -n "$token" ]
	git --git-dir="$ORIGIN" update-ref refs/heads/checkpoint "$cached"
	run git review start "--prepared=$token" --from "$selector" --no-walk -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$lower" ]
	[ "$(git diff --cached --name-only)" = $'a.txt\nb.txt' ]
	[ "$(git rev-parse "$tracking")" = "$cached" ]
	[ "$(git reflog show --format='%H %gs' "$tracking")" = "$before" ]
}

@test "start resolves numbered and dated reflog selectors like a normal fetch" {
	make_two_commit_feature
	first=$(git rev-parse develop)
	second=$(git rev-parse feature/two^)
	fresh=$(git rev-parse feature/two)
	git --git-dir="$ORIGIN" update-ref refs/heads/checkpoint "$fresh"
	tracking=refs/remotes/origin/checkpoint
	GIT_COMMITTER_DATE='2020-01-01T00:00:00Z' git update-ref --create-reflog "$tracking" "$first"
	git tag -a checkpoint-tag -m checkpoint "$second"
	cached=$(git rev-parse refs/tags/checkpoint-tag)
	GIT_COMMITTER_DATE='2021-01-01T00:00:00Z' git update-ref "$tracking" "$cached"
	before=$(git rev-parse "$tracking@{0}" "$tracking@{1}")

	for selector in 'origin/checkpoint@{1}^{tag}' 'origin/checkpoint@{2021-06-01}^{tag}' 'origin/checkpoint@{1622505600}^{tag}'; do
		run git review start --from "$selector" --no-walk -- feature/two
		[ "$status" -eq 0 ]
		[ "$(git rev-parse HEAD)" = "$second" ]
		[ "$(git diff --cached --name-only)" = b.txt ]
		git review abort
	done
	for selector in 'origin/checkpoint@{2}' 'origin/checkpoint@{1}^' 'origin/checkpoint@{2020-06-01}'; do
		run git review start --from "$selector" --no-walk -- feature/two
		[ "$status" -eq 0 ]
		[ "$(git rev-parse HEAD)" = "$first" ]
		[ "$(git diff --cached --name-only)" = $'a.txt\nb.txt' ]
		git review abort
	done
	[ "$(git rev-parse "$tracking")" = "$cached" ]
	[ "$(git rev-parse "$tracking@{0}" "$tracking@{1}")" = "$before" ]
}

@test "start resolves a fresh remote lower bound and pins it when prepared" {
	make_two_commit_feature
	cached=$(git rev-parse feature/two^)
	lower=$(git rev-parse develop)
	git push -q origin "$cached:refs/heads/checkpoint"
	git config --add remote.origin.fetch '+refs/heads/checkpoint:refs/remotes/origin/boundary'
	git fetch -q origin
	tracking=$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes)
	git --git-dir="$ORIGIN" update-ref refs/heads/checkpoint "$lower"
	git config branch.develop.merge refs/heads/checkpoint

	for selector in origin/boundary '@{upstream}'; do
		run git review start feature/two --from "$selector" --no-walk
		[ "$status" -eq 0 ]
		[ "$(git rev-parse HEAD)" = "$lower" ]
		[ "$(git diff --cached --name-only)" = $'a.txt\nb.txt' ]
		git review abort
		[ -z "$(git for-each-ref refs/worktree/review-start/)" ]
	done

	run git review start --prepare --from refs/remotes/origin/boundary -- feature/two
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
	[ -n "$token" ]
	[ "$(git for-each-ref --format='%(refname)' refs/worktree/review-start/)" = "refs/worktree/review-start/pending/$token" ]
	git --git-dir="$ORIGIN" update-ref refs/heads/checkpoint "$cached"
	git remote set-url origin "$TMP/unavailable"
	run git review start "--prepared=$token" --from refs/remotes/origin/boundary --no-walk -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$lower" ]
	[ "$(git diff --cached --name-only)" = $'a.txt\nb.txt' ]
	[ "$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes)" = "$tracking" ]

	git review abort
	git review start --release -- "$token"
	run git review start feature/two --offline --from origin/boundary --no-walk
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$cached" ]
	[ "$(git diff --cached --name-only)" = b.txt ]
}

@test "start refreshes exact fetch destinations and preserves literal comparisons" {
	make_two_commit_feature
	cached=$(git rev-parse feature/two^)
	lower=$(git rev-parse develop)
	destination=refs/integration/checkpoint
	git --git-dir="$ORIGIN" update-ref refs/heads/checkpoint "$cached"
	git config --add remote.origin.fetch '+refs/heads/checkpoint:refs/integration/checkpoint'
	git config --add remote.origin.fetch '+refs/heads/checkpoint:refs/remotes/origin/boundary'
	git fetch -q origin
	git --git-dir="$ORIGIN" update-ref refs/heads/checkpoint "$lower"
	refs_before=$(git for-each-ref --format='%(refname) %(objectname)' refs/integration refs/remotes)
	fetch_head=$(cat .git/FETCH_HEAD)

	for option in --base --from; do
		run git review start "$option" "$destination" --no-walk -- feature/two
		[ "$status" -eq 0 ]
		if [ "$option" = --base ]; then [[ "$output" == *"ready (vs $destination)"* ]]; fi
		[ "$(git rev-parse HEAD)" = "$lower" ]
		[ "$(git diff --cached --name-only)" = $'a.txt\nb.txt' ]
		git review abort

		run git review start --prepare "$option" "$destination" -- feature/two
		[ "$status" -eq 0 ]
		token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
		[ -n "$token" ]
		run git review start "--prepared=$token" "$option" "$destination" --no-walk -- feature/two
		[ "$status" -eq 0 ]
		if [ "$option" = --base ]; then [[ "$output" == *"ready (vs $destination)"* ]]; fi
		[ "$(git rev-parse HEAD)" = "$lower" ]
		[ "$(git diff --cached --name-only)" = $'a.txt\nb.txt' ]
		git review abort
		git review start --release -- "$token"
	done

	run git review compare --prepare --porcelain -- "$destination" fetch:origin:boundary
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comparison-prepared" {print $2}')
	[ -n "$token" ]
	ref="refs/worktree/review-compare/pending/$token"
	[ "$(git rev-parse "$ref^1")" = "$cached" ]
	[ "$(git rev-parse "$ref^2")" = "$lower" ]
	git review compare --release -- "$token"
	git config reviewworkflow.boundary.reviewed "$cached"
	run git review forget --delta --stale
	[ "$status" -eq 0 ]
	[ "$(git config reviewworkflow.boundary.reviewed)" = "$cached" ]

	! git reflog exists "$destination"
	run git review start --from "$destination@{0}" --no-walk -- feature/two
	[ "$status" -eq 1 ]
	[[ "$output" == *"unknown commit: $destination@{0}"* ]]
	[ "$(git branch --show-current)" = develop ]
	run git -c core.logAllRefUpdates=always review start --from "$destination@{0}" --no-walk -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$lower" ]
	[ "$(git diff --cached --name-only)" = $'a.txt\nb.txt' ]
	git review abort
	! git reflog exists "$destination"

	run git review start --from integration/checkpoint --no-walk -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$lower" ]
	git review abort
	[ "$(git for-each-ref --format='%(refname) %(objectname)' refs/integration refs/remotes)" = "$refs_before" ]
	[ "$(cat .git/FETCH_HEAD)" = "$fetch_head" ]

	git update-ref -d "$destination"
	run git review start --from "$destination" --no-walk -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$lower" ]
	[ "$(git diff --cached --name-only)" = $'a.txt\nb.txt' ]
	! git show-ref --verify --quiet "$destination"
}

@test "prepared start pins the fetched tip without updating tracking refs" {
	cached=$(git rev-parse refs/remotes/origin/feature/x)
	local_base=$(git rev-parse refs/remotes/origin/develop)
	push_pr2
	fresh=$(git rev-parse refs/remotes/origin/feature/x)
	git update-ref refs/remotes/origin/feature/x "$cached"
	new_base=$(git commit-tree "$local_base^{tree}" -p "$local_base" -m 'advance remote base')
	git push -q origin "$new_base:refs/heads/develop"
	git update-ref refs/remotes/origin/develop "$local_base"
	git config fetch.prune true
	git update-ref refs/remotes/origin/previously-deleted "$local_base"
	run git review start --prepare -- feature/x
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
	[ -n "$token" ]
	[ "$(git rev-parse refs/remotes/origin/feature/x)" = "$cached" ]
	[ "$(git rev-parse refs/remotes/origin/develop)" = "$local_base" ]
	[ "$(git rev-parse refs/remotes/origin/previously-deleted)" = "$local_base" ]
	[ "$(git branch --show-current)" = develop ]
	git switch -q feature/x
	git commit -q --allow-empty -m 'advance after preparation'
	git push -q origin feature/x
	git switch -q develop
	git update-ref refs/remotes/origin/feature/x "$cached"
	run git review start "--prepared=$token" --no-walk -- feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewtip)" = "$fresh" ]
	[ "$(git config branch.review/feature/x.reviewbasecommit)" = "$new_base" ]
	[ "$(git rev-parse refs/remotes/origin/feature/x)" = "$cached" ]
	run git review start --release -- "$token"
	[ "$status" -eq 0 ]
	run git review finish
	[ "$status" -eq 0 ]
	run git review clean --keep-fixes feature/x
	[ "$status" -eq 0 ]
	[ -z "$(git for-each-ref refs/worktree/review-start/)" ]
	[ "$(git for-each-ref --format='%(objectname)' refs/review-delta/)" = "$fresh" ]
	run git review forget --delta feature/x
	[ "$status" -eq 0 ]
	[ -z "$(git for-each-ref refs/review-delta/)" ]
}

@test "start resolves new destinations with the same precedence as Git fetch" {
	make_two_commit_feature
	git fetch -q origin develop
	cutoff=$(git rev-parse develop)
	homonym=$(git rev-parse feature/two^)
	git clone -q --branch develop "$ORIGIN" "$TMP/oracle"
	destination=refs/integration/checkpoint
	git --git-dir="$ORIGIN" update-ref refs/heads/checkpoint "$cutoff"
	for reader in "$TMP/oracle" "$PWD"; do
		git -C "$reader" config --add remote.origin.fetch "+refs/heads/checkpoint:$destination"
		git -C "$reader" branch integration/checkpoint "$homonym"
	done
	! git show-ref --verify --quiet "$destination"
	git -C "$TMP/oracle" fetch -q origin
	expected=$(git -C "$TMP/oracle" rev-parse --verify integration/checkpoint 2>/dev/null)
	[ "$expected" = "$cutoff" ]
	refs_before=$(git for-each-ref --format='%(refname) %(objectname)' refs/heads refs/remotes refs/integration)
	fetch_before=$(cat .git/FETCH_HEAD)

	for option in --base --from; do
		run git review start "$option" integration/checkpoint --no-walk -- feature/two
		[ "$status" -eq 0 ]
		[ "$(git rev-parse HEAD)" = "$expected" ]
		[ "$(git diff --cached --name-only)" = $'a.txt\nb.txt' ]
		git review abort
	done

	run git review start --prepare --from integration/checkpoint -- feature/two
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
	[ -n "$token" ]
	run git review start "--prepared=$token" --from integration/checkpoint --no-walk -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$expected" ]
	[ "$(git diff --cached --name-only)" = $'a.txt\nb.txt' ]
	git review abort
	git review start --release -- "$token"
	[ "$(git for-each-ref --format='%(refname) %(objectname)' refs/heads refs/remotes refs/integration)" = "$refs_before" ]
	[ "$(cat .git/FETCH_HEAD)" = "$fetch_before" ]
}

@test "start supports previously unfetched upstream push and message selectors" {
	make_two_commit_feature
	cutoff=$(git rev-parse feature/two^)
	git config branch.develop.merge refs/heads/checkpoint
	git config push.default upstream
	git --git-dir="$ORIGIN" update-ref refs/heads/checkpoint "$cutoff"
	message=$(git log -1 --format=%s "$cutoff")
	! git show-ref --verify --quiet refs/remotes/origin/checkpoint

	for selector in 'develop@{upstream}' 'develop@{push}' ":/$message"; do
		run git review start --from "$selector" --no-walk -- feature/two
		[ "$status" -eq 0 ]
		[ "$(git rev-parse HEAD)" = "$cutoff" ]
		[ "$(git diff --cached --name-only)" = b.txt ]
		git review abort
		! git show-ref --verify --quiet refs/remotes/origin/checkpoint
	done

	message='cutoff visible through another remote branch'
	other=$(git commit-tree "$cutoff^{tree}" -p "$cutoff" -m "$message")
	git push -q origin "$other:refs/heads/search-target"
	git update-ref -d refs/remotes/origin/search-target
	! git rev-parse --verify --quiet ":/$message"
	run git review start --base ":/$message" --no-walk -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/two.reviewbasecommit)" = "$other" ]
	[ "$(git diff --cached --name-only)" = b.txt ]
	git review abort
	! git show-ref --verify --quiet refs/remotes/origin/search-target

	git update-ref refs/remotes/origin/checkpoint "$cutoff"
	git --git-dir="$ORIGIN" update-ref -d refs/heads/checkpoint
	run git -c fetch.prune=false review start --from origin/checkpoint --no-walk -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git diff --cached --name-only)" = b.txt ]
	[ "$(git rev-parse refs/remotes/origin/checkpoint)" = "$cutoff" ]
}

@test "start resolves and pins the same parents as Git with replacement refs" {
	make_two_commit_feature
	git fetch -q origin develop
	tip=$(git rev-parse feature/two)
	first=$(git rev-parse feature/two^)
	base=$(git rev-parse develop)
	replacement=$(git commit-tree "$tip^{tree}" -p "$base" -p "$first" -m reordered-parents)
	git replace "$tip" "$replacement"
	git update-ref "refs/other-replacements/$tip" "$replacement"
	selector=origin/feature/two^
	fetch_before=$(cat .git/FETCH_HEAD)
	refs_before=$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes refs/other-replacements)

	for replacement_mode in default disabled custom; do
		unset GIT_NO_REPLACE_OBJECTS GIT_REPLACE_REF_BASE
		case "$replacement_mode" in
			default) want_cutoff=$base; want_paths=$'a.txt\nb.txt' ;;
			disabled) export GIT_NO_REPLACE_OBJECTS=; want_cutoff=$first; want_paths=b.txt ;;
			custom) export GIT_REPLACE_REF_BASE=refs/other-replacements/; want_cutoff=$base; want_paths=$'a.txt\nb.txt' ;;
		esac
		cutoff=$(git rev-parse --verify "$selector")
		[ "$cutoff" = "$want_cutoff" ]
		run git review start --prepare --from "$selector" -- feature/two
		[ "$status" -eq 0 ]
		token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
		[ -n "$token" ]
		run git review start "--prepared=$token" --from "$selector" --no-walk -- feature/two
		[ "$status" -eq 0 ]
		[ "$(git config branch.review/feature/two.reviewrangefrom)" = "$cutoff" ]
		[ "$(git diff --cached --name-only)" = "$want_paths" ]
		git review abort
		git review start --release -- "$token"
		if [ "$replacement_mode" = disabled ]; then git replace -d "$tip"; fi
	done
	[ "$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes refs/other-replacements)" = "$refs_before" ]
	[ "$(cat .git/FETCH_HEAD)" = "$fetch_before" ]
}

@test "start resolves ancestry from the graft file used by Git" {
	make_two_commit_feature
	tip=$(git rev-parse feature/two)
	first=$(git rev-parse feature/two^)
	base=$(git rev-parse develop)
	export GIT_GRAFT_FILE="$TMP/review.grafts"
	printf '%s %s %s\n' "$tip" "$base" "$first" >"$GIT_GRAFT_FILE"
	git config advice.graftFileDeprecated false
	selector=origin/feature/two^
	cutoff=$(git rev-parse --verify "$selector")
	[ "$cutoff" = "$base" ]

	run git review start --from "$selector" --no-walk -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/two.reviewrangefrom)" = "$cutoff" ]
	[ "$(git diff --cached --name-only)" = $'a.txt\nb.txt' ]
	[ "$(cat "$GIT_GRAFT_FILE")" = "$tip $base $first" ]
}

@test "start refuses a fetch that would change its replacement refs" {
	bats_require_minimum_version 1.5.0
	tip=$(git rev-parse feature/x)
	git switch -qc replacement develop
	printf 'alternate\n' >alternate.txt
	git add alternate.txt
	git commit -qm alternate
	git push -q origin "HEAD:refs/replace/$tip"
	git switch -q develop
	git fetch -q origin develop
	git config --add remote.origin.fetch '+refs/replace/*:refs/replace/*'
	refs_before=$(git for-each-ref --format='%(refname) %(objectname)')
	fetch_before=$(git hash-object .git/FETCH_HEAD)

	for flag in --no-walk --prepare; do
		run --separate-stderr git review start "$flag" -- feature/x
		[ "$status" -eq 1 ]
		[ "$stdout" = '' ]
		[ "$stderr" = 'error: fetch changed the replacement refs. Fetch manually and prepare the review again.' ]
		[ "$(git branch --show-current)" = develop ]
		[ "$(git for-each-ref --format='%(refname) %(objectname)')" = "$refs_before" ]
		[ "$(git hash-object .git/FETCH_HEAD)" = "$fetch_before" ]
		[ -z "$(git diff --cached --name-only)" ]
	done

	run git -c core.useReplaceRefs=false review start --no-walk -- feature/x
	[ "$status" -eq 0 ]
	[ "$(git diff --cached --name-only)" = app.txt ]
	git review abort

	git fetch -q origin
	expected=$(git diff --name-only develop origin/feature/x)
	[ "$expected" = alternate.txt ]
	run git review start --no-walk -- feature/x
	[ "$status" -eq 0 ]
	[ "$(git diff --cached --name-only)" = "$expected" ]
}

@test "temporary fetch honors worktree config and preserves linked ref stores" {
	make_two_commit_feature
	cutoff=$(git rev-parse feature/two^)
	for format in files reftable; do
		if [ "$format" = reftable ] && ! git init -h 2>&1 | grep -q -- --ref-format; then
			continue
		fi
		reader="$TMP/reader-$format"
		linked="$TMP/linked-$format"
		GIT_DEFAULT_REF_FORMAT="$format" git clone -q --branch develop "$ORIGIN" "$reader"
		git -C "$reader" worktree add -q -b reading "$linked" develop
		git -C "$reader" config extensions.worktreeConfig true
		git -C "$linked" config --worktree branch.reading.remote origin
		linked_dir=$(git -C "$linked" rev-parse --absolute-git-dir)
		include_file="$TMP/linked-$format.config"
		git config --file "$include_file" branch.reading.merge "refs/heads/cutoff-$format"
		git config --global "includeIf.gitdir:$linked_dir.path" "$include_file"
		[ "$(git -C "$linked" config branch.reading.merge)" = "refs/heads/cutoff-$format" ]
		git --git-dir="$ORIGIN" update-ref "refs/heads/cutoff-$format" "$cutoff"
		! git -C "$linked" show-ref --verify --quiet "refs/remotes/origin/cutoff-$format"

		run git -C "$linked" review start --from '@{upstream}' --no-walk -- feature/two
		[ "$status" -eq 0 ]
		[ "$(git -C "$linked" rev-parse HEAD)" = "$cutoff" ]
		[ "$(git -C "$linked" diff --cached --name-only)" = b.txt ]
		! git -C "$linked" show-ref --verify --quiet "refs/remotes/origin/cutoff-$format"
		[ "$(git -C "$reader" branch --show-current)" = develop ]
	done
}

@test "an explicit cutoff survives draft preparation save and reopen" {
	make_two_commit_feature
	cutoff=$(git rev-parse feature/two^)
	git config --unset reviewworkflow.base

	run git review start --prepare --from "$cutoff" -- feature/two
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
	[ -n "$token" ]
	run git review walkthrough draft "--start-prepared=$token" -- feature/two
	[ "$status" -eq 0 ]
	[ "$(sed -n '/^## ?\. /p' .git/review-walkthrough/feature/two.md)" = '## ?. b.txt' ]
	git review start --release -- "$token"

	run git review config --porcelain --from-draft -- feature/two
	[ "$status" -eq 0 ]
	[[ "$output" == *$'start-draft-range\t1'* ]]
	[[ "$output" == *$'offer\twhole\tavailable'* ]]
	run git review start --from-draft --no-walk -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$cutoff" ]
	[ "$(git diff --cached --name-only)" = b.txt ]
	git review save
	git review continue feature/two
	run git review walkthrough draft --stdout
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | sed -n '/^## ?\. /p')" = '## ?. b.txt' ]
}

@test "review draft created from a prepared start retains its selected range" {
	cached=$(git rev-parse refs/remotes/origin/feature/x)
	push_pr2
	fresh=$(git rev-parse refs/remotes/origin/feature/x)
	git update-ref refs/remotes/origin/feature/x "$cached"
	run git review start --prepare -- feature/x
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
	run git review walkthrough draft --porcelain "--start-prepared=$token" -- feature/x
	[ "$status" -eq 0 ]
	run git review start --release -- "$token"
	[ "$status" -eq 0 ]
	run git review config --porcelain --from-draft -- feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *$'start-draft-range\t1'* ]]
	run git review start --from-draft --no-walk -- feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewtip)" = "$fresh" ]
	[ "$(git rev-parse refs/remotes/origin/feature/x)" = "$cached" ]
}

@test "prepared drafts coexist when a branch becomes a prefix of another" {
	run git review start --prepare -- feature/x
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
	[ -n "$token" ]
	run git review walkthrough draft "--start-prepared=$token" -- feature/x
	[ "$status" -eq 0 ]
	git review start --release -- "$token"
	first=.git/review-walkthrough/feature/x.md
	first_oid=$(git hash-object "$first")

	git push -q origin :feature/x
	git branch -D feature/x
	git switch -qc feature/x/next develop
	printf 'next\n' >next.txt
	git add next.txt
	git commit -qm next
	git push -q origin feature/x/next
	git switch -q develop

	run git review start --prepare -- feature/x/next
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
	[ -n "$token" ]
	run git review walkthrough draft "--start-prepared=$token" -- feature/x/next
	[ "$status" -eq 0 ]
	git review start --release -- "$token"
	[ "$(git hash-object "$first")" = "$first_oid" ]
	[ "$(sed -n '/^## ?\. /p' .git/review-walkthrough/feature/x/next.md)" = '## ?. next.txt' ]

	run git review forget --draft feature/x
	[ "$status" -eq 0 ]
	[ ! -e "$first" ]
	run git review config --porcelain --from-draft -- feature/x/next
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | sed -n '/^start-draft-range/p')" = $'start-draft-range\t1' ]
}

@test "a draft keeps its explicit base when validated and reopened from another branch" {
	bats_require_minimum_version 1.5.0
	make_two_commit_feature
	alternate=$(git rev-parse feature/two^)
	git branch alternate "$alternate"
	git push -q origin alternate
	git review start --base alternate --no-walk -- feature/two
	git review walkthrough draft
	draft=.git/review-walkthrough/feature/two.md
	[ "$(sed -n '/^## ?\. /p' "$draft")" = '## ?. b.txt' ]
	printf '# Walkthrough\n\n## 1. b.txt\nRead the second change.\n' >"$draft"
	git review abort
	[ "$(git branch --show-current)" = develop ]
	git push -q origin :alternate
	git branch -D alternate
	git config --unset reviewworkflow.base

	run git review walkthrough draft --build -- feature/two
	[ "$status" -eq 0 ]
	[[ "$output" == *'git review start --from-draft -- feature/two now reads it'* ]]
	run git review config --porcelain --from-draft -- feature/two
	[ "$status" -eq 0 ]
	[[ "$output" == *$'start-draft-range\t1'* ]]
	[[ "$output" == *$'offer\twalk\trecommended'* ]]

	run --separate-stderr git review start --from-draft --base develop -- feature/two
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: prepared review does not match the selected branch and range' ]
	[ "$(git branch --show-current)" = develop ]
	run git review start --from-draft -- feature/two
	[ "$status" -eq 0 ]
	[[ "$output" == *'vs origin/alternate'* ]]
	[ "$(git config branch.review/feature/two.reviewbase)" = alternate ]
	[ "$(git config branch.review/feature/two.reviewbasecommit)" = "$alternate" ]
	[ "$(git config branch.review/feature/two.reviewmode)" = walk ]
	[ "$(git diff --cached --name-only)" = b.txt ]
}

@test "build validates an active draft against the open review and pins that range" {
	make_two_commit_feature
	first=$(git rev-parse feature/two^)
	tip=$(git rev-parse feature/two)
	git push -q --force origin "$first:refs/heads/feature/two"
	git review start --no-walk -- feature/two
	git review walkthrough draft
	draft=.git/review-walkthrough/feature/two.md
	[ "$(sed -n '/^## ?\. /p' "$draft")" = '## ?. a.txt' ]
	git review abort

	git push -q origin "$tip:refs/heads/feature/two"
	git review start --no-walk -- feature/two
	[ "$(git diff --cached --name-only)" = $'a.txt\nb.txt' ]
	saved_range=$(git for-each-ref --format='%(objectname)' refs/worktree/review-start/draft-key/)
	[ -n "$saved_range" ]
	printf '# Walkthrough\n\n## 1. a.txt\nFirst change.\n' >"$draft"
	draft_oid=$(git hash-object "$draft")
	run git review walkthrough draft --build
	[ "$status" -eq 1 ]
	[ "$output" = 'error: changed in the PR but missing from the walkthrough: b.txt' ]
	[ "$(git hash-object "$draft")" = "$draft_oid" ]
	[ "$(git for-each-ref --format='%(objectname)' refs/worktree/review-start/draft-key/)" = "$saved_range" ]

	printf '# Walkthrough\n\n## 1. a.txt\nFirst change.\n\n## 2. b.txt\nSecond change.\n' >"$draft"
	run git review walkthrough draft --build
	[ "$status" -eq 0 ]
	[[ "$output" == *'git review start --from-draft -- feature/two now reads it'* ]]
	git review abort

	git push -q --force origin "$first:refs/heads/feature/two"
	run git review config --porcelain --from-draft -- feature/two
	[ "$status" -eq 0 ]
	[[ "$output" == *$'offer\twalk\trecommended'* ]]
	run git review start --from-draft --no-walk -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/two.reviewtip)" = "$tip" ]
	[ "$(git diff --cached --name-only)" = $'a.txt\nb.txt' ]
}

@test "drafting for an active delta keeps the review's previous point" {
	make_two_commit_feature
	first=$(git rev-parse feature/two^)
	git config reviewworkflow.feature/two.reviewed "$first"
	git review start --delta --no-walk -- feature/two
	[ "$(git diff --cached --name-only)" = b.txt ]
	git config reviewworkflow.feature/two.reviewed "$(git rev-parse develop)"

	run git review walkthrough draft --delta
	[ "$status" -eq 0 ]
	draft=.git/review-walkthrough/feature/two.md
	[ "$(sed -n '/^## ?\. /p' "$draft")" = '## ?. b.txt' ]
	[ "$(git config branch.review/feature/two.reviewprevreviewed)" = "$first" ]
}

@test "a legacy draft range remains usable and is replaced on the next draft update" {
	run git review start --prepare -- feature/x
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
	[ -n "$token" ]
	prepared="refs/worktree/review-start/pending/$token"
	legacy="refs/worktree/review-start/draft/feature/x"
	subject=$(git log -1 --format='%s' "$prepared" --)
	range=$(git commit-tree "$prepared^{tree}" -p "$prepared^1" -p "$prepared^2" -m "$subject")
	git update-ref "$legacy" "$range"
	draft=.git/review-walkthrough/feature/x.md
	mkdir -p "$(dirname "$draft")"
	printf '# Walkthrough\n\n## 1. app.txt\nRead the first change.\n' >"$draft"

	run git review config --porcelain --from-draft -- feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *$'start-draft-range\t1'* ]]
	run git review walkthrough draft "--start-prepared=$token" -- feature/x
	[ "$status" -eq 0 ]
	git review start --release -- "$token"
	! git show-ref --verify --quiet "$legacy"
	[ "$(sed -n '/^Read the first change\.$/p' "$draft")" = 'Read the first change.' ]

	run git review start --from-draft -- feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = walk ]
	[ "$(git diff --cached --name-only)" = app.txt ]
}

@test "prepared offline draft preserves its local range through build and start" {
	bats_require_minimum_version 1.5.0
	make_two_commit_feature
	git branch -f feature/two refs/heads/feature/two^
	pinned=$(git rev-parse refs/heads/feature/two)
	git remote set-url origin "$TMP/unavailable"

	run git review start --prepare --offline -- feature/two
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
	[ -n "$token" ]
	git branch -f feature/two refs/remotes/origin/feature/two

	run --separate-stderr git review walkthrough draft --porcelain --offline "--start-prepared=$token" -- feature/two
	[ "$status" -eq 0 ]
	[ "$output" = $'merged\t0\t1\t0' ]
	draft=.git/review-walkthrough/feature/two.md
	[ "$(sed -n '/^## ?\. /p' "$draft")" = '## ?. a.txt' ]
	git review start --release -- "$token"
	printf '# Walkthrough\n\n## 1. a.txt\nwhy\n' >"$draft"

	run git review walkthrough draft --build --offline -- feature/two
	[ "$status" -eq 0 ]
	run git review config --porcelain --from-draft --offline -- feature/two
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | sed -n '/^start-draft-range/p')" = $'start-draft-range\t1' ]
	run git review start --from-draft --offline -- feature/two
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/two.reviewtip)" = "$pinned" ]
	[ "$(git config branch.review/feature/two.reviewmode)" = walk ]
	[ "$(git diff --cached --name-only)" = a.txt ]
}

@test "prepared start pins the explicit lower bound even after its branch moves" {
	make_two_commit_feature
	git branch boundary develop
	lower=$(git rev-parse boundary)
	for layout in --no-walk --step; do
		run git review start --prepare --offline --from boundary -- feature/two
		[ "$status" -eq 0 ]
		token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
		[ -n "$token" ]
		git branch -f boundary feature/two^

		run git review start "--prepared=$token" --offline --from boundary "$layout" -- feature/two
		[ "$status" -eq 0 ]
		[ "$(git rev-parse HEAD)" = "$lower" ]
		if [ "$layout" = --no-walk ]; then
			[ "$(git diff --cached --name-only)" = $'a.txt\nb.txt' ]
		else
			[ "$(git config branch.review/feature/two.reviewcount)" = 2 ]
			[ "$(git diff --cached --name-only)" = a.txt ]
		fi
		git review abort
		git review start --release -- "$token"
		git branch -f boundary "$lower"
	done
}

@test "finish update refuses undo after committing the correction" {
	push_pr2
	git branch -f feature/x origin/feature/x~1
	git review start feature/x
	printf 'a\nB\nc\nd\ne\nfix\n' >app.txt
	git review finish --update-source
	git commit -qm 'publishable correction'
	correction=$(git rev-parse HEAD)
	run git review finish --abort
	[ "$status" -eq 1 ]
	[[ "$output" == *"has changes since the finish"* ]]
	[ "$(git branch --show-current)" = feature/x ]
	[ "$(git rev-parse HEAD)" = "$correction" ]
	git show-ref --verify --quiet refs/review-undo/feature/x/source-before
}

@test "finish leaves a PR branch checked out in another worktree alone" {
	push_pr2
	git branch -f feature/x origin/feature/x~1
	before=$(git rev-parse refs/heads/feature/x)
	git worktree add -q "$TMP/other" feature/x
	git review start feature/x
	run git review finish --destinations --porcelain
	[ "$status" -eq 0 ]
	[ "$output" = "$(printf 'finish-destination\tseparate')" ]
	run git review finish --update-source
	[ "$status" -eq 1 ]
	[[ "$output" == *"checked out in another worktree"* ]]
	[ -z "$(git for-each-ref refs/review-undo/feature/x/)" ]
	[ "$(git -C "$TMP/other" rev-parse HEAD)" = "$before" ]
	[ -z "$(git -C "$TMP/other" status --porcelain)" ]
}

@test "finish leaves the PR tip intact when another worktree takes the branch during finish" {
	bats_require_minimum_version 1.5.0
	push_pr2
	git branch -f feature/x origin/feature/x~1
	before=$(git rev-parse refs/heads/feature/x)
	git worktree add -q --detach "$TMP/other" develop
	git review start feature/x
	printf 'a\nB\nc\nd\ne\nfix\n' >app.txt
	index_before=$(git write-tree)
	review_before=$(git rev-parse HEAD)

	export FINISH_TEST_GIT="$(command -v git)"
	export FINISH_TEST_WORKTREE="$TMP/other"
	mkdir "$TMP/wrapper"
	cat >"$TMP/wrapper/git" <<'EOF'
#!/bin/sh
set -eu
case "$*" in
	"switch -q feature/x"|"update-ref -m git review finish: fast-forward PR branch refs/heads/feature/x "*)
		"$FINISH_TEST_GIT" -C "$FINISH_TEST_WORKTREE" switch -q feature/x
		;;
esac
exec "$FINISH_TEST_GIT" "$@"
EOF
	chmod +x "$TMP/wrapper/git"
	run --separate-stderr env PATH="$TMP/wrapper:$PATH" sh "$BATS_TEST_DIRNAME/../bin/git-review" finish --update-source
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'could not switch to feature/x'* ]]
	[ "$(git branch --show-current)" = review/feature/x ]
	[ "$(git -C "$TMP/other" branch --show-current)" = feature/x ]
	[ "$(git -C "$TMP/other" rev-parse HEAD)" = "$before" ]
	[ -z "$(git -C "$TMP/other" status --porcelain)" ]

	run git review finish --abort
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$review_before" ]
	[ "$(git write-tree)" = "$index_before" ]
	[ "$(tail -n 1 app.txt)" = fix ]
}

@test "finish can update a behind PR branch without review edits" {
	push_pr2
	git branch -f feature/x origin/feature/x~1
	before=$(git rev-parse refs/heads/feature/x)
	git review start feature/x
	tip=$(git config branch.review/feature/x.reviewtip)
	review_before=$(git rev-parse HEAD)
	index_before=$(git write-tree)

	run git review finish --update-source
	[ "$status" -eq 0 ]
	[[ "$output" == *'no review changes to apply'* ]]
	[ "$(git branch --show-current)" = feature/x ]
	[ "$(git rev-parse HEAD)" = "$tip" ]
	[ -z "$(git status --porcelain)" ]
	git switch -q develop

	run git review finish --abort
	[ "$status" -eq 0 ]
	[ "$(git branch --show-current)" = review/feature/x ]
	[ "$(git rev-parse refs/heads/feature/x)" = "$before" ]
	[ "$(git rev-parse HEAD)" = "$review_before" ]
	[ "$(git write-tree)" = "$index_before" ]
}

@test "finish fast-forwards a PR branch configured to squash merges" {
	push_pr2
	git branch -f feature/x refs/remotes/origin/feature/x~1
	before=$(git rev-parse refs/heads/feature/x)
	git config branch.feature/x.mergeOptions --squash
	git review start feature/x
	tip=$(git config branch.review/feature/x.reviewtip)

	run git review finish --update-source
	[ "$status" -eq 0 ]
	[ "$(git branch --show-current)" = feature/x ]
	[ "$(git rev-parse HEAD)" = "$tip" ]
	[ -z "$(git status --porcelain)" ]
	[ "$(git config branch.feature/x.mergeOptions)" = --squash ]

	run git review finish --abort
	[ "$status" -eq 0 ]
	[ "$(git branch --show-current)" = review/feature/x ]
	[ "$(git rev-parse refs/heads/feature/x)" = "$before" ]
}

# ── review clean behaviours ───────────────────────────────────────────────────

@test "review clean with no branch deletes every review branch" {
	git switch --quiet -c feature/y develop
	printf 'a\nb\nc\nY\n' >app.txt
	git add app.txt
	git commit --quiet -m pr1y
	git push --quiet -u origin feature/y
	git switch --quiet develop

	git review start feature/x
	git switch --quiet develop
	git reset --hard --quiet
	git review start feature/y
	git switch --quiet develop
	git reset --hard --quiet

	run git review clean
	[ "$status" -eq 0 ]
	run git for-each-ref refs/heads/review/
	[ -z "$output" ]
}

@test "review clean reports when there are no review branches" {
	run git review clean
	[ "$status" -eq 0 ]
	[[ "$output" == *"no review branches found"* ]]
}

@test "review clean does not claim 'no review branches' when it drops orphaned refs" {
	# An orphaned undo ref with no matching review branch: review clean must
	# still purge it, and it must not pretend it had nothing to do.
	git update-ref refs/review-undo/feature/x/0 "$(git rev-parse HEAD)"

	run git review clean
	[ "$status" -eq 0 ]
	[[ "$output" != *"no review branches found"* ]]
	run git for-each-ref refs/review-undo/
	[ -z "$output" ]
}

@test "review clean rolls back the reviewed tip of an abandoned start (like abort)" {
	# start advances the marker; cleaning an incomplete review must not leave
	# never-reviewed commits skipped for the next --delta.
	git review start feature/x
	git switch --quiet develop
	git reset --hard --quiet
	[ -n "$(git config reviewworkflow.feature/x.reviewed)" ]
	run git review clean feature/x
	[ "$status" -eq 0 ]
	[ -z "$(git config reviewworkflow.feature/x.reviewed || true)" ]
}

# ── review status: banked steps display ───────────────────────────────────────

@test "review status lists banked steps in step mode" {
	git switch --quiet -c feature/two develop
	printf 'a\nb\nc\nP1\n' >app.txt
	git add app.txt
	git commit --quiet -m t1
	printf 'a\nb\nc\nP1\nP2\n' >app.txt
	git add app.txt
	git commit --quiet -m t2
	git push --quiet -u origin feature/two
	git switch --quiet develop

	git review start feature/two --step
	printf 'a\nb\nc\nP1\nEDIT\n' >app.txt
	git review next
	run git review status
	[ "$status" -eq 0 ]
	# The exact line, not a loose grep: it has to name step 1 and only step 1,
	# and the ref really has to exist for it to be reported.
	[ "$(printf '%s\n' "$output" | grep '^  banked')" = "  banked   1" ]
	git rev-parse --verify --quiet refs/review-edits/feature/two/1 >/dev/null
	run git rev-parse --verify --quiet refs/review-edits/feature/two/2
	[ "$status" -ne 0 ]
}

@test "review status banked list tells step 1 apart from step 12" {
	git switch --quiet -c feature/many develop
	i=1
	while [ "$i" -le 12 ]; do
		printf 'line %s\n' "$i" >>app.txt
		git add app.txt
		git commit --quiet -m "c$i"
		i=$((i + 1))
	done
	git push --quiet -u origin feature/many
	git switch --quiet develop

	git review start feature/many --step
	[ "$(git config branch.review/feature/many.reviewcount)" -eq 12 ]
	# Bank steps 2 and 12 directly: what status reports is which refs exist, and
	# this is the only way to get a two-digit step banked without walking the
	# whole review. A membership test over the ref list that forgets the trailing
	# newline reports step 1 as banked too, because the name of the ref for step
	# 12 starts with the name of the ref for step 1.
	git update-ref refs/review-edits/feature/many/2 "$(git rev-parse feature/many~10)"
	git update-ref refs/review-edits/feature/many/12 "$(git rev-parse feature/many)"
	run git review status
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | grep '^  banked')" = "  banked   2 12" ]
}

@test "review status reports no banked steps as none" {
	git review start feature/x --step
	run git review status
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | grep '^  banked')" = "  banked   none" ]
}

# ── partial step metadata: a hand-deleted key must be reported, not die silently ─
#
# These commands read step metadata with `|| true`; under set -e a bare read of a
# missing key would otherwise kill the script with no message.

@test "review status reports a deleted reviewcount key instead of dying silently" {
	git review start feature/x --step
	git config --unset branch.review/feature/x.reviewcount
	run git review status
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
}

@test "review status reports a deleted reviewstep key instead of dying silently" {
	git review start feature/x --step
	git config --unset branch.review/feature/x.reviewstep
	run git review status
	[ "$status" -ne 0 ]
	[[ "$output" == *"corrupt review metadata"* ]]
}

@test "review next reports a deleted reviewstart key instead of dying silently" {
	git review start feature/x --step
	git config --unset branch.review/feature/x.reviewstart
	run git review next
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
}

# ── review finish on corrupt step metadata ────────────────────────────────────
#
# review finish used to read step metadata raw, without the guards the shared
# helper (load_step_review_meta) gives the other commands. Each corrupt key below
# either silently discarded the user's banked edits or died with an opaque shell /
# git / sed diagnostic. It now validates through the helper and reports a clear
# error, the way review next / review status do.

@test "review finish reports a deleted reviewcount instead of saying 'no changes'" {
	# `|| echo 0` defaulted a deleted reviewcount to 0, so the replay loop never
	# ran: every banked edit (FIXA) and the current step's edit (FIXB) were
	# discarded and review finish printed "no review changes to apply" — silent
	# data loss. It must report the corrupt metadata instead.
	step_review_two_with_edits
	git config --unset branch.review/feature/two.reviewcount
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" != *"no review changes to apply"* ]]
	[[ "$output" == *"missing review metadata"* ]]
}

@test "review finish with a deleted reviewcount preserves the undo point for --abort" {
	# The undo point is recorded before the step block runs. The old "no changes"
	# path cleared it, so --abort could not recover; the fix fails before clearing.
	step_review_two_with_edits
	git config --unset branch.review/feature/two.reviewcount
	run git review finish
	[ "$status" -ne 0 ]
	[ -n "$(git config branch.review/feature/two.reviewundohead || true)" ]

	run git review finish --abort
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/two" ]
	# The current step's edit (FIXB) must be back in the working tree.
	run git diff
	[[ "$output" == *"FIXB"* ]]
}

@test "review finish reports reviewcount=0 instead of silently losing edits" {
	step_review_two_with_edits
	git config branch.review/feature/two.reviewcount 0
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" != *"no review changes to apply"* ]]
	[[ "$output" == *"corrupt review metadata"* ]]
}

@test "review finish reports a non-numeric reviewcount instead of a shell error" {
	step_review_two_with_edits
	git config branch.review/feature/two.reviewcount abc
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" != *"no review changes to apply"* ]]
	[[ "$output" == *"corrupt review metadata"* ]]
}

@test "review finish reports a deleted reviewstart instead of dying silently" {
	# reviewstart was read without || true, so set -e killed review finish with no
	# message; the helper reads it with || true and reports it.
	step_review_two_with_edits
	git config --unset branch.review/feature/two.reviewstart
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing review metadata"* ]]
}

@test "review finish reports reviewstep=0 instead of an opaque sed error" {
	# step=0 reached `sed -n "0p"` ("invalid usage of line address 0"); now caught
	# by the helper's range check.
	step_review_two_with_edits
	git config branch.review/feature/two.reviewstep 0
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"out of range"* ]]
}

@test "review finish reports a reviewstep past the last commit instead of a git error" {
	# step past the commit count made `sed -n "${step}p"` empty, so rev-parse died
	# with "ambiguous argument"; now caught by the helper's range check.
	step_review_two_with_edits
	git config branch.review/feature/two.reviewstep 99
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"out of range"* ]]
	# Recovery path when metadata is still enough for abort to run.
	[[ "$output" == *"git review abort"* ]]
}

@test "review finish on a step review with deleted reviewmode does not leak author commits" {
	# With reviewmode gone the step block was skipped and the whole-mode tail diffed
	# the current step commit (c1) against the tip (c2), reversing the author's c2
	# into the extracted fix. The step keys still present make the inconsistency
	# detectable: report it and never build the fix branch.
	make_two_commit_feature
	git review start feature/two --step
	# Stay on step 1 (HEAD = c1, not the tip c2).
	printf 'a2\nFIXA\n' >a.txt
	git config --unset branch.review/feature/two.reviewmode

	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"corrupt review metadata"* ]]
	# No review-fixes branch — so the author's c2 could not have leaked into one.
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/two
	[ "$status" -ne 0 ]
}

# ── a finish, then a second one off the review branch ─────────────────────────

@test "a second review finish is blocked once you are off the review branch" {
	git review start feature/x
	printf 'a\nB\nc\nd\nfix\n' >app.txt
	git review finish
	# the first finish left us on review-fixes/*, no longer a review/* branch
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"not on a review/* branch"* ]]
}
