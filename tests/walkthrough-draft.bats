#!/usr/bin/env bats
#
# Tests for git review walkthrough draft: the reviewer's own reading order for a
# PR whose author never wrote one, kept outside the working tree entirely.
#
# Two PRs vs develop. feature/plain changes three files and carries NO
# walkthrough — the case the whole feature exists for. feature/annotated carries
# one, and is here to prove the draft takes precedence over it and says so.

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

	# The unannotated PR. One path carries a space and a non-ASCII byte on
	# purpose: those are what keep breaking path comparison in silence.
	git switch --quiet -c feature/plain
	printf 'a1\na2\n' >a.txt
	mkdir -p src
	printf 'hello\n' >src/c.txt
	printf 'x\n' >"src/café con espacio.js"
	git add -A
	git commit --quiet -m work
	git push --quiet -u origin feature/plain

	git switch --quiet develop
	git switch --quiet -c feature/annotated
	printf 'b1\nb2\n' >b.txt
	mkdir -p .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. b.txt
the author's own reading order
EOF
	git add -A
	git commit --quiet -m work-with-walkthrough
	git push --quiet -u origin feature/annotated

	git switch --quiet develop

	DRAFT="$(git rev-parse --git-dir)/review-walkthrough/feature/plain.md"
}

teardown() {
	rm -rf "$TMP"
}

# Portable in-place edit (the same helper step-replay.bats carries, and for the
# same reason): BSD/macOS sed consumes the script as -i's backup suffix, so the
# bare `sed -i 'script' file` form errors on the macOS runner.
edit_file() {
	tmp="$(mktemp)"
	sed "$1" "$2" >"$tmp" && mv "$tmp" "$2"
}

# Fill the draft for feature/plain with a valid, deliberately non-diff order.
fill_draft() {
	cat >"$DRAFT" <<'EOF'
# Walkthrough

## Heads-up

mind the encoding of that one path

## 3. a.txt
last

## 1. src/c.txt
> key
start here

## 2. src/café con espacio.js
then this
EOF
}

# ── creating ──────────────────────────────────────────────────────────────────

@test "draft writes a skeleton for the named branch listing every changed file" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"3 file(s)"* ]]
	[ -f "$DRAFT" ]
	# Every path of the range is listed as an unfilled entry, and nothing else is.
	run grep -c '^## ?\. ' "$DRAFT"
	[ "$status" -eq 0 ]
	[ "$output" = "3" ]
	grep -Fxq '## ?. a.txt' "$DRAFT"
	grep -Fxq '## ?. src/c.txt' "$DRAFT"
	grep -Fxq '## ?. src/café con espacio.js' "$DRAFT"
}

