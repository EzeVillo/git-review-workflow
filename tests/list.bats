#!/usr/bin/env bats
#
# Tests for git review list, which shows every review/* branch in progress.

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

	printf 'a\n' >app.txt
	git add app.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop

	git switch --quiet -c feature/x
	printf 'a\nb\n' >app.txt
	git add app.txt
	git commit --quiet -m pr1
	git push --quiet -u origin feature/x

	git switch --quiet -c feature/y develop
	printf 'a\nc\n' >app.txt
	git add app.txt
	git commit --quiet -m pr1y
	git push --quiet -u origin feature/y

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

@test "review list reports no reviews when none exist" {
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"no reviews in progress"* ]]
}

@test "review list lists every review branch" {
	git review start feature/x
	# A whole review leaves a staged diff; clear it before starting another.
	git switch --quiet develop
	git reset --hard --quiet
	git review start feature/y --step
	git switch --quiet develop

	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"review/feature/x"* ]]
	[[ "$output" == *"whole"* ]]
	[[ "$output" == *"review/feature/y"* ]]
	[[ "$output" == *"step ["* ]]
}

@test "review list marks the current branch with an asterisk" {
	git review start feature/x
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"* review/feature/x"* ]]
}

@test "review list shows saved branches that lack metadata" {
	# An orphan saved branch (e.g. a review save that died before writing its
	# metadata) used to make review list print nothing at all: the "no reviews"
	# check sees a non-empty review-saved/* namespace, but describe() skipped the
	# branch for having no reviewsource.
	git branch review-saved/orphan develop
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"review-saved/orphan"* ]]
	[[ "$output" == *"(no metadata"* ]]
	# Recovery: forget --saved uses the source name (suffix), not the full ref.
	[[ "$output" == *"git review forget --saved orphan"* ]]
	[[ "$output" != *"no reviews in progress"* ]]
}

@test "review list still shows valid reviews alongside an orphan branch" {
	git review start feature/x
	git switch --quiet develop
	git branch review/orphan develop
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"review/feature/x"* ]]
	[[ "$output" == *"whole"* ]]
	[[ "$output" == *"review/orphan"* ]]
	[[ "$output" == *"(no metadata"* ]]
	# Active orphan: abort cannot run without reviewsource — point at branch -D.
	[[ "$output" == *"git branch -D review/orphan"* ]]
}

@test "review list rejects unexpected arguments" {
	run git review list bogus
	[ "$status" -ne 0 ]
	[[ "$output" == *"unexpected argument"* ]]
}

# ── list --porcelain (US6) ─────────────────────────────────────────────────────

@test "list --porcelain reports every branch with exact fields, including orphans and missing position" {
	git review start feature/x --step >/dev/null
	git switch --quiet develop
	git reset --hard --quiet
	git review start feature/y >/dev/null
	git switch --quiet develop
	git reset --hard --quiet

	git branch review/orphan develop
	git branch review-saved/gone develop

	# A branch with reviewsource but no persisted position/total: list --porcelain
	# must omit both fields, never emit "?" (contracts/list-porcelain.md).
	git branch review/partial develop
	git config branch.review/partial.reviewsource feature/x
	git config branch.review/partial.reviewmode step

	run git review list --porcelain
	[ "$status" -eq 0 ]

	x_line="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "branch" && $2 == "review/feature/x"')"
	[ "$x_line" = "$(printf 'branch\treview/feature/x\t0\t0\t0\tstep\t1\t1')" ]

	y_line="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "branch" && $2 == "review/feature/y"')"
	[ "$y_line" = "$(printf 'branch\treview/feature/y\t0\t0\t0\twhole')" ]

	orphan_line="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "branch" && $2 == "review/orphan"')"
	[ "$orphan_line" = "$(printf 'branch\treview/orphan\t0\t0\t1')" ]

	saved_line="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "branch" && $2 == "review-saved/gone"')"
	[ "$saved_line" = "$(printf 'branch\treview-saved/gone\t1\t0\t1')" ]

	partial_line="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "branch" && $2 == "review/partial"')"
	[ "$partial_line" = "$(printf 'branch\treview/partial\t0\t0\t0\tstep')" ]
	[[ "$partial_line" != *"?"* ]]
}

