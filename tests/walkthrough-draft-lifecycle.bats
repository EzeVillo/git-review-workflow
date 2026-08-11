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

	# A second PR, so "does this touch the other review?" can be asked of a command
	# that succeeds rather than only of one that refuses.
	git switch --quiet develop
	git switch --quiet -c feature/y
	printf 'y1\n' >y.txt
	git add -A
	git commit --quiet -m other
	git push --quiet -u origin feature/y

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

# ── what the review records ───────────────────────────────────────────────────

@test "start records where the draft lives and that it opened on it" {
	git review start feature/x
	[ "$(git config branch.review/feature/x.reviewdraft)" = "feature/x" ]
	[ "$(git config branch.review/feature/x.reviewwalkfromdraft)" = "1" ]
	git review abort

	# Same PR with no draft: the name is recorded all the same — it is where a
	# draft written mid-review will go, and where every custody surface looks —
	# while the flag's absence keeps meaning "the author's order".
	rm "$DRAFT"
	git review start feature/x
	[ "$(git config branch.review/feature/x.reviewdraft)" = "feature/x" ]
	run git config branch.review/feature/x.reviewwalkfromdraft
	[ "$status" -ne 0 ]
}

@test "a whole review carrying the draft name still finishes" {
	# reviewdraft is recorded in every mode, walk included, so it must not read as
	# a walk key: finish's guard aborts on those outside walk mode, and a whole
	# review of a branch you had drafted for would have been unfinishable.
	rm "$DRAFT"
	git review start --no-walk feature/x
	[ "$(git config branch.review/feature/x.reviewdraft)" = "feature/x" ]
	printf 'edited\n' >>a.txt
	run git review finish
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -eq 0 ]
}

@test "finish refuses when the draft flag outlives its mode" {
	git review start feature/x
	# Hand-edited metadata, walk keys without walk mode. The other walk keys are
	# unset so this lands on the draft flag alone: it is a walk key like the rest
	# and has to be guarded like the rest, or finish would run on a review whose
	# recorded state is inconsistent.
	git config --unset branch.review/feature/x.reviewmode
	git config --unset branch.review/feature/x.reviewwalkstep
	git config --unset branch.review/feature/x.reviewwalkcount
	git config --unset branch.review/feature/x.reviewwalkbase
	[ "$(git config branch.review/feature/x.reviewwalkfromdraft)" = "1" ]
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"walkthrough keys but reviewmode is not 'walk'"* ]]
	run git rev-parse --verify --quiet refs/heads/review-fixes/feature/x
	[ "$status" -ne 0 ]
}

# ── save and continue ─────────────────────────────────────────────────────────

@test "save files the draft with the paused review" {
	git review start feature/x
	run git review save
	[ "$status" -eq 0 ]
	[ ! -f "$DRAFT" ]
	[ -f "$SAVED_DRAFT" ]
	grep -Fxq 'start here' "$SAVED_DRAFT"
}