@test "draft leaves the working tree and the index untouched" {
	before="$(git status --porcelain)"
	# Every path the work tree holds, tracked and untracked alike, before and
	# after. The invariant is that drafting adds nothing anywhere a reviewer could
	# commit it from — asserting only on one filename would pass even if the
	# draft landed in the work tree under another.
	before_files="$(git ls-files -co | LC_ALL=C sort)"
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[ -f "$DRAFT" ]
	[ "$(git status --porcelain)" = "$before" ]
	[ "$(git ls-files -co | LC_ALL=C sort)" = "$before_files" ]
	# Not even as an ignored file: the draft is in the gitdir, which git status
	# does not walk at all.
	run git status --porcelain --ignored
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "draft defaults to the branch you are on" {
	git switch --quiet feature/plain
	run git review walkthrough draft
	[ "$status" -eq 0 ]
	[ -f "$DRAFT" ]
	# The file existing says nothing about which branch it was written for: the
	# range is what tells "took the branch I am on" apart from "took anything at
	# all and wrote it there".
	run grep -c '^## ?\. ' "$DRAFT"
	[ "$status" -eq 0 ]
	[ "$output" = "3" ]
	grep -Fxq '## ?. a.txt' "$DRAFT"
	grep -Fxq '## ?. src/c.txt' "$DRAFT"
	grep -Fxq '## ?. src/café con espacio.js' "$DRAFT"
}

@test "draft with no argument inside a review drafts for the review's source" {
	# Standing inside the review is when a reviewer knows they want their own
	# order, and the branch they are standing on is review/feature/plain -- a name
	# nobody drafts for and one with no remote copy, so the bare command died
	# naming origin/review/feature/plain, a ref that never existed.
	git review start feature/plain
	[ "$(git symbolic-ref --short HEAD)" = "review/feature/plain" ]
	run git review walkthrough draft
	[ "$status" -eq 0 ]
	[[ "$output" == *"3 file(s)"* ]]
	# Named for the source, so the command it suggests is the one that works.
	[[ "$output" == *"git review walkthrough draft --build feature/plain"* ]]
	[ -f "$DRAFT" ]
	run grep -c '^## ?\. ' "$DRAFT"
	[ "$status" -eq 0 ]
	[ "$output" = "3" ]
	grep -Fxq '## ?. src/café con espacio.js' "$DRAFT"
	# And --build from the same place validates that same draft.
	fill_draft
	run git review walkthrough draft --build
	[ "$status" -eq 0 ]
	grep -Fxq '## 1. src/c.txt' "$DRAFT"
	grep -Fxq '## 3. a.txt' "$DRAFT"
}

@test "draft with no argument inside a compare of a remote-tracking branch writes the branch's draft" {
	# The review's identity here is "origin/feature/plain"; the draft belongs to
	# "feature/plain", because a draft belongs to the branch and not to the ref you
	# happened to name it by. The compare records that name and this reads it back,
	# so the file lands where every other entry point looks for it.
	#
	# The two used to be derived separately -- the compare stripping the remote,
	# this one taking the source verbatim -- and they disagreed in silence: the
	# draft went to origin/feature/plain.md, where a later git review start,
	# forget --draft and the command this very message prints would none of them
	# ever look.
	git review compare develop origin/feature/plain
	[ "$(git config branch.review/origin/feature/plain.reviewsource)" = "origin/feature/plain" ]
	[ "$(git config branch.review/origin/feature/plain.reviewdraft)" = "feature/plain" ]
	run git review walkthrough draft
	[ "$status" -eq 0 ]
	[[ "$output" == *"3 file(s)"* ]]
	[ -f "$DRAFT" ]
	[ ! -f "$(git rev-parse --git-dir)/review-walkthrough/origin/feature/plain.md" ]
	run grep -c '^## ?\. ' "$DRAFT"
	[ "$status" -eq 0 ]
	[ "$output" = "3" ]
}

@test "the build command a compare review suggests is one that runs" {
	# It named the review's source, and drafting for "origin/feature/plain" goes
	# looking for origin/origin/feature/plain: the next step the tool itself
	# printed was a dead end with no hint of where to go instead.
	git review compare develop origin/feature/plain
	run git review walkthrough draft
	[ "$status" -eq 0 ]
	[[ "$output" == *"git review walkthrough draft --build feature/plain"* ]]
	fill_draft

	# Typed exactly as printed, from where you are when you read it: inside the
	# review, on review/origin/feature/plain.
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 0 ]
	grep -Fxq '## 1. src/c.txt' "$DRAFT"
	grep -Fxq '## 3. a.txt' "$DRAFT"
}

@test "a draft written inside a compare is the one a later start reads" {
	# The whole point of writing it: the compare is where you find out nobody
	# ordered the PR, and the review you do afterwards is the one that has to read
	# what you wrote there. Filed under the review's own name it was invisible
	# here, and start opened on the whole diff without a word about the draft.
	git review compare develop origin/feature/plain
	git review walkthrough draft
	fill_draft
	git review abort

	run git review start feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/3] src/c.txt"* ]]
	[[ "$output" == *"start here"* ]]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk (draft)"* ]]
	# And custody answers to the same name: this is the command that throws it away.
	run git review forget --draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"forgot the walkthrough draft for feature/plain"* ]]
	[[ "$output" == *"review/feature/plain was reading it"* ]]
	[ ! -f "$DRAFT" ]
}

@test "a compare in whole mode records where its draft goes" {
	# No walkthrough anywhere, so this compare is a plain whole-diff review -- and
	# the draft written inside it still has to land under the branch's name. The
	# name used to be recorded only by the walk path, so the one mode where a
	# reviewer is most likely to start writing an order was the one that did not
	# know where to put it.
	git review compare develop origin/feature/plain
	[ "$(git config branch.review/origin/feature/plain.reviewmode || true)" = "" ]
	[ "$(git config branch.review/origin/feature/plain.reviewdraft)" = "feature/plain" ]
	git review walkthrough draft
	[ -f "$DRAFT" ]
	fill_draft
	# list badges custody in every mode, under the name the review recorded.
	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"whole (draft)"* ]]
}

