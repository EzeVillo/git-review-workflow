#!/usr/bin/env bats
#
# The state field of the draft records, and the sweep it makes possible:
# git review forget --draft --reviewed.
#
# A reading order the reviewer wrote outlives the review it was written for --
# clean is deliberately hands-off with it, and that is the promise -- but once
# the review is over it is no longer work in progress, and the panel drew it in
# the same block as a half-written one either way. The state says which is
# which; the sweep is the way to throw away the ones you cannot name, since a
# draft is spelled by its branch and after a handful of reviews nobody remembers
# which branches still hold prose.

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

	git switch --quiet -c feature/checkout
	printf 'a1\na2\n' >a.txt
	git add -A
	git commit --quiet -m checkout
	git push --quiet -u origin feature/checkout

	git switch --quiet develop
	git switch --quiet -c telemetry
	printf 't\n' >t.txt
	git add -A
	git commit --quiet -m telemetry
	git push --quiet -u origin telemetry

	git switch --quiet develop
	GITDIR="$(git rev-parse --git-dir)"
	NS="$GITDIR/review-walkthrough"
}

teardown() {
	rm -rf "$TMP"
}

state_of() {
	git review config --porcelain |
		awk -F'\t' -v want="$1" '$1 == "draft" && $2 == want { print $8; exit }'
}

# Turn the skeleton for <branch> into a reading order --build takes: every
# placeholder why replaced by prose, every "## ?." numbered, and the heads-up
# comment replaced by a line of text. The instruction block is left alone, which
# is what keeps the tip (and so the state) readable afterwards.
fill_draft() {
	_fd_file="$NS/$1.md"
	_fd_branch="$1"
	shift
	awk '
		/^<!-- heads-up/ {
			print "Read the range before opening a file."
			if (index($0, "-->") == 0) hu = 1
			next
		}
		hu { if (index($0, "-->")) hu = 0; next }
		/^## \?\. / {
			n++
			sub(/^## \?\. /, "## " n ". ")
			print
			next
		}
		/^<!-- why/ {
			print "REVIEWER: this is why the file matters."
			if (index($0, "-->") == 0) why = 1
			next
		}
		why { if (index($0, "-->")) why = 0; next }
		{ print }
	' "$_fd_file" >"$TMP/filled"
	mv "$TMP/filled" "$_fd_file"
	git review walkthrough draft --build "$@" "$_fd_branch" >/dev/null
}

# Run a whole review of <branch> through to a completed finish and clean it up.
# What is left behind is the state a reviewer is in the morning after: no
# review, no review branch, and the reading order still on disk.
review_and_finish() {
	fill_draft "$1"
	git review start "$1" >/dev/null
	printf 'edited by the reviewer\n' >>a.txt
	git review finish >/dev/null
	# finish leaves the extracted edits staged on review-fixes/<branch>; commit
	# them so the switch below is not refused, which is the ordinary flow.
	git commit --quiet -m fixes
	git review clean --keep-fixes >/dev/null
	git switch --quiet develop
}

# ── the state field ───────────────────────────────────────────────────────────

@test "a draft for a branch nobody has reviewed reports fresh" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]

	[ "$(state_of feature/checkout)" = "fresh" ]
}

@test "after a completed review and a clean the draft reports reviewed" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]
	[ "$(state_of feature/checkout)" = "fresh" ]

	review_and_finish feature/checkout

	# The file is still there -- clean does not touch prose, and that has not
	# changed -- but it is no longer a reading order with a review ahead of it.
	[ -f "$NS/feature/checkout.md" ]
	[ "$(state_of feature/checkout)" = "reviewed" ]
}

@test "a draft regenerated after the review reports fresh again" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]
	review_and_finish feature/checkout
	[ "$(state_of feature/checkout)" = "reviewed" ]

	# The PR moves and the reading order is written again over the new range.
	git switch --quiet feature/checkout
	printf 'a3\n' >>a.txt
	git add -A
	git commit --quiet -m more
	git push --quiet origin feature/checkout
	git switch --quiet develop
	run git review walkthrough draft --force feature/checkout
	[ "$status" -eq 0 ]

	# What the marker records is the tip the review that closed covered, and
	# this draft covers a later one: nobody has read it.
	[ "$(state_of feature/checkout)" = "fresh" ]
}