@test "a save that cannot return anywhere leaves the draft alone" {
	git review start feature/x
	# Both answers to "where do I go back to" gone, so save refuses. It used to
	# move the draft first and find out after: the review stayed live with no
	# reading order at all, and the file sat in the saved namespace with no saved
	# review to claim it — clean cannot reach there and forget --saved refuses.
	git config --unset branch.review/feature/x.reviewreturn
	git config --unset branch.review/feature/x.reviewbase
	run git review save
	[ "$status" -eq 1 ]
	[[ "$output" == *"could not determine a branch to return to"* ]]
	[ -f "$DRAFT" ]
	[ ! -f "$SAVED_DRAFT" ]
	# Nothing was put aside: the review is still here, still on the draft.
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git rev-parse --verify --quiet refs/heads/review-saved/feature/x
	[ "$status" -ne 0 ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk (draft)"* ]]
	[[ "$output" == *"on src/c.txt"* ]]
}

@test "a continue that cannot restore leaves the draft with the saved review" {
	git review start feature/x
	git review save
	# Half-deleted metadata, so continue refuses. It used to bring the draft back
	# first, which left it in the active namespace beside a review that was still
	# paused — and the next clean deleted it as a leftover.
	git config --unset branch.review-saved/feature/x.reviewtip
	run git review continue feature/x
	[ "$status" -eq 1 ]
	[[ "$output" == *"missing review metadata"* ]]
	[ ! -f "$DRAFT" ]
	[ -f "$SAVED_DRAFT" ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
	# Still the paused review's, so the one verb that owns it can still take it.
	run git review forget --saved feature/x
	[ "$status" -eq 0 ]
	[ ! -f "$SAVED_DRAFT" ]
}

@test "forget --draft --all leaves the archived draft of a paused compare" {
	# The archived file is named after the branch (feature/x) and the paused review
	# after the ref it was compared with (review-saved/origin/feature/x). Testing
	# refs/heads/review-saved/<file name> therefore answered "no paused review" for
	# exactly this shape: the sweep deleted a live paused review's reading order,
	# announced that nothing was left to restore it, and the next continue came back
	# to "the walkthrough this review was reading is gone" with abort as the only
	# way out.
	git review compare develop origin/feature/x >/dev/null
	[ "$(git config branch.review/origin/feature/x.reviewdraft)" = "feature/x" ]
	git review save >/dev/null
	[ -f "$SAVED_DRAFT" ]

	run git review forget --draft --all --dry-run
	[ "$status" -eq 0 ]
	[ "$output" = "no walkthrough drafts" ]
	run git review forget --draft --all
	[ "$status" -eq 0 ]
	[ "$output" = "no walkthrough drafts" ]
	[ -f "$SAVED_DRAFT" ]

	# Still resumable, still on the reviewer's own order.
	run git review continue origin/feature/x
	[ "$status" -eq 0 ]
	[ -f "$DRAFT" ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk (draft)"* ]]
	[[ "$output" == *"on src/c.txt"* ]]
}

@test "forget --draft --all still takes a compares archived draft once its review is gone" {
	# The other side of the same test: the claim is what protects the file, so
	# deleting the claimant by hand must hand it back to the sweep -- under the
	# name it is filed as, which is not the review's.
	git review compare develop origin/feature/x >/dev/null
	git review save >/dev/null
	git branch -D review-saved/origin/feature/x >/dev/null
	run git review forget --draft --all
	[ "$status" -eq 0 ]
	[[ "$output" == *"forgot the archived walkthrough draft for feature/x"* ]]
	[ ! -f "$SAVED_DRAFT" ]
}

@test "save refuses to file a draft over one a paused review still claims" {
	# Two reviews of one branch can want the same file name: a draft belongs to the
	# branch, so the compare of origin/feature/x and the start of feature/x both
	# file under feature/x. The move at the end of save is an mv, and it replaced
	# the paused review's prose without a word.
	git review compare develop origin/feature/x >/dev/null
	git review save >/dev/null
	[ -f "$SAVED_DRAFT" ]
	archived="$(cat "$SAVED_DRAFT")"

	# A second draft for the same branch, and a second review reading it.
	printf '# Walkthrough\n\n## 1. a.txt\nthe second draft\n' >"$DRAFT"
	git review start feature/x >/dev/null
	run git review save
	[ "$status" -eq 1 ]
	[[ "$output" == *"review-saved/origin/feature/x is paused on a walkthrough draft for feature/x"* ]]
	[[ "$output" == *"git review forget --saved origin/feature/x"* ]]

	# Neither copy moved, and the review that could not be saved is still live.
	[ "$(cat "$SAVED_DRAFT")" = "$archived" ]
	[ "$(tail -n 1 "$DRAFT")" = "the second draft" ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/feature/x" ]
	run git rev-parse --verify --quiet refs/heads/review-saved/feature/x
	[ "$status" -ne 0 ]
}

@test "save of a review with no draft is not blocked by someone elses archive" {
	# The guard protects an mv, and with no draft of its own this review makes no
	# mv: nothing of the paused review's is at risk. Refusing anyway locked the
	# branch out of being paused at all, over prose that would not have been
	# touched -- and the archive is normally there for exactly this reason, because
	# the earlier review of the same branch was saved with its draft.
	git review compare develop origin/feature/x >/dev/null
	git review save >/dev/null
	[ -f "$SAVED_DRAFT" ]
	archived="$(cat "$SAVED_DRAFT")"

	git review start feature/x >/dev/null
	[ ! -f "$DRAFT" ]
	run git review save
	[ "$status" -eq 0 ]
	[[ "$output" != *"replaced an archived walkthrough draft"* ]]
	run git rev-parse --verify --quiet refs/heads/review-saved/feature/x
	[ "$status" -eq 0 ]
	# The other review's prose is exactly where it was, and still comes back to it.
	[ "$(cat "$SAVED_DRAFT")" = "$archived" ]
	run git review continue origin/feature/x
	[ "$status" -eq 0 ]
	[ "$(cat "$DRAFT")" = "$archived" ]
}

@test "an archived draft goes back only to the review that filed it" {
	# Two paused reviews of one branch share the name of the archived file, and save
	# only refuses the collision when it has a file of its own to move -- so pausing
	# a draftless review first and a drafted one after leaves both sitting over one
	# file that only the second wrote. Every reader used to answer "mine" for both.
	rm -f "$DRAFT"
	git review start feature/x >/dev/null
	git review save >/dev/null
	[ "$(git config branch.review-saved/feature/x.reviewdraftfiled)" = "0" ]
	[ ! -f "$SAVED_DRAFT" ]

	printf '# Walkthrough\n\n## 1. a.txt\nthe compares own order\n' >"$DRAFT"
	git review compare develop origin/feature/x >/dev/null
	git review save >/dev/null
	[ "$(git config branch.review-saved/origin/feature/x.reviewdraftfiled)" = "1" ]
	[ -f "$SAVED_DRAFT" ]
	archived="$(cat "$SAVED_DRAFT")"

	# The row that filed nothing must not promise a reading order it cannot bring.
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"review-saved/origin/feature/x"* ]]
	[[ "$output" != *"review-saved/feature/x  whole (draft)"* ]]

	# Resuming it walks off with nothing.
	run git review continue feature/x
	[ "$status" -eq 0 ]
	[ ! -f "$DRAFT" ]
	[ "$(cat "$SAVED_DRAFT")" = "$archived" ]

	# And the review that wrote it still gets it back, unchanged.
	git review abort >/dev/null
	run git review continue origin/feature/x
	[ "$status" -eq 0 ]
	[ "$(cat "$DRAFT")" = "$archived" ]
	[ ! -f "$SAVED_DRAFT" ]
}

@test "forget --saved leaves an archived draft it did not file" {
	# The same shape, on the one command that destroys a draft on purpose: it says
	# so out loud, and it used to say it while deleting prose the review it was
	# discarding had never written.
	rm -f "$DRAFT"
	git review start feature/x >/dev/null
	git review save >/dev/null

	printf '# Walkthrough\n\n## 1. a.txt\nthe compares own order\n' >"$DRAFT"
	git review compare develop origin/feature/x >/dev/null
	git review save >/dev/null
	archived="$(cat "$SAVED_DRAFT")"

	run git review forget --saved feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"discarded saved review of feature/x"* ]]
	[[ "$output" != *"walkthrough draft"* ]]
	[ "$(cat "$SAVED_DRAFT")" = "$archived" ]

	# Its real owner still has it, and discarding that one does take it.
	run git review forget --saved origin/feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"its walkthrough draft for feature/x went with it"* ]]
	[ ! -f "$SAVED_DRAFT" ]
}