@test "drafting inside a compare of a loose revision says there is no branch" {
	# A compare of a SHA records its own identity as the draft's name, because that
	# is the only name the comparison has. It names no branch, so the bare command
	# went looking for origin/<short-sha> and died on a ref that never existed --
	# the same shape as the origin/review/feature/x error the review-aware
	# resolution exists to prevent.
	sha="$(git rev-parse --short origin/feature/plain)"
	git review compare develop "$sha" >/dev/null
	run git review walkthrough draft
	[ "$status" -eq 1 ]
	[[ "$output" == *"this review compares $sha, which is not a branch"* ]]
	[[ "$output" == *"git review walkthrough draft <branch>"* ]]
	[[ "$output" != *"origin/$sha"* ]]
	[ ! -f "$(git rev-parse --git-dir)/review-walkthrough/$sha.md" ]

	# Naming the branch from in there still works, and lands where it belongs.
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[ -f "$DRAFT" ]
}

@test "a compare --step of a remote-tracking branch records where its draft goes" {
	# --step exits before the whole-mode tail, and the name used to be written only
	# there: this review recorded nothing and every reader fell back to the source,
	# which for a remote-tracking <b> is "origin/feature/plain". Step mode reads no
	# walkthrough, but it holds custody of one exactly like the other two.
	git review compare develop origin/feature/plain --step >/dev/null
	[ "$(git config branch.review/origin/feature/plain.reviewsource)" = "origin/feature/plain" ]
	[ "$(git config branch.review/origin/feature/plain.reviewdraft)" = "feature/plain" ]

	# The bare draft command from inside the review died with
	# "origin/origin/feature/plain not found" -- a ref that never existed.
	run git review walkthrough draft
	[ "$status" -eq 0 ]
	[[ "$output" == *"3 file(s) from origin/feature/plain"* ]]
	[[ "$output" == *"git review walkthrough draft --build feature/plain"* ]]
	[ -f "$DRAFT" ]
	[ ! -f "$(git rev-parse --git-dir)/review-walkthrough/origin/feature/plain.md" ]
}

@test "a step review carries the draft into the saved namespace" {
	# The custody chain the missing name broke: save filed nothing, so list never
	# badged the paused row and forget --saved never took the file with the review.
	git review walkthrough draft feature/plain >/dev/null
	fill_draft
	git review compare develop origin/feature/plain --step >/dev/null
	git review save >/dev/null
	[ ! -f "$DRAFT" ]
	saved="$(git rev-parse --git-dir)/review-saved-walkthrough/feature/plain.md"
	[ -f "$saved" ]
	grep -Fxq 'start here' "$saved"

	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"review-saved/origin/feature/plain"* ]]
	[[ "$output" == *"step (draft) ["* ]]

	# And it comes back with the review, under the same name.
	run git review continue origin/feature/plain
	[ "$status" -eq 0 ]
	[ -f "$DRAFT" ]
	[ ! -f "$saved" ]
	grep -Fxq 'start here' "$DRAFT"
}

@test "start --step records the draft name and says the order is being bypassed" {
	git review walkthrough draft feature/plain >/dev/null
	fill_draft
	run git review start --step feature/plain
	[ "$status" -eq 0 ]
	# Attributed to whoever wrote it. The context was set after this branch, so a
	# reviewer who had written an order and then asked for --step was told nothing,
	# while the same PR annotated by its author said so.
	[[ "$output" == *"you have a walkthrough draft for feature/plain; --step ignores it"* ]]
	[[ "$output" != *"feature/plain has a walkthrough;"* ]]
	[ "$(git config branch.review/feature/plain.reviewmode)" = "step" ]
	[ "$(git config branch.review/feature/plain.reviewdraft)" = "feature/plain" ]
	# The note is about the draft and nothing else: --step really is stepping.
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"mode    step"* ]]
}

@test "start --step on an author walkthrough still names the author" {
	# The other arm of the same message: with no draft of ours the wording must not
	# have changed.
	run git review start --step feature/annotated
	[ "$status" -eq 0 ]
	[[ "$output" == *"feature/annotated has a walkthrough; --step ignores it"* ]]
	[[ "$output" != *"you have a walkthrough draft"* ]]
}

