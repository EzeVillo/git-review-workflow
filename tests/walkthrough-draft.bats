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
	[ "$output" = "3" ]
	grep -Fxq '## ?. a.txt' "$DRAFT"
	grep -Fxq '## ?. src/c.txt' "$DRAFT"
	grep -Fxq '## ?. src/café con espacio.js' "$DRAFT"
}

@test "draft leaves the working tree and the index untouched" {
	before="$(git status --porcelain)"
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[ "$(git status --porcelain)" = "$before" ]
	# And the draft is not a tracked path under any name.
	run git ls-files --error-unmatch .review/walkthrough.md
	[ "$status" -ne 0 ]
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
	[ "$output" = "3" ]
}

@test "a draft survives between invocations with its content intact" {
	git review walkthrough draft feature/plain
	fill_draft
	expected="$(cat "$DRAFT")"
	run git review config --porcelain -- feature/plain
	[ "$status" -eq 0 ]
	[ "$(cat "$DRAFT")" = "$expected" ]
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
	sed -i 's/^> key$/> key: because it matters/' "$DRAFT"
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"takes no value"* ]]
}

@test "draft --build orders by the numbers and renumbers 1..N" {
	git review walkthrough draft feature/plain
	fill_draft
	run git review walkthrough draft --build feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"3 entries (1 key)"* ]]
	# Renumbered into the reviewer's order, not the diff order.
	run grep '^## ' "$DRAFT"
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