@test "a reading order that is not written through is never reviewed" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]
	review_and_finish feature/checkout
	[ "$(state_of feature/checkout)" = "reviewed" ]

	# Start over, with the branch exactly where the review left it: the new
	# skeleton lands on the very tip the marker records, so the tip comparison
	# cannot tell it apart from the order that was read. What tells them apart is
	# the pair -- and it has to, because a spent row is drawn without the two
	# controls that fill a draft in and start it, so a blank one folded away
	# there would have no way forward at all.
	run git review walkthrough draft --force feature/checkout
	[ "$status" -eq 0 ]
	[ "$(state_of feature/checkout)" = "fresh" ]

	# And it goes back to reviewed once it is written through again.
	fill_draft feature/checkout
	[ "$(state_of feature/checkout)" = "reviewed" ]
}

@test "an empty draft is fresh, not complete" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]
	review_and_finish feature/checkout
	[ "$(state_of feature/checkout)" = "reviewed" ]

	# 0 of 0 is "this file declares no entry", never "complete".
	: >"$NS/feature/checkout.md"
	[ "$(state_of feature/checkout)" = "fresh" ]
}

@test "a marker of the other flavour does not mark a draft as reviewed" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]

	# A --local review of the same branch records its marker in its own config
	# section. Crossing the two would report this remote draft as read because
	# the local copy of the branch was.
	git config "reviewworkflowlocal.feature/checkout.reviewed" "$(git rev-parse origin/feature/checkout)"

	[ "$(state_of feature/checkout)" = "fresh" ]
	[ "$(git config "reviewworkflowlocal.feature/checkout.reviewed")" = "$(git rev-parse origin/feature/checkout)" ]
}

@test "a local draft is answered by the local marker" {
	run git review walkthrough draft --local feature/checkout
	[ "$status" -eq 0 ]
	[ "$(state_of feature/checkout)" = "fresh" ]
	fill_draft feature/checkout --local

	git config "reviewworkflowlocal.feature/checkout.reviewed" "$(git rev-parse feature/checkout)"
	[ "$(state_of feature/checkout)" = "reviewed" ]
}

@test "a draft whose instruction block was deleted by hand reports fresh" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]
	fill_draft feature/checkout
	git config "reviewworkflow.feature/checkout.reviewed" "$(git rev-parse origin/feature/checkout)"
	[ "$(state_of feature/checkout)" = "reviewed" ]

	# Deleting the block is legal, and it takes the tip with it. Nothing can be
	# proved about the draft then, and fresh is the state that offers more.
	awk '
		index($0, "<!-- git-review-range:") == 1 { skip = 1; next }
		skip { if (index($0, "-->")) skip = 0; next }
		{ print }
	' "$NS/feature/checkout.md" >"$TMP/stripped"
	mv "$TMP/stripped" "$NS/feature/checkout.md"

	[ "$(state_of feature/checkout)" = "fresh" ]
}

@test "an aborted review leaves the draft fresh" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]
	git review start feature/checkout >/dev/null
	# start writes the marker up front; abort rolls it back, which is exactly
	# what makes the marker mean "a review that COMPLETED".
	git review abort >/dev/null
	git switch --quiet develop

	[ "$(state_of feature/checkout)" = "fresh" ]
}

# ── the sweep ─────────────────────────────────────────────────────────────────

@test "forget --draft --reviewed deletes the spent drafts and keeps the rest" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]
	run git review walkthrough draft telemetry
	[ "$status" -eq 0 ]
	review_and_finish feature/checkout

	run git review forget --draft --reviewed
	[ "$status" -eq 0 ]
	[[ "$output" == *"forgot the walkthrough draft for feature/checkout"* ]]
	[[ "$output" != *telemetry* ]]

	[ ! -f "$NS/feature/checkout.md" ]
	[ -f "$NS/telemetry.md" ]
	[ "$(state_of telemetry)" = "fresh" ]
}