@test "draft refuses to overwrite an existing draft without --force" {
	git review walkthrough draft feature/plain
	fill_draft
	before="$(cat "$DRAFT")"
	run git review walkthrough draft feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"already exists"* ]]
	[[ "$output" == *"--force"* ]]
	# The refusal did not touch what the reviewer had written.
	[ "$(cat "$DRAFT")" = "$before" ]
}

@test "draft --force overwrites an existing draft" {
	git review walkthrough draft feature/plain
	fill_draft
	run git review walkthrough draft feature/plain --force
	[ "$status" -eq 0 ]
	# Back to a skeleton: the filled entries are gone.
	run grep -c '^## ?\. ' "$DRAFT"
	[ "$status" -eq 0 ]
	[ "$output" = "3" ]
	run grep -c '^## [0-9]\+\. ' "$DRAFT"
	[ "$status" -ne 0 ]
	[ "$output" = "0" ]
}

@test "a draft survives between invocations with its content intact" {
	git review walkthrough draft feature/plain
	fill_draft
	expected="$(cat "$DRAFT")"
	run git review config --porcelain -- feature/plain
	[ "$status" -eq 0 ]
	[ "$(cat "$DRAFT")" = "$expected" ]
}

@test "the draft skeleton closes with the draft's own build command" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	# The file the reviewer has open in front of them used to close with the
	# author's two instructions: "git review walkthrough build", which from the base
	# dies on a .review/walkthrough.md that is not there, and "commit the PR before
	# authoring it" -- about someone else's PR, and the very advice warn_dirty is
	# deliberately suppressed for on this path.
	grep -q 'Then validate and write with:  git review walkthrough draft --build feature/plain -->' "$DRAFT"
	! grep -q 'git review walkthrough build' "$DRAFT"
	! grep -q 'Commit the PR before authoring it' "$DRAFT"
	! grep -q 'never push automatically' "$DRAFT"
	# What it says instead is true of a draft, and says where the file is not.
	grep -q 'never from your working tree' "$DRAFT"
	grep -q 'ever staged or committed' "$DRAFT"
	# The rest of the instructions are still the shared ones: switching those two
	# passages must not have forked the block into two copies that drift.
	grep -q '"> key"' "$DRAFT"
	grep -q 'Fill in the "## Heads-up" section below' "$DRAFT"
}

@test "draft skeleton names no guide when neither is in force" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	run grep -c 'Authoring guide' "$DRAFT"
	[ "$output" = "0" ]
}

@test "draft skeleton names the guides in force" {
	# Resolved from the work tree the reviewer is standing in, not from the PR tip:
	# these are the conventions of whoever is annotating.
	mkdir -p .review
	printf 'team rules\n' >.review/walkthrough-guide.md
	printf 'my rules\n' >"$(git rev-parse --git-dir)/review-walkthrough-guide.md"
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	grep -q 'Authoring guide for this repository' "$DRAFT"
	grep -q '\.review/walkthrough-guide\.md  (this repository, shared)' "$DRAFT"
	grep -q 'review-walkthrough-guide\.md  (the reviewer, private)' "$DRAFT"
	grep -qi 'cannot change this format' "$DRAFT"
}

@test "draft notes how to create a guide when there is none" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"no authoring guide"* ]]
	[[ "$output" == *"git review walkthrough guide"* ]]
	[[ "$output" != *"in force"* ]]
}

@test "draft notes the guide in force in the work tree" {
	mkdir -p .review
	printf '# team rules\n' >.review/walkthrough-guide.md
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"authoring guide in force at .review/walkthrough-guide.md"* ]]
	[[ "$output" != *"no authoring guide"* ]]
}

@test "the draft skeleton repeats the flags the draft was written with" {
	# Same shape as the line the verb prints on stdout: a reviewer who came back to
	# the file a day later must not be told to rebuild it against origin's copy of a
	# branch they drafted locally.
	run git review walkthrough draft --offline feature/plain
	[ "$status" -eq 0 ]
	grep -q 'git review walkthrough draft --build --offline feature/plain -->' "$DRAFT"
}