@test "save can replace an archived draft the only paused review never filed" {
	# The claim is what protects the file, and a review that filed nothing does not
	# claim it -- otherwise the sweep and the guard would both defer to a review
	# that is never going to restore it.
	rm -f "$DRAFT"
	git review start feature/x >/dev/null
	git review save >/dev/null
	mkdir -p "$(dirname "$SAVED_DRAFT")"
	printf '# Walkthrough\n\n## 1. a.txt\nleft over\n' >"$SAVED_DRAFT"

	printf '# Walkthrough\n\n## 1. a.txt\nthe compares own order\n' >"$DRAFT"
	git review compare develop origin/feature/x >/dev/null
	run git review save
	[ "$status" -eq 0 ]
	[[ "$output" == *"replaced an archived walkthrough draft for feature/x"* ]]
	[ "$(tail -n 1 "$SAVED_DRAFT")" = "the compares own order" ]
}

@test "save replaces an archived draft nobody claims and says so" {
	# Same collision with the claimant deleted by hand: nothing can bring that file
	# back, so saving proceeds -- but it is still prose someone typed, and this is
	# the only mv in the suite that lands on top of some.
	git review compare develop origin/feature/x >/dev/null
	git review save >/dev/null
	git branch -D review-saved/origin/feature/x >/dev/null
	[ -f "$SAVED_DRAFT" ]

	printf '# Walkthrough\n\n## 1. a.txt\nthe second draft\n' >"$DRAFT"
	git review start feature/x >/dev/null
	run git review save
	[ "$status" -eq 0 ]
	[[ "$output" == *"replaced an archived walkthrough draft for feature/x"* ]]
	[ ! -f "$DRAFT" ]
	[ "$(tail -n 1 "$SAVED_DRAFT")" = "the second draft" ]
}