@test "forget --draft --reviewed --dry-run deletes nothing" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]
	review_and_finish feature/checkout

	run git review forget --draft --reviewed --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"would forget the walkthrough draft for feature/checkout"* ]]
	[[ "$output" != *"forgot the walkthrough"* ]]

	[ -f "$NS/feature/checkout.md" ]
	[ "$(state_of feature/checkout)" = "reviewed" ]
}

@test "forget --draft --reviewed says so when nothing is spent" {
	run git review walkthrough draft telemetry
	[ "$status" -eq 0 ]

	run git review forget --draft --reviewed
	[ "$status" -eq 0 ]
	[ "$output" = "no walkthrough drafts whose review is over" ]
	[ -f "$NS/telemetry.md" ]
}

@test "forget --draft --reviewed on a repository with no drafts at all is a no-op" {
	run git review forget --draft --reviewed
	[ "$status" -eq 0 ]
	[ "$output" = "no walkthrough drafts whose review is over" ]
}

@test "forget --draft --reviewed skips a draft a live review is reading" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]
	# A reading order start can actually walk: only then is the review reading
	# the draft, which is what there is to protect.
	fill_draft feature/checkout
	# start records the marker before the review runs, so this draft answers
	# "reviewed" while the review reading it is still open. Naming it would
	# delete it; a sweep must not.
	git review start feature/checkout >/dev/null
	[ "$(git config "branch.review/feature/checkout.reviewmode")" = "walk" ]
	[ "$(state_of feature/checkout)" = "reviewed" ]

	run git review forget --draft --reviewed
	[ "$status" -eq 0 ]
	[[ "$output" != *"forgot the walkthrough draft"* ]]
	[[ "$output" == *"skipping feature/checkout"* ]]
	[ -f "$NS/feature/checkout.md" ]

	# And the message it did not print is the "nothing matched" one, which
	# would contradict the line it did print.
	[[ "$output" != *"no walkthrough drafts whose review is over"* ]]
}

@test "forget --draft --reviewed still deletes a draft a whole review is holding" {
	# Custody is mode-blind: a whole review records which draft belongs to the
	# branch but never reads one, so there is nothing to protect.
	run git review walkthrough draft telemetry
	[ "$status" -eq 0 ]
	fill_draft telemetry
	git config "reviewworkflow.telemetry.reviewed" "$(git rev-parse origin/telemetry)"
	git review start feature/checkout >/dev/null

	run git review forget --draft --reviewed
	[ "$status" -eq 0 ]
	[[ "$output" == *"forgot the walkthrough draft for telemetry"* ]]
	[ ! -f "$NS/telemetry.md" ]
}

# ── the flag itself ───────────────────────────────────────────────────────────

@test "forget --draft --reviewed refuses to be combined with a branch or --all" {
	run git review forget --draft --reviewed feature/checkout
	[ "$status" -ne 0 ]
	[[ "$output" == *"use only one of <branch>, --all and --reviewed"* ]]

	run git review forget --draft --reviewed --all
	[ "$status" -ne 0 ]
	[[ "$output" == *"use only one of <branch>, --all and --reviewed"* ]]
}

@test "forget --reviewed is refused in the other two modes" {
	run git review forget --delta --reviewed --all
	[ "$status" -ne 0 ]
	[[ "$output" == *"--reviewed only applies to --draft"* ]]

	run git review forget --saved --reviewed --all
	[ "$status" -ne 0 ]
	[[ "$output" == *"--reviewed only applies to --draft"* ]]
}

@test "forget --draft --reviewed appears in the usage" {
	run git review forget -h
	[ "$status" -eq 0 ]
	[[ "$output" == *"--reviewed"* ]]
	[[ "$output" == *"delete only the drafts whose review is over"* ]]
}