@test "build on a draft with no entries points back at the draft, never at init" {
	git review walkthrough draft feature/plain
	# Prose and no entry heading at all -- the unfilled "## ?." check does not own
	# this one. It is reachable from the IDE assistant, which offers to resume any
	# draft file that exists, and init is the author's flow: it writes
	# .review/walkthrough.md into the working tree of whatever branch you are
	# standing on, the one thing this verb exists never to do.
	printf '# Walkthrough\n\nnotes to myself, no order yet\n' >"$DRAFT"
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"no entries found in"* ]]
	[[ "$output" == *"review-walkthrough/feature/plain.md"* ]]
	[[ "$output" == *"git review walkthrough draft --force feature/plain"* ]]
	[[ "$output" != *"walkthrough init"* ]]
	# Rejected, and the reviewer's file is exactly as they left it.
	[ "$(cat "$DRAFT")" = "$(printf '# Walkthrough\n\nnotes to myself, no order yet')" ]
	[ ! -e .review/walkthrough.md ]
}

# Every temp file the draft namespace can be left holding, as a newline-separated
# list. A glob and not find: the lib avoids find by writing, because under Git
# Bash a stray PATH resolves it to Windows' own find.exe, whose -name means
# nothing to it — and CI runs this suite on a real Windows runner, where the test
# would then pass or fail for reasons that have nothing to do with the draft.
# nullglob is a bashism but this is a bats file, not a POSIX verb.
draft_temps() (
	shopt -s nullglob
	printf '%s\n' "$(dirname "$DRAFT")"/*.tmp.*
)

@test "writing a draft leaves no temporary file behind" {
	git review walkthrough draft feature/plain
	[ -f "$DRAFT" ]
	# The skeleton is written to "<target>.tmp.$$" and moved into place. Anything
	# else left in the namespace is litter nobody collects: walk_draft_list only
	# matches *.md, clean is deliberately hands-off in there, and forget --draft
	# only knows names it can spell.
	run draft_temps
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "a draft is shared by the local and the remote reading of one branch" {
	# The path encodes the branch and nothing else — not the origin it was drafted
	# against, not the range — so --offline and the plain form are two ways into the
	# same file. Deliberate: one branch, one reading order. Pinned because the
	# alternative would only ever be discovered by a reviewer wondering where theirs
	# went.
	git review walkthrough draft --offline feature/plain
	[ -f "$DRAFT" ]
	run git review walkthrough draft feature/plain
	[ "$status" -ne 0 ]
	[[ "$output" == *"already exists"* ]]
	[[ "$output" == *"pass --force to overwrite"* ]]
}

@test "each git worktree keeps its own draft" {
	# --git-dir, not --git-common-dir: a review is per working tree, and so is the
	# order it is read in. Both clients resolve the same path by reading the
	# worktree's .git link, so this is the CLI half of that contract.
	git review walkthrough draft feature/plain
	# Absolute, because the rest of this test runs from another working tree, where
	# the "$(git rev-parse --git-dir)" DRAFT was built from means something else.
	main_draft="$WORK/.git/review-walkthrough/feature/plain.md"
	[ -f "$main_draft" ]

	git worktree add --quiet --detach "$TMP/wt" develop
	cd "$TMP/wt"
	[ "$(git rev-parse --absolute-git-dir)" != "$(git -C "$WORK" rev-parse --absolute-git-dir)" ]

	# The other working tree's draft is not this one's.
	run git review forget --draft --all
	[ "$status" -eq 0 ]
	[[ "$output" == *"no walkthrough drafts"* ]]

	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	wt_draft="$(git rev-parse --absolute-git-dir)/review-walkthrough/feature/plain.md"
	[ -f "$wt_draft" ]
	# Two files, one per working tree, neither disturbed by the other.
	[ -f "$main_draft" ]
	run git review forget --draft feature/plain
	[ "$status" -eq 0 ]
	[ ! -f "$wt_draft" ]
	[ -f "$main_draft" ]
}

@test "draft on a PR that has a walkthrough warns that the draft wins" {
	run git review walkthrough draft feature/annotated
	[ "$status" -eq 0 ]
	[[ "$output" == *"already carries a walkthrough from its author"* ]]
	[[ "$output" == *"takes precedence"* ]]
	# The author's sidecar is untouched: it is committed content, not ours.
	# The branch is resolved to a SHA first, for the same reason wt_blob in
	# walk.bats does it: under Git Bash MSYS reads
	# "origin/feature/annotated:.review/walkthrough.md" as a POSIX path list --
	# two slash-bearing components around a colon -- and git.exe gets
	# "origin\feature\annotated;.review\walkthrough.md". A SHA has no slash
	# before the colon. The command under test is safe on its own: it resolves
	# the rev with rev-parse before building the "<rev>:<path>" argument.
	run git show "$(git rev-parse origin/feature/annotated):.review/walkthrough.md"
	[ "$status" -eq 0 ]
	[[ "$output" == *"the author's own reading order"* ]]
}

# ── refusals that leave nothing behind ────────────────────────────────────────

@test "draft for an unknown branch fails and writes nothing" {
	run git review walkthrough draft no/such/branch
	[ "$status" -eq 1 ]
	[[ "$output" == *"not found"* ]]
	[ ! -e "$(git rev-parse --git-dir)/review-walkthrough/no/such/branch.md" ]
}

@test "draft without reviewworkflow.base fails with an actionable message" {
	git config --unset reviewworkflow.base
	run git review walkthrough draft feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"no base set"* ]]
	[[ "$output" == *"reviewworkflow.base"* ]]
	[ ! -f "$DRAFT" ]
}

@test "draft --delta without a previous review fails and writes nothing" {
	run git review walkthrough draft --delta feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"no previous review"* ]]
	[ ! -f "$DRAFT" ]
}

@test "draft rejects --local together with --offline" {
	run git review walkthrough draft --local --offline feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"only one of --local and --offline"* ]]
	[ ! -f "$DRAFT" ]
}

@test "draft flags are refused on init and build" {
	run git review walkthrough init --delta
	[ "$status" -eq 1 ]
	[[ "$output" == *"apply only to git review walkthrough draft"* ]]
	run git review walkthrough build feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"only git review walkthrough draft takes a branch"* ]]
}

@test "draft rejects --force with --build" {
	run git review walkthrough draft --build --force feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"--force applies only when creating a draft"* ]]
}

# ── validating ────────────────────────────────────────────────────────────────

@test "draft --build without a draft says so" {
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"no draft for feature/plain"* ]]
}

@test "draft --build rejects an unfilled draft and changes nothing" {
	git review walkthrough draft feature/plain
	before="$(cat "$DRAFT")"
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"unfilled entries remain"* ]]
	[ "$(cat "$DRAFT")" = "$before" ]
}

@test "draft --build reports drift in both directions and changes nothing" {
	git review walkthrough draft feature/plain
	cat >"$DRAFT" <<'EOF'
# Walkthrough

## 1. a.txt
kept

## 2. gone.txt
this file is not in the PR
EOF
	before="$(cat "$DRAFT")"
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"missing from the walkthrough"* ]]
	[[ "$output" == *"src/c.txt"* ]]
	[[ "$output" == *"not changed in the PR"* ]]
	[[ "$output" == *"gone.txt"* ]]
	[ "$(cat "$DRAFT")" = "$before" ]
}

@test "draft --build rejects a > key marker carrying a value" {
	git review walkthrough draft feature/plain
	fill_draft
	edit_file 's/^> key$/> key: because it matters/' "$DRAFT"
	before="$(cat "$DRAFT")"
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"takes no value"* ]]
	# A rejected build leaves the draft byte for byte as the reviewer left it.
	[ "$(cat "$DRAFT")" = "$before" ]
}

@test "draft --build orders by the numbers and renumbers 1..N" {
	git review walkthrough draft feature/plain
	fill_draft
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"3 entries (1 key)"* ]]
	# Renumbered into the reviewer's order, not the diff order.
	run grep '^## ' "$DRAFT"
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 4 ]
	[ "${lines[0]}" = "## Heads-up" ]
	[ "${lines[1]}" = "## 1. src/c.txt" ]
	[ "${lines[2]}" = "## 2. src/café con espacio.js" ]
	[ "${lines[3]}" = "## 3. a.txt" ]
	# The heads-up preamble is preserved verbatim.
	grep -Fxq 'mind the encoding of that one path' "$DRAFT"
}

@test "draft --build is idempotent on an already built draft" {
	git review walkthrough draft feature/plain
	fill_draft
	git review walkthrough draft --build feature/plain
	first="$(cat "$DRAFT")"
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 0 ]
	[ "$(cat "$DRAFT")" = "$first" ]
}

# ── origin, range, and the argv the clients send ──────────────────────────────

@test "draft takes the branch after -- like the clients send it" {
	# draftArgs() in both IDEs emits exactly this shape
	# (contracts/cli-invocation-draft.md): draft [--build] [--local|--offline]
	# [--delta] -- <branch>. Nothing else in the suite exercises the -- form, and
	# the positional parser it goes through is where the branch is picked up.
	run git review walkthrough draft --local -- feature/plain
	[ "$status" -eq 0 ]
	[ -f "$DRAFT" ]
	fill_draft
	run git review walkthrough draft --build --local -- feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"3 entries (1 key)"* ]]
	run grep -c '^## [0-9]\+\. ' "$DRAFT"
	[ "$status" -eq 0 ]
	[ "$output" = "3" ]
	# The branch was read as the branch, not swallowed as a second subcommand.
	run grep '^## 1\. ' "$DRAFT"
	[ "$status" -eq 0 ]
	[ "$output" = "## 1. src/c.txt" ]
}

@test "draft --offline resolves both ends locally" {
	# A branch with no copy on the remote: with --offline neither the tip nor the
	# base goes near origin, which is the whole reason the flag exists.
	git switch --quiet -c feature/onlylocal develop
	printf 'z\n' >z.txt
	git add -A
	git commit --quiet -m z
	git switch --quiet develop
	d="$(git rev-parse --git-dir)/review-walkthrough/feature/onlylocal.md"

	run git review walkthrough draft --offline feature/onlylocal
	[ "$status" -eq 0 ]
	[[ "$output" == *"1 file(s) from feature/onlylocal"* ]]
	run grep -c '^## ?\. ' "$d"
	[ "$status" -eq 0 ]
	[ "$output" = "1" ]
	grep -Fxq '## ?. z.txt' "$d"
}

@test "the command a draft suggests carries the flags it was made with" {
	git switch --quiet -c feature/onlylocal develop
	printf 'z\n' >z.txt
	git add -A
	git commit --quiet -m z
	git switch --quiet develop
	d="$(git rev-parse --git-dir)/review-walkthrough/feature/onlylocal.md"

	run git review walkthrough draft --offline feature/onlylocal
	[ "$status" -eq 0 ]
	# Bare, this suggested "draft --build feature/onlylocal", which dies with
	# "origin/feature/onlylocal not found" — the command it had just told you to
	# run, on the branch it had just drafted for.
	[[ "$output" == *"git review walkthrough draft --build --offline feature/onlylocal"* ]]

	printf '# Walkthrough\n\n## 1. z.txt\nwhy\n' >"$d"
	run git review walkthrough draft --build --offline feature/onlylocal
	[ "$status" -eq 0 ]
	[[ "$output" == *"git review start --offline feature/onlylocal now reads it"* ]]

	# And what it suggests is a command that works, on the range it drafted.
	run git review start --offline feature/onlylocal
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/1] z.txt"* ]]
	[ "$(git config branch.review/feature/onlylocal.reviewmode)" = "walk" ]
}

@test "draft --delta covers only the commits since the last review" {
	git config reviewworkflow.feature/plain.reviewed "$(git rev-parse origin/feature/plain)"
	git switch --quiet feature/plain
	printf 'new\n' >new.txt
	git add -A
	git commit --quiet -m more
	git push --quiet origin feature/plain
	git switch --quiet develop

	run git review walkthrough draft --delta feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"1 file(s)"* ]]
	[[ "$output" == *"git review walkthrough draft --build --delta feature/plain"* ]]
	# Only the new commit's file: the three from the full range are not listed.
	run grep -c '^## ?\. ' "$DRAFT"
	[ "$status" -eq 0 ]
	[ "$output" = "1" ]
	grep -Fxq '## ?. new.txt' "$DRAFT"
	run grep -Fxq '## ?. a.txt' "$DRAFT"
	[ "$status" -ne 0 ]

	# And it validates against that same range, so the entry it holds is enough.
	printf '# Walkthrough\n\n## 1. new.txt\nwhy\n' >"$DRAFT"
	run git review walkthrough draft --build --delta feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"1 entry"* ]]
}
