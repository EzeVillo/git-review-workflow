#!/usr/bin/env bats
#
# The draft's life: what save, continue, clean, forget and finish do with it.
#
# It follows the rule the banked edits already follow — pausing puts it out of
# clean's reach — rather than inventing one of its own. And the thing it must
# never do is show up among the reviewer's extracted edits: it is a reading aid,
# not a change to the PR.

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
	git add a.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop

	git switch --quiet -c feature/x
	printf 'a1\na2\n' >a.txt
	mkdir -p src
	printf 'hello\n' >src/c.txt
	git add -A
	git commit --quiet -m work
	git push --quiet -u origin feature/x

	git switch --quiet develop

	GITDIR="$(git rev-parse --git-dir)"
	DRAFT="$GITDIR/review-walkthrough/feature/x.md"
	SAVED_DRAFT="$GITDIR/review-saved-walkthrough/feature/x.md"

	mkdir -p "$(dirname "$DRAFT")"
	cat >"$DRAFT" <<'EOF'
# Walkthrough

## 1. src/c.txt
> key
start here

## 2. a.txt
then a
EOF
}

teardown() {
	rm -rf "$TMP"
}

# ── save and continue ─────────────────────────────────────────────────────────

@test "save moves the draft out of clean's reach" {
	git review start feature/x
	run git review save
	[ "$status" -eq 0 ]
	[ ! -f "$DRAFT" ]
	[ -f "$SAVED_DRAFT" ]
	grep -Fxq 'start here' "$SAVED_DRAFT"
}

@test "clean prunes a leftover draft but never a paused one" {
	git review start feature/x
	git review save
	run git review clean
	[ "$status" -eq 0 ]
	# The paused review keeps its reading order.
	[ -f "$SAVED_DRAFT" ]
}

@test "clean run from inside a review leaves that review's draft alone" {
	git review start feature/x
	# Standing on the review: clean never touches the branch you are on, so this
	# is the shape of "clean up the leftovers while I am still reviewing".
	run git review clean
	[ "$status" -eq 0 ]
	[ -f "$DRAFT" ]
	# And the review is still readable in the reviewer's own order afterwards.
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk (draft)"* ]]
	[[ "$output" == *"on src/c.txt"* ]]
}

@test "clean from elsewhere takes the review and its draft together" {
	git review start feature/x
	git switch --quiet develop
	run git review clean
	[ "$status" -eq 0 ]
	# review/feature/x is leftover from clean's point of view, so it goes — and the
	# draft goes with it rather than outliving the review it belonged to.
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
	[ ! -f "$DRAFT" ]
}

@test "clean removes a draft whose review is gone" {
	git review start feature/x
	git review abort
	[ -f "$DRAFT" ]
	run git review clean
	[ "$status" -eq 0 ]
	[ ! -f "$DRAFT" ]
}

@test "continue brings the draft back and resumes in the same order" {
	git review start feature/x
	git review next
	run git review status
	[[ "$output" == *"[2/2]"* ]]
	git review save

	run git review continue feature/x
	[ "$status" -eq 0 ]
	[ -f "$DRAFT" ]
	[ ! -f "$SAVED_DRAFT" ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk (draft)"* ]]
	[[ "$output" == *"[2/2]"* ]]
	[[ "$output" == *"on a.txt"* ]]
}

@test "save then clean then continue still resumes on the draft" {
	git review start feature/x
	git review save
	git review clean
	run git review continue feature/x
	[ "$status" -eq 0 ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk (draft)"* ]]
	[[ "$output" == *"on src/c.txt"* ]]
}

@test "forget --saved discards the paused draft with the review" {
	git review start feature/x
	git review save
	run git review forget --saved feature/x
	[ "$status" -eq 0 ]
	[ ! -f "$SAVED_DRAFT" ]
	[ ! -f "$DRAFT" ]
}

# ── finish ────────────────────────────────────────────────────────────────────

@test "the draft never appears among the extracted edits" {
	git review start feature/x
	printf 'hello\nreviewer edit\n' >src/c.txt
	run git review finish
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]
	# finish lands the reviewer's edits staged on review-fixes/, so the staged set
	# IS the extraction. It must be the edited file and nothing else.
	[ "$(git diff --cached --name-only)" = "src/c.txt" ]
	# And nothing named after the draft is tracked anywhere on that branch.
	run git ls-tree -r --name-only HEAD
	[ "$status" -eq 0 ]
	[[ "$output" != *"review-walkthrough"* ]]
}

@test "finish leaves the draft in place for a later re-review" {
	git review start feature/x
	printf 'hello\nreviewer edit\n' >src/c.txt
	git review finish
	[ -f "$DRAFT" ]
}

# ── no effect on an active review ─────────────────────────────────────────────

@test "drafting for another branch does not disturb an active review" {
	git review start feature/x
	before_mode="$(git config branch.review/feature/x.reviewmode)"
	before_step="$(git config branch.review/feature/x.reviewwalkstep)"

	run git review walkthrough draft --offline develop
	# develop has no changes vs itself, so this refuses — the point is that the
	# active review's metadata is identical either way.
	[ "$status" -ne 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "$before_mode" ]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "$before_step" ]
}

@test "rebuilding the draft mid-review does not move the cursor" {
	git review start feature/x
	git review next
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "2" ]
	run git review walkthrough draft --build feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "2" ]
}

# ── the presence record ───────────────────────────────────────────────────────

@test "status --porcelain emits a draft record while the draft is in force" {
	git review start feature/x
	run git review status --porcelain
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -Fxq 'draft'
}

@test "a review on the author's walkthrough emits no draft record" {
	# Same PR, but annotated by its author and with no draft of ours.
	rm "$DRAFT"
	git switch --quiet feature/x
	mkdir -p .review
	printf '# Walkthrough\n\n## 1. a.txt\nauthor prose\n\n## 2. src/c.txt\nmore\n' >.review/walkthrough.md
	git add -A
	git commit --quiet -m walkthrough
	git push --quiet origin feature/x
	git switch --quiet develop

	git review start feature/x
	run git review status --porcelain
	[ "$status" -eq 0 ]
	run bash -c "printf '%s\n' \"\$1\" | grep -Fx draft" _ "$output"
	[ "$status" -ne 0 ]
}

@test "deleting the draft mid-review names the real cause, not HEAD" {
	git review start feature/x
	rm "$DRAFT"
	run git review status
	# The sequence empties exactly as it does after a stray commit, so without a
	# dedicated diagnostic the reviewer is told HEAD moved and to git reset --soft.
	[ "$status" -ne 0 ]
	[[ "$output" == *"the walkthrough this review was reading is gone"* ]]
	[[ "$output" == *"git review walkthrough draft feature/x"* ]]
	[[ "$output" != *"git reset --soft"* ]]
}