# ── clean ─────────────────────────────────────────────────────────────────────
#
# A draft is hand-written prose that outlives the review it was written for, so
# clean leaves it alone in both namespaces — the rule it already follows for the
# --delta markers and for a paused review. git review forget --draft is what
# throws one away.

@test "clean does not delete a draft written before the review exists" {
	# The documented flow writes the draft first: draft, fill it in, --build,
	# start. A clean in that window used to destroy the file without a word,
	# because no review/<branch> existed yet for it to belong to.
	run git review clean
	[ "$status" -eq 0 ]
	[ -f "$DRAFT" ]
	grep -Fxq 'start here' "$DRAFT"
	# And it is still the order the review starts in.
	run git review start feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/2] src/c.txt"* ]]
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

@test "clean takes the review branch and leaves the draft" {
	git review start feature/x
	git switch --quiet develop
	run git review clean
	[ "$status" -eq 0 ]
	run git rev-parse --verify --quiet refs/heads/review/feature/x
	[ "$status" -ne 0 ]
	[ -f "$DRAFT" ]
}

@test "a draft outlives abort and clean, and the next start reads it again" {
	git review start feature/x
	git review next
	git review abort
	run git review clean
	[ "$status" -eq 0 ]
	[ -f "$DRAFT" ]
	# What keeping it buys: re-reviewing the branch costs no re-typing. The
	# cursor is a property of the review, so it starts at 1 again — the order,
	# which is what was written by hand, is what survives.
	run git review start feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/2] src/c.txt"* ]]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk (draft)"* ]]
}

@test "clean never touches a paused review's draft either" {
	git review start feature/x
	git review save
	run git review clean
	[ "$status" -eq 0 ]
	[ -f "$SAVED_DRAFT" ]
	[ ! -f "$DRAFT" ]
}

# ── forget --draft ────────────────────────────────────────────────────────────

@test "forget --draft deletes the draft it names" {
	run git review forget --draft feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"forgot the walkthrough draft for feature/x"* ]]
	[ ! -f "$DRAFT" ]
	# Back to what the PR itself offers, which here is nothing: a whole review.
	run git review start feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"the staged diff is the PR"* ]]
	[ -z "$(git config branch.review/feature/x.reviewmode || true)" ]
}

@test "forget --draft on a branch with no draft says so and deletes nothing" {
	run git review forget --draft feature/nope
	[ "$status" -eq 0 ]
	[[ "$output" == *"no walkthrough draft for feature/nope"* ]]
	[ -f "$DRAFT" ]
}

@test "forget --draft --dry-run reports without deleting" {
	run git review forget --draft --dry-run feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"would forget the walkthrough draft for feature/x"* ]]
	[ -f "$DRAFT" ]
	grep -Fxq 'start here' "$DRAFT"
}

@test "forget --draft --all takes every draft, namespaced ones included" {
	# A draft two levels deep: this is where a branch name with slashes lands, and
	# a one-level glob would miss it entirely.
	other="$GITDIR/review-walkthrough/team/a/b.md"
	mkdir -p "$(dirname "$other")"
	printf '# Walkthrough\n\n## 1. a.txt\nx\n' >"$other"
	run git review forget --draft --all
	[ "$status" -eq 0 ]
	[[ "$output" == *"forgot the walkthrough draft for feature/x"* ]]
	[[ "$output" == *"forgot the walkthrough draft for team/a/b"* ]]
	[ ! -f "$DRAFT" ]
	[ ! -f "$other" ]
}

@test "forget --draft --all with no drafts says so" {
	rm "$DRAFT"
	run git review forget --draft --all
	[ "$status" -eq 0 ]
	[[ "$output" == *"no walkthrough drafts"* ]]
}

