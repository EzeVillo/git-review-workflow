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

@test "writing a draft leaves no temporary file behind" {
	git review walkthrough draft feature/plain
	[ -f "$DRAFT" ]
	# The skeleton is written to "<target>.tmp.$$" and moved into place. Anything
	# else left in the namespace is litter nobody collects: walk_draft_list only
	# matches *.md, clean is deliberately hands-off in there, and forget --draft
	# only knows names it can spell.
	run find "$(dirname "$DRAFT")" -name '*.tmp.*'
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
	run git show origin/feature/annotated:.review/walkthrough.md
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
