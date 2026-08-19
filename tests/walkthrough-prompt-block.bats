#!/usr/bin/env bats
#
# Tests for the instruction block a walkthrough skeleton carries: the comment
# that names the review range in resolved objects and says how to see it.
#
# It exists because whoever fills a skeleton in — usually an agent — is standing
# in a working tree that holds the wrong content for the job: on the base branch
# the listed files hold their PRE-PR bytes, and reading them there produces prose
# about the old code, confidently and with nothing failing.
#
# Three PRs vs develop, each here for one reason:
#
#   feature/plain    modifies an existing file and adds two: the ordinary case,
#                    and the one that proves "read the file" and "read the range"
#                    are different answers. Two commits, so --delta has a range.
#   feature/merged   merged the base into itself and carries the marker a
#                    previous review would have left, which is the only shape
#                    whose review lower bound is a TREE OID and not a commit.
#                    With a tree, git log/rev-list/shortlog print the whole
#                    repository with exit 0 instead of failing, which is why the
#                    block may never name them.
#   feature/annotated  carries the author's own walkthrough, for the author-side
#                    (init/build) half of the same rules.

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

	# The ordinary PR: a.txt is MODIFIED (not added), which is what makes the
	# working tree on the base a wrong source for annotating it.
	git switch --quiet -c feature/plain
	printf 'a1\na2\n' >a.txt
	mkdir -p src
	printf 'hello\n' >src/c.txt
	git add -A
	git commit --quiet -m first
	PLAIN_PREV="$(git rev-parse HEAD)"
	printf 'a1\na2\na3\n' >a.txt
	git add -A
	git commit --quiet -m second
	git push --quiet -u origin feature/plain

	# The PR that merged the base in. The marker is set by hand: it is what
	# git review start would have written, and it is older than the base merge,
	# which is exactly the condition that folds the lower bound into a tree.
	git switch --quiet develop
	git switch --quiet -c feature/merged
	mkdir -p src
	printf 'm1\n' >src/m.txt
	git add -A
	git commit --quiet -m merged-first
	MERGED_PREV="$(git rev-parse HEAD)"
	git switch --quiet develop
	printf 'b1\nb2\n' >b.txt
	git add -A
	git commit --quiet -m base-moves
	# Pushed, because the fold is decided against the base ref the verbs resolve.
	git push --quiet origin develop
	git switch --quiet feature/merged
	git merge --quiet --no-edit develop
	printf 'm2\n' >src/m2.txt
	git add -A
	git commit --quiet -m merged-second
	git push --quiet -u origin feature/merged

	# The author's own walkthrough, for the init/build side.
	git switch --quiet develop
	git switch --quiet -c feature/annotated
	printf 'z\n' >z.txt
	git add -A
	git commit --quiet -m annotated
	git push --quiet -u origin feature/annotated

	git switch --quiet develop
	git config "reviewworkflow.feature/plain.reviewed" "$PLAIN_PREV"
	git config "reviewworkflowlocal.feature/plain.reviewed" "$PLAIN_PREV"
	git config "reviewworkflow.feature/merged.reviewed" "$MERGED_PREV"

	GITDIR="$(git rev-parse --git-dir)"
	DRAFT="$GITDIR/review-walkthrough/feature/plain.md"
	MERGED_DRAFT="$GITDIR/review-walkthrough/feature/merged.md"
}

teardown() {
	rm -rf "$TMP"
}

# The block only, from its opening sentinel to its closing marker. Every negative
# assertion below is scoped to this and never to the whole file: the skeleton's
# scaffolding contains "(1, 2, 3, ...)", so a grep for ".." over the file would
# match the scaffolding and pass while proving nothing.
block_of() {
	awk '
		index($0, "<!-- git-review-range:") == 1 { inb = 1 }
		inb {
			print
			if ($0 == "-->") exit
		}
	' "$1"
}

block_field() {
	block_of "$2" | awk -v want="$1" -v col="$3" '$1 == want { print $col; exit }'
}

block_tip() { block_field tip "$1" 2; }
block_base() { block_field base "$1" 2; }

block_kind() {
	block_of "$1" | awk '$1 == "base" { gsub(/[()]/, "", $3); print $3; exit }'
}