@test "list --porcelain reports zero lines and exit 0 with no reviews in the repository" {
	run git review list --porcelain
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# ── branch-draft: who carries a reading order of their own ────────────────────

# Install a valid reviewer's draft for <branch> without going through the
# skeleton: the shape of the file is not what these tests are about.
put_draft() {
	run git review walkthrough draft --build --from - "$1" <<'ORDER'
# Walkthrough

## 1. app.txt
mine, not the author's
ORDER
	[ "$status" -eq 0 ]
}

branch_drafts() {
	git review list --porcelain | awk -F'\t' '$1 == "branch-draft" { print $2 }'
}

@test "list --porcelain marks a review that carries a draft, right after its branch row" {
	put_draft feature/x
	git review start feature/x >/dev/null
	git switch --quiet develop

	run git review list --porcelain
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | awk -F'\t' '$1 == "branch-draft" { print $2 }')" = "review/feature/x" ]
	# Position is normative: porcelain-bytes.bats compares this output byte for
	# byte, so "somewhere in the output" would leave two equally correct
	# implementations producing two different suites.
	prev="$(printf '%s\n' "$output" | grep -n '^branch-draft' | cut -d: -f1)"
	[ -n "$prev" ]
	before="$(printf '%s\n' "$output" | sed -n "$((prev - 1))p" | cut -f1-2)"
	[ "$before" = "$(printf 'branch\treview/feature/x')" ]
}

@test "list --porcelain emits no branch-draft when nothing carries one" {
	before="$(git review list --porcelain)"
	git review start feature/x >/dev/null
	git switch --quiet develop
	run git review list --porcelain
	[ "$status" -eq 0 ]
	[ -z "$(printf '%s\n' "$output" | awk -F'\t' '$1 == "branch-draft"')" ]
	# The empty-inventory output is untouched too.
	git switch --quiet review/feature/x
	git review abort >/dev/null
	[ "$(git review list --porcelain)" = "$before" ]
}

@test "list --porcelain marks a draft in whole and in step, not only in walk" {
	# The draft travels with the review in every mode -- save files it, and
	# forget --saved discards it -- so a badge only on walk rows would hand a file
	# to forget --saved that no surface ever showed.
	put_draft feature/x
	git review start feature/x --no-walk >/dev/null
	git switch --quiet develop
	[ "$(branch_drafts)" = "review/feature/x" ]
	git switch --quiet review/feature/x
	git review abort >/dev/null

	git review start feature/x --step >/dev/null
	git switch --quiet develop
	[ "$(branch_drafts)" = "review/feature/x" ]
}

@test "a paused review that filed its draft keeps the mark, and one that filed none does not" {
	put_draft feature/x
	git review start feature/x >/dev/null
	run git review save
	[ "$status" -eq 0 ]
	[ "$(branch_drafts)" = "review-saved/feature/x" ]

	# A second paused review of the SAME branch, with no draft of its own: a
	# comparison names its review branch after the ref it was given, so the two
	# coexist, but the archived file is named after the branch and both would
	# claim it by name. Only the one that actually filed it may.
	run git review compare develop origin/feature/x
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/origin/feature/x.reviewdraft)" = "feature/x" ]
	run git review save
	[ "$status" -eq 0 ]

	run git review list --porcelain
	[ "$status" -eq 0 ]
	marked="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "branch-draft" { print $2 }')"
	[ "$marked" = "review-saved/feature/x" ]
}