@test "forget --draft says nothing about a step review of the same branch" {
	# The note is about what a review will read next, and a step review reads no
	# walkthrough at all. It records the draft's name like every other mode does —
	# custody is mode-blind — so without the walk filter it would be caught here
	# and promised a fallback that never happens.
	git review start --step feature/x
	run git review forget --draft feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"forgot the walkthrough draft for feature/x"* ]]
	[[ "$output" != *"was reading it"* ]]
	[ ! -f "$DRAFT" ]
	# The review is still there, still stepping.
	[ "$(git config branch.review/feature/x.reviewmode)" = "step" ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"step"* ]]
}

@test "forget --draft --all leaves an archived draft its paused review can restore" {
	git review start feature/x
	git review save
	[ -f "$SAVED_DRAFT" ]
	run git review forget --draft --all
	[ "$status" -eq 0 ]
	# The active namespace is empty and the archive has an owner, so there is
	# nothing to take -- and saying so is the point: the sweep must not be able to
	# report having forgotten prose that is still coming back.
	[[ "$output" == *"no walkthrough drafts"* ]]
	[ -f "$SAVED_DRAFT" ]
	run git review continue feature/x
	[ "$status" -eq 0 ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk (draft)"* ]]
}

@test "forget --draft --all takes an archived draft whose paused review is gone" {
	git review start feature/x
	git review save
	[ -f "$SAVED_DRAFT" ]
	# The owner deleted by hand. Every command that could reach the file went
	# through that branch, so from here it answered to nothing at all.
	git branch -D review-saved/feature/x >/dev/null
	run git review forget --saved feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"no saved review for feature/x"* ]]
	[ -f "$SAVED_DRAFT" ]

	run git review forget --draft --all --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"would forget the archived walkthrough draft for feature/x"* ]]
	[ -f "$SAVED_DRAFT" ]

	run git review forget --draft --all
	[ "$status" -eq 0 ]
	[[ "$output" == *"forgot the archived walkthrough draft for feature/x"* ]]
	[ ! -f "$SAVED_DRAFT" ]
}

@test "forget --draft leaves a paused review's draft to forget --saved" {
	git review start feature/x
	git review save
	run git review forget --draft feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"no walkthrough draft for feature/x"* ]]
	[ -f "$SAVED_DRAFT" ]
	# Untouched means resumable: the paused review still comes back on it.
	run git review continue feature/x
	[ "$status" -eq 0 ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk (draft)"* ]]
	[[ "$output" == *"on src/c.txt"* ]]
}

@test "forget --draft under a live review says what it changed" {
	git review start feature/x
	run git review forget --draft feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"forgot the walkthrough draft for feature/x"* ]]
	[[ "$output" == *"review/feature/x was reading it"* ]]
	[ ! -f "$DRAFT" ]
}

@test "forget --draft names the compare review that was reading it" {
	# The review is review/origin/feature/x and the draft is feature/x's: the note
	# has to come from what the review recorded, not from its own name.
	git review compare develop origin/feature/x
	[ "$(git config branch.review/origin/feature/x.reviewdraft)" = "feature/x" ]
	git switch --quiet develop

	run git review forget --draft feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"forgot the walkthrough draft for feature/x"* ]]
	[[ "$output" == *"review/origin/feature/x was reading it"* ]]
	[ ! -f "$DRAFT" ]
}

@test "forget --draft rejects a name that is not a branch, and deletes nothing" {
	# The draft's file name is its branch name, so an unchecked argument addressed
	# any file on the disk: .git/review-walkthrough/../../victim.md is this one,
	# sitting in the work tree.
	victim="$WORK/victim.md"
	printf 'not a draft\n' >"$victim"
	run git review forget --draft '../../victim'
	[ "$status" -ne 0 ]
	[[ "$output" == *"not a valid branch name: ../../victim"* ]]
	[ -f "$victim" ]
	[ "$(cat "$victim")" = "not a draft" ]
	# And it did not report success for a deletion it never made.
	[[ "$output" != *"forgot the walkthrough draft"* ]]
	[ -f "$DRAFT" ]
}

@test "forget --draft without a target prints usage and deletes nothing" {
	run git review forget --draft
	[ "$status" -eq 1 ]
	[[ "$output" == *"usage: git review forget"* ]]
	[ -f "$DRAFT" ]
}

@test "forget --draft rejects a branch together with --all" {
	run git review forget --draft --all feature/x
	[ "$status" -eq 1 ]
	[[ "$output" == *"use either <branch> or --all, not both"* ]]
	[ -f "$DRAFT" ]
}