block_tip_label() {
	block_of "$1" | awk '$1 == "tip" { gsub(/[()]/, "", $3); print $3; exit }'
}

# Fill a generated skeleton in without changing its file list: number every
# entry in file order and replace every why placeholder with prose. The block is
# untouched, which is the point of most of the tests below.
fill_in() {
	awk '
		inhead {
			if (index($0, "-->")) {
				inhead = 0
				print "the delicate part is the retry cap"
			}
			next
		}
		index($0, "<!-- heads-up") == 1 { inhead = 1; next }
		/^## \?\. / { n++; sub(/^## \?\. /, "## " n ". "); print; next }
		/^<!-- why: -->$/ { print "why prose"; next }
		{ print }
	' "$1" >"$1.filled"
	mv "$1.filled" "$1"
}

# The review's mode as status --porcelain reports it: field 5 of the state
# record, not a prefix of the line -- the record leads with the branch, source
# and tip, so a grep anchored at the label would never match.
porcelain_mode() {
	git review status --porcelain | awk -F'\t' '$1 == "state" { print $5; exit }'
}

# ── the two endpoints ─────────────────────────────────────────────────────────

@test "the block names two objects git can resolve, and says which kind the lower one is" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]

	tip="$(block_tip "$DRAFT")"
	low="$(block_base "$DRAFT")"
	[ -n "$tip" ]
	[ -n "$low" ]
	run git cat-file -e "$tip"
	[ "$status" -eq 0 ]
	run git cat-file -e "$low"
	[ "$status" -eq 0 ]

	# The tip is the remote copy of the branch, which is the range start reviews
	# resolve; the label beside it is what the verb calls it.
	[ "$tip" = "$(git rev-parse refs/remotes/origin/feature/plain)" ]
	[ "$(block_tip_label "$DRAFT")" = "origin/feature/plain" ]

	# The kind is not decoration: it is why the commands are shaped as they are.
	[ "$(block_kind "$DRAFT")" = "$(git cat-file -t "$low")" ]
	[ "$(block_kind "$DRAFT")" = "commit" ]
}

@test "the tree-OID fixture really has a tree lower bound" {
	# Guards the fixture itself. Without this, every assertion about the tree case
	# below could be passing over an ordinary commit bound and nothing would say so.
	run git review walkthrough draft --delta feature/merged
	[ "$status" -eq 0 ]
	low="$(block_base "$MERGED_DRAFT")"
	[ -n "$low" ]
	run git cat-file -t "$low"
	[ "$status" -eq 0 ]
	[ "$output" = "tree" ]
	[ "$(block_kind "$MERGED_DRAFT")" = "tree" ]
}

# ── what the block may never say ──────────────────────────────────────────────

@test "no line of the block joins the two endpoints with dots, in any origin" {
	# git diff with a two-dot argument and no -- stats it as a possible pathspec,
	# and on Windows with a deep cwd that stat blows past MAX_PATH: exit 128,
	# "Filename too long". It does not depend on the type of either endpoint.
	for flags in "" "--local" "--offline" "--delta"; do
		rm -rf "$GITDIR/review-walkthrough"
		# shellcheck disable=SC2086
		run git review walkthrough draft $flags feature/plain
		[ "$status" -eq 0 ]
		run block_of "$DRAFT"
		[ "$status" -eq 0 ]
		[ -n "$output" ]
		if printf '%s\n' "$output" | grep -q '\.\.'; then
			echo "two-dot range in the block with flags '$flags'"
			false
		fi
	done
}

@test "the block never names a history command, in any origin" {
	# With a tree lower bound, git log <tree>..<tip> prints the whole repository
	# with exit 0. There is no way to write those commands that works, so the
	# block does not write them at all -- on either side of the review.
	for flags in "" "--local" "--offline" "--delta"; do
		rm -rf "$GITDIR/review-walkthrough"
		# shellcheck disable=SC2086
		run git review walkthrough draft $flags feature/plain
		[ "$status" -eq 0 ]
		run block_of "$DRAFT"
		[ "$status" -eq 0 ]
		if printf '%s\n' "$output" | grep -qE 'git (log|rev-list|shortlog|range-diff)'; then
			echo "history command in the block with flags '$flags'"
			false
		fi
	done
}