@test "every (draft) row in the readable listing has its branch-draft record, and the reverse" {
	# One paused review carrying its filed draft, one active review carrying its
	# own: the two shapes the badge has to cover.
	put_draft feature/x
	git review start feature/x >/dev/null
	run git review save
	[ "$status" -eq 0 ]
	put_draft feature/y
	git review start feature/y >/dev/null

	readable="$(git review list | grep -c '(draft)')"
	porcelain="$(branch_drafts | grep -c .)"
	[ "$readable" = "2" ]
	[ "$readable" = "$porcelain" ]

	# And the reverse direction: discard one draft and both surfaces lose a row.
	run git review forget --draft feature/y
	[ "$status" -eq 0 ]
	[ "$(git review list | grep -c '(draft)')" = "1" ]
	[ "$(branch_drafts | grep -c .)" = "1" ]
	[ "$(branch_drafts)" = "review-saved/feature/x" ]
}

# -- review-fixes/*: the leftovers no surface used to name ---------------------

# fixes_rows: the porcelain fixes records, one per line.
fixes_rows() {
	git review list --porcelain | awk -F'\t' '$1 == "fixes" { print }'
}

@test "review list names the review-fixes branch a finish left behind" {
	git review start feature/x >/dev/null
	git review finish >/dev/null

	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"review-fixes/feature/x  fixes  (nothing committed on it)"* ]]
	[[ "$output" == *"git review clean --fixes-only <branch>"* ]]

	# current=1 (finish leaves you there) and session=1: clean <branch> would take
	# both branches, so the panel row needs to know it must pass --fixes-only.
	[ "$(fixes_rows)" = "$(printf 'fixes\treview-fixes/feature/x\t1\t1\tempty')" ]
}

@test "a fixes branch you committed on reports unmerged, and merged once the base has it" {
	git review start feature/x >/dev/null
	git review finish >/dev/null
	git switch --quiet review-fixes/feature/x
	printf 'my fix\n' >>app.txt
	git add app.txt
	git commit --quiet -m "my fix"
	git switch --quiet develop

	[ "$(fixes_rows | cut -f5)" = "unmerged" ]

	# Same branch, once the base contains it: nothing of yours is lost by
	# dropping it, and the row is allowed to say so.
	git merge --quiet --no-ff -m merge review-fixes/feature/x
	[ "$(fixes_rows | cut -f5)" = "merged" ]
}

@test "an untouched fixes branch reports empty even when the base does not have the PR" {
	git review start feature/x >/dev/null
	git review finish >/dev/null
	git switch --quiet develop

	# The tip is feature/x, which develop does not contain -- so the merged test
	# alone would call this unmerged and warn about losing work that is not there.
	run git merge-base --is-ancestor review-fixes/feature/x develop
	[ "$status" -ne 0 ]
	[ "$(fixes_rows | cut -f5)" = "empty" ]
}

@test "without a base configured the fixes state is unknown, not a guess" {
	git review start feature/x >/dev/null
	git review finish >/dev/null
	git switch --quiet review-fixes/feature/x
	printf 'my fix\n' >>app.txt
	git add app.txt
	git commit --quiet -m "my fix"
	git switch --quiet develop
	git config --unset reviewworkflow.base

	[ "$(fixes_rows | cut -f5)" = "unknown" ]
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"(no base set, cannot tell)"* ]]
}

@test "fixes branches are listed when no review is left to list" {
	git review start feature/x >/dev/null
	git review finish >/dev/null
	git switch --quiet develop
	git review clean --keep-fixes feature/x >/dev/null

	# Precondition: the two namespaces list() used to bail on are both empty.
	[ -z "$(git for-each-ref refs/heads/review/ refs/heads/review-saved/)" ]

	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" != *"no reviews in progress"* ]]
	[[ "$output" == *"review-fixes/feature/x"* ]]
	[ "$(fixes_rows)" = "$(printf 'fixes\treview-fixes/feature/x\t0\t0\tempty')" ]
}

@test "the fixes record marks the branch you are standing on" {
	git review start feature/x >/dev/null
	git review finish >/dev/null

	# finish leaves you on review-fixes/<branch>: the one row clean can never
	# delete, and the row a panel has to disable.
	[ "$(git symbolic-ref --short HEAD)" = "review-fixes/feature/x" ]
	[ "$(fixes_rows | cut -f3)" = "1" ]
}