@test "forget --draft rejects --stale" {
	run git review forget --draft --stale
	[ "$status" -eq 1 ]
	[[ "$output" == *"--stale only applies to --delta"* ]]
	[ -f "$DRAFT" ]
}

@test "continue brings the draft back and resumes in the same order" {
	git review start feature/x
	git review next
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/2]"* ]]
	git review save

	run git review continue feature/x
	[ "$status" -eq 0 ]
	[ -f "$DRAFT" ]
	[ ! -f "$SAVED_DRAFT" ]
	# Both records travel with the review, both ways: where the draft lives, and
	# that this review's order came out of it.
	[ "$(git config branch.review/feature/x.reviewdraft)" = "feature/x" ]
	[ "$(git config branch.review/feature/x.reviewwalkfromdraft)" = "1" ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk (draft)"* ]]
	[[ "$output" == *"[2/2]"* ]]
	[[ "$output" == *"on a.txt"* ]]
}

@test "continue refuses rather than overwrite a draft written while paused" {
	git review start feature/x
	git review save
	[ ! -f "$DRAFT" ]

	# The reviewer writes a new one for the same branch while the review sleeps.
	# Nothing so far has had reason to mention the archived copy.
	cat >"$DRAFT" <<'EOF'
# Walkthrough

## 1. a.txt
written while the review was paused
EOF

	run git review continue feature/x
	[ "$status" -ne 0 ]
	[[ "$output" == *"already exists"* ]]
	[[ "$output" == *"git review forget --draft feature/x"* ]]
	# Both files still there, both untouched, and the review still paused: the
	# refusal happens before anything moves.
	[ "$(tail -n 1 "$DRAFT")" = "written while the review was paused" ]
	[ -f "$SAVED_DRAFT" ]
	git rev-parse --verify --quiet refs/heads/review-saved/feature/x >/dev/null
	! git rev-parse --verify --quiet refs/heads/review/feature/x >/dev/null
}

@test "dropping the new draft lets continue resume on the archived one" {
	git review start feature/x
	git review next
	git review save
	printf '# Walkthrough\n\n## 1. a.txt\nmine\n' >"$DRAFT"

	run git review forget --draft feature/x
	[ "$status" -eq 0 ]
	run git review continue feature/x
	[ "$status" -eq 0 ]
	[ ! -f "$SAVED_DRAFT" ]
	# The archived draft is what came back: its order puts src/c.txt first, so the
	# cursor saved at 2 lands on a.txt.
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk (draft)"* ]]
	[[ "$output" == *"[2/2] on a.txt"* ]]
}

@test "drafting for a branch with a paused review says one is already filed" {
	git review start feature/x
	git review save
	run git review walkthrough draft feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"a paused review of feature/x carries a walkthrough draft of its own"* ]]
	[ -f "$DRAFT" ]
	[ -f "$SAVED_DRAFT" ]
}

@test "drafting over a leftover archive says nobody can bring it back" {
	# Same collision with the claimant deleted by hand. Deciding by the file's name
	# announced a paused review that does not exist and pointed at a git review
	# continue that cannot be run -- and the thing that actually happens next is the
	# opposite of what it says: the next save replaces the leftover rather than
	# refusing over it.
	git review start feature/x
	git review save
	git branch -D review-saved/feature/x >/dev/null
	[ -f "$SAVED_DRAFT" ]

	run git review walkthrough draft feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"left over from a review that no longer exists"* ]]
	[[ "$output" != *"a paused review of feature/x carries"* ]]
	[ -f "$DRAFT" ]
	[ -f "$SAVED_DRAFT" ]
}

@test "list marks a paused step review's row as carrying a draft" {
	# A draft belongs to a branch, not to a mode: a step or whole review of a
	# branch you had drafted for takes that draft into the saved namespace when it
	# pauses, and forget --saved would then discard it. Marking only walk rows left
	# that prose invisible on the one surface a reviewer reads days later.
	git review start --step feature/x
	git review save
	[ ! -f "$DRAFT" ]
	[ -f "$SAVED_DRAFT" ]

	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"review-saved/feature/x"* ]]
	[[ "$output" == *"step (draft) ["* ]]

	rm "$SAVED_DRAFT"
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" != *"(draft)"* ]]
}