@test "the author side gets the same two rules" {
	git switch --quiet feature/annotated
	run git review walkthrough init
	[ "$status" -eq 0 ]
	run block_of .review/walkthrough.md
	[ "$status" -eq 0 ]
	[ -n "$output" ]
	! printf '%s\n' "$output" | grep -q '\.\.'
	! printf '%s\n' "$output" | grep -qE 'git (log|rev-list|shortlog|range-diff)'
}

# ── the commands in the block actually work ───────────────────────────────────

@test "the tree-bound block still generates, and its commands return content" {
	run git review walkthrough draft --delta feature/merged
	[ "$status" -eq 0 ]
	tip="$(block_tip "$MERGED_DRAFT")"
	low="$(block_base "$MERGED_DRAFT")"
	[ "$(block_kind "$MERGED_DRAFT")" = "tree" ]

	# The two shapes the block uses, against a tree lower bound.
	run git show "$tip:src/m2.txt"
	[ "$status" -eq 0 ]
	[ "$output" = "m2" ]
	run git diff "$low" "$tip" -- src/m2.txt
	[ "$status" -eq 0 ]
	[ -n "$output" ]
	run git diff --name-only "$low" "$tip"
	[ "$status" -eq 0 ]
	[ "$output" = "src/m2.txt" ]
}

@test "following the block gives the PR content, not the working tree content" {
	# The whole point, on a file the PR MODIFIES: standing on the base, the file
	# is right there with its pre-PR bytes and reading it is silently wrong.
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	tip="$(block_tip "$DRAFT")"
	[ "$(cat a.txt)" = "a1" ]
	run git show "$tip:a.txt"
	[ "$status" -eq 0 ]
	[ "$output" = "$(printf 'a1\na2\na3')" ]
	[ "$output" != "$(cat a.txt)" ]
}

# ── which working tree you are standing in ────────────────────────────────────

@test "from the base branch the block says so" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	run block_of "$DRAFT"
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -q 'standing on the base branch'
	! printf '%s\n' "$output" | grep -q 'inside an active review'
	! printf '%s\n' "$output" | grep -q 'standing on the PR branch'
}

@test "inside a review, with the branch named explicitly, the block says so" {
	# The case from_review gets wrong: it is 1 only when the branch was omitted,
	# so naming it from inside review/feature/plain used to pick the base phrase.
	run git review start feature/plain
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = "review/feature/plain" ]
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	run block_of "$DRAFT"
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -q 'inside an active review'
	! printf '%s\n' "$output" | grep -q 'standing on the base branch'
}

@test "init gets the author phrase and the same command body" {
	git switch --quiet feature/annotated
	run git review walkthrough init
	[ "$status" -eq 0 ]
	run block_of .review/walkthrough.md
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -q 'standing on the PR branch'
	! printf '%s\n' "$output" | grep -q 'standing on the base branch'
	# The shared body is genuinely shared: same four commands, same wording.
	printf '%s\n' "$output" | grep -q 'the change the PR makes to it'
	printf '%s\n' "$output" | grep -q 'its content after the PR'
	printf '%s\n' "$output" | grep -q 'every file in the range, again'
	[ "$(block_tip_label .review/walkthrough.md)" = "HEAD" ]
	[ "$(block_tip .review/walkthrough.md)" = "$(git rev-parse HEAD)" ]
}

@test "the closing rule is in the block in all three situations" {
	rule='Write the reading order over the range above'

	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	block_of "$DRAFT" | grep -q "$rule"

	run git review start feature/plain
	[ "$status" -eq 0 ]
	# --force because the first call above already wrote one; the situation phrase
	# is what changes, not whether the file exists.
	run git review walkthrough draft --force feature/plain
	[ "$status" -eq 0 ]
	block_of "$DRAFT" | grep -q "$rule"
	block_of "$DRAFT" | grep -q 'inside an active review'

	run git review abort
	[ "$status" -eq 0 ]
	git switch --quiet feature/annotated
	run git review walkthrough init
	[ "$status" -eq 0 ]
	block_of .review/walkthrough.md | grep -q "$rule"
}

# ── the incremental range ─────────────────────────────────────────────────────

@test "with --delta the block says the range is incremental and names the marker" {
	run git review walkthrough draft --delta feature/plain
	[ "$status" -eq 0 ]
	run block_of "$DRAFT"
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -q 'This is an incremental range'
	printf '%s\n' "$output" | grep -q 'previous review of feature/plain'
	# Equality against the marker, not "there is a SHA there": that is the only
	# thing that tells an incremental range apart from one covering the whole PR.
	[ "$(block_base "$DRAFT")" = "$(git config reviewworkflow.feature/plain.reviewed)" ]
}

@test "without --delta the block does not claim an incremental range" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	! block_of "$DRAFT" | grep -q 'incremental range'
	[ "$(block_base "$DRAFT")" = "$(git merge-base refs/remotes/origin/develop refs/remotes/origin/feature/plain)" ]
}

# ── the flags the skeleton was generated with ─────────────────────────────────

@test "Generated with records the origin and range flags in a fixed order" {
	generated_with() {
		block_of "$1" | sed -n 's/^ *Generated with: //p'
	}

	rm -rf "$GITDIR/review-walkthrough"
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[ "$(generated_with "$DRAFT")" = "(defaults)" ]

	rm -rf "$GITDIR/review-walkthrough"
	run git review walkthrough draft --local feature/plain
	[ "$status" -eq 0 ]
	[ "$(generated_with "$DRAFT")" = "--local" ]

	rm -rf "$GITDIR/review-walkthrough"
	run git review walkthrough draft --offline feature/plain
	[ "$status" -eq 0 ]
	[ "$(generated_with "$DRAFT")" = "--offline" ]

	rm -rf "$GITDIR/review-walkthrough"
	run git review walkthrough draft --delta feature/plain
	[ "$status" -eq 0 ]
	[ "$(generated_with "$DRAFT")" = "--delta" ]

	rm -rf "$GITDIR/review-walkthrough"
	run git review walkthrough draft --local --delta feature/plain
	[ "$status" -eq 0 ]
	[ "$(generated_with "$DRAFT")" = "--local --delta" ]
}

# ── surviving the rewrite ─────────────────────────────────────────────────────

@test "the block survives a build, exactly once, and a second build changes nothing" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	fill_in "$DRAFT"
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 0 ]
	run grep -c 'git-review-range' "$DRAFT"
	[ "$output" = "1" ]

	cp "$DRAFT" "$TMP/once.md"
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 0 ]
	run cmp -s "$TMP/once.md" "$DRAFT"
	[ "$status" -eq 0 ]
	run grep -c 'git-review-range' "$DRAFT"
	[ "$output" = "1" ]
}

@test "the author's build keeps the block exactly once too" {
	git switch --quiet feature/annotated
	run git review walkthrough init
	[ "$status" -eq 0 ]
	fill_in .review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	run grep -c 'git-review-range' .review/walkthrough.md
	[ "$output" = "1" ]

	cp .review/walkthrough.md "$TMP/once.md"
	run git review walkthrough build
	[ "$status" -eq 0 ]
	run cmp -s "$TMP/once.md" .review/walkthrough.md
	[ "$status" -eq 0 ]
}

@test "the rewrite regenerates the block instead of carrying it forward" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	fill_in "$DRAFT"
	old_tip="$(block_tip "$DRAFT")"

	# A commit that touches the SAME paths: the file set does not change, so the
	# drift check has nothing to say. A carried block would keep the old tip and
	# nothing at all would report it.
	git switch --quiet feature/plain
	printf 'a1\na2\na3\na4\n' >a.txt
	git add -A
	git commit --quiet -m third
	git push --quiet origin feature/plain
	git switch --quiet develop
	new_tip="$(git rev-parse refs/remotes/origin/feature/plain)"
	[ "$new_tip" != "$old_tip" ]

	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 0 ]
	[ "$(block_tip "$DRAFT")" = "$new_tip" ]
	run grep -c 'git-review-range' "$DRAFT"
	[ "$output" = "1" ]
}

@test "a hand-written block in the input is neither duplicated nor leaked into the preamble" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	cat >"$DRAFT" <<'EOF'
# Walkthrough