@test "list marks a paused review's row as reading a draft" {
	git review start feature/x
	git review next
	git review save
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"review-saved/feature/x"* ]]
	[[ "$output" == *"walk (draft) [2/2]"* ]]
	# The badge is read from the saved namespace, where the draft now is — the
	# active path holds nothing for this branch.
	[ ! -f "$DRAFT" ]
	[ -f "$SAVED_DRAFT" ]
	# And it is a real test of the file, not a label the row always carries.
	rm "$SAVED_DRAFT"
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk [2/2]"* ]]
	[[ "$output" != *"(draft)"* ]]
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
	# And it says so. Every other verb goes out of its way to keep hand-written
	# prose — clean will not touch a draft — so the one command that destroys one
	# has to name it rather than leave it to the docs.
	[[ "$output" == *"its walkthrough draft for feature/x went with it"* ]]
}

@test "forget --saved says nothing about a draft when the review carried none" {
	rm "$DRAFT"
	git review start feature/x
	git review save
	run git review forget --saved feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"discarded saved review of feature/x"* ]]
	[[ "$output" != *"went with it"* ]]
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
	# And the branch tracks the PR's files and nothing else. Asserted as the whole
	# tree rather than as "no path contains review-walkthrough": the draft lives
	# inside the gitdir, where git cannot track a file whatever finish does, so that
	# spelling of the check could not fail if the extraction went wrong.
	run git ls-tree -r --name-only HEAD
	[ "$status" -eq 0 ]
	[ "$output" = "a.txt
src/c.txt" ]
	# The draft itself is untouched on disk: not extracted, not moved, not deleted.
	[ -f "$DRAFT" ]
	[ "$(head -n 1 "$DRAFT")" = "# Walkthrough" ]
}

@test "finish leaves the draft in place for a later re-review" {
	git review start feature/x
	printf 'hello\nreviewer edit\n' >src/c.txt
	git review finish
	[ -f "$DRAFT" ]
}

# ── no effect on an active review ─────────────────────────────────────────────

@test "a command that fails to draft leaves an active review alone" {
	git review start feature/x
	before_mode="$(git config branch.review/feature/x.reviewmode)"
	before_step="$(git config branch.review/feature/x.reviewwalkstep)"

	run git review walkthrough draft --offline develop
	# develop has no changes vs itself, so this refuses — the point is that the
	# active review's metadata is identical either way.
	[ "$status" -ne 0 ]
	[[ "$output" == *"no changes vs develop"* ]]
	[ "$(git config branch.review/feature/x.reviewmode)" = "$before_mode" ]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "$before_step" ]
}

@test "drafting for another branch does not disturb an active review" {
	git review start feature/x
	git review next
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "2" ]

	# A draft that actually gets written, for a different branch, from inside a
	# live review — the case the failing command above cannot stand in for.
	run git review walkthrough draft feature/y
	[ "$status" -eq 0 ]
	[ -f "$GITDIR/review-walkthrough/feature/y.md" ]

	# The review still reads its own draft, at its own position.
	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "2" ]
	[ "$(git config branch.review/feature/x.reviewdraft)" = "feature/x" ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/2] on a.txt"* ]]
}

@test "rebuilding the draft mid-review does not move the cursor" {
	# Numbered 2 then 1, so --build has something to do: it sorts by those numbers
	# and renumbers 1..N, rewriting the file. The reading order itself is derived
	# from the numbers too (walk_sequence), so a rebuild normalises the file
	# without ever changing which entry is entry 2 — which is the invariant worth
	# pinning, and what the fixture's already-ordered draft could not have shown.
	cat >"$DRAFT" <<'EOF'
# Walkthrough

## 2. a.txt
second

## 1. src/c.txt
first
EOF
	git review start feature/x
	git review next
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "2" ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/2] on a.txt"* ]]

	run git review walkthrough draft --build feature/x
	[ "$status" -eq 0 ]
	# The file really was rewritten: the entry numbered 2 is now the one that used
	# to be numbered 1.
	[ "$(grep -c '^## 1\. src/c\.txt$' "$DRAFT")" = "1" ]
	[ "$(grep -c '^## 2\. a\.txt$' "$DRAFT")" = "1" ]

	[ "$(git config branch.review/feature/x.reviewmode)" = "walk" ]
	[ "$(git config branch.review/feature/x.reviewwalkstep)" = "2" ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/2] on a.txt"* ]]
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