<!-- git-review-range: stale text somebody pasted here
     base  deadbeef  (commit)
-->

## Heads-up

mind the encoding

## 1. a.txt
why a

## 2. src/c.txt
why c
EOF
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 0 ]
	run grep -c 'git-review-range' "$DRAFT"
	[ "$output" = "1" ]
	! grep -q 'stale text somebody pasted here' "$DRAFT"

	run git review start feature/plain
	[ "$status" -eq 0 ]
	! printf '%s\n' "$output" | grep -q 'git-review-range'
	! printf '%s\n' "$output" | grep -q 'stale text somebody pasted here'
	printf '%s\n' "$output" | grep -q 'mind the encoding'
}

@test "--check writes nothing, block included" {
	# The author's side owns --check; on the reviewer's it is refused outright,
	# with the same net effect, so both are pinned here.
	git switch --quiet feature/annotated
	run git review walkthrough init
	[ "$status" -eq 0 ]
	fill_in .review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	cp .review/walkthrough.md "$TMP/before.md"
	run git review walkthrough build --check
	[ "$status" -eq 0 ]
	run cmp -s "$TMP/before.md" .review/walkthrough.md
	[ "$status" -eq 0 ]

	git switch --quiet develop
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	cp "$DRAFT" "$TMP/draft-before.md"
	run git review walkthrough draft --build --check feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"--check applies only to git review walkthrough build"* ]]
	run cmp -s "$TMP/draft-before.md" "$DRAFT"
	[ "$status" -eq 0 ]
}

# ── the reviewer never sees it ────────────────────────────────────────────────

@test "start prints no line of the block, and prints the heads-up that sits beside it" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	cat >"$DRAFT" <<'EOF'
# Walkthrough

## Heads-up

the delicate part is the retry cap

## 1. a.txt
why a

## 2. src/c.txt
why c
EOF
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 0 ]
	grep -q 'git-review-range' "$DRAFT"

	run git review start feature/plain
	[ "$status" -eq 0 ]
	! printf '%s\n' "$output" | grep -q 'git-review-range'
	! printf '%s\n' "$output" | grep -q 'Range under review'
	! printf '%s\n' "$output" | grep -q 'Generated with'
	printf '%s\n' "$output" | grep -q 'the delicate part is the retry cap'
}

@test "status --why shows the why and no line of the block" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	cat >"$DRAFT" <<'EOF'
# Walkthrough

## 1. a.txt
the reason a.txt matters

## 2. src/c.txt
why c
EOF
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 0 ]
	run git review start feature/plain
	[ "$status" -eq 0 ]
	run git review status --why a.txt
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -q 'the reason a.txt matters'
	! printf '%s\n' "$output" | grep -q 'git-review-range'
	! printf '%s\n' "$output" | grep -q 'Range under review'
}

@test "a preamble holding only the block prints no empty heads-up" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	fill_in "$DRAFT"
	# Drop the ## Heads-up section entirely, as the skeleton says you may.
	awk '/^## Heads-up$/ { drop = 1 } /^## 1\. / { drop = 0 } !drop { print }' "$DRAFT" >"$DRAFT.x"
	mv "$DRAFT.x" "$DRAFT"
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 0 ]
	grep -q 'git-review-range' "$DRAFT"

	run git review start feature/plain
	[ "$status" -eq 0 ]
	! printf '%s\n' "$output" | grep -q 'git-review-range'
	! printf '%s\n' "$output" | grep -q 'Heads-up'
	# Walk mode was entered all the same.
	[ "$(porcelain_mode)" = "walk" ]
}

@test "re-annotating after drift needs no new skeleton: the block is still in the file" {
	# The reason the block is kept rather than stripped on build. When the PR
	# gains a file, the draft has to be edited -- and the instructions for editing
	# it, with the range they are about, are right there, with every why already
	# written underneath.
	run git review walkthrough draft --stdout feature/plain
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" >"$TMP/printed.md"
	fill_in "$TMP/printed.md"
	run git review walkthrough draft --build --from "$TMP/printed.md" feature/plain
	[ "$status" -eq 0 ]

	git switch --quiet feature/plain
	printf 'n\n' >src/new.txt
	git add -A
	git commit --quiet -m adds-a-file
	git push --quiet origin feature/plain
	git switch --quiet develop

	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"changed in the PR but missing from the walkthrough: src/new.txt"* ]]

	# Nothing was rebuilt and nothing was lost: one block, and the whys are there.
	run grep -c 'git-review-range' "$DRAFT"
	[ "$output" = "1" ]
	run grep -c 'why prose' "$DRAFT"
	[ "$output" = "2" ]
}

# ── neutral for validation ────────────────────────────────────────────────────

@test "a draft validates the same with the block and without it" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	fill_in "$DRAFT"
	cp "$DRAFT" "$TMP/with-block.md"

	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 0 ]
	with_status="$status"

	# The same content with the block deleted by hand, which is legal.
	awk '
		index($0, "<!-- git-review-range:") == 1 { skip = 1; next }
		skip { if (index($0, "-->")) skip = 0; next }
		{ print }
	' "$TMP/with-block.md" >"$DRAFT"
	! grep -q 'git-review-range' "$DRAFT"
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq "$with_status" ]
	[ "$status" -eq 0 ]
	# And the rewrite puts one back, so the file is whole again.
	run grep -c 'git-review-range' "$DRAFT"
	[ "$output" = "1" ]

	run git review start feature/plain
	[ "$status" -eq 0 ]
	[ "$(porcelain_mode)" = "walk" ]
}

@test "the rejection messages are identical with and without the block" {
	# Every rule that can reject a draft, run twice over the same content: once
	# with the block the skeleton wrote, once with it deleted. Same exit, same
	# message. If the block ever became a ninth rule, one of these pairs breaks.
	assert_same_rejection() {
		body="$1"
		run git review walkthrough draft --force feature/plain
		[ "$status" -eq 0 ]
		# With the block: keep the skeleton's, append the broken body.
		block_of "$DRAFT" >"$TMP/block.txt"
		{
			printf '# Walkthrough\n\n'
			cat "$TMP/block.txt"
			printf '\n'
			printf '%s\n' "$body"
		} >"$DRAFT"
		run git review walkthrough draft --build feature/plain
		with_status="$status"
		with_output="$output"
		[ "$with_status" -eq 1 ]

		{
			printf '# Walkthrough\n\n'
			printf '%s\n' "$body"
		} >"$DRAFT"
		run git review walkthrough draft --build feature/plain
		[ "$status" -eq "$with_status" ]
		[ "$output" = "$with_output" ]
	}

	assert_same_rejection "$(printf '## ?. a.txt\nwhy a\n\n## 2. src/c.txt\nwhy c\n')"
	assert_same_rejection "$(printf '## 1. a.txt\n<!-- why: -->\n\n## 2. src/c.txt\nwhy c\n')"
	assert_same_rejection "$(printf '## 1. a.txt\nwhy a\n\n## 2. a.txt\nwhy a again\n')"
	assert_same_rejection "$(printf '## 1. a.txt\n> key: because\nwhy a\n\n## 2. src/c.txt\nwhy c\n')"
	assert_same_rejection "$(printf '## 1. a.txt\nwhy a\n')"

	# The malformed-heading rule is the one message that names a LINE NUMBER, so
	# the two files cannot produce identical text -- the block sits above the
	# heading and shifts it. What has to match is the rule and the offending
	# heading, which is what is compared here; asserting the whole string would be
	# asserting that the two files are the same file.
	run git review walkthrough draft --force feature/plain
	[ "$status" -eq 0 ]
	block_of "$DRAFT" >"$TMP/block.txt"
	bad="$(printf '## 1) a.txt\nwhy a\n\n## 2. src/c.txt\nwhy c\n')"
	{
		printf '# Walkthrough\n\n'
		cat "$TMP/block.txt"
		printf '\n'
		printf '%s\n' "$bad"
	} >"$DRAFT"
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"entry heading(s) not in the '## N. <path>' form"* ]]
	[[ "$output" == *"## 1) a.txt"* ]]

	{
		printf '# Walkthrough\n\n'
		printf '%s\n' "$bad"
	} >"$DRAFT"
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"entry heading(s) not in the '## N. <path>' form"* ]]
	[[ "$output" == *"## 1) a.txt"* ]]
}
