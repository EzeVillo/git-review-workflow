#!/usr/bin/env bats
#
# Tests for the draft progress pair: how many entries a reading order has, and
# how many of them are actually annotated.
#
# It is counted over the FILE and never crossed with the range, which is what
# makes it cheap and what makes it honest about a half-written draft. It is also
# not a promise: annotated == total says nothing about whether --build will pass.

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
	NS="$GITDIR/review-walkthrough"
	DRAFT="$NS/feature/x.md"
}

teardown() {
	rm -rf "$TMP"
}

# The <annotated>/<total> pair the CLI reports for <src>, as "A/T". Read off the
# porcelain record, never derived here: deriving it in the test would be testing
# the test's idea of the rule instead of the CLI's.
progress_of() {
	git review config --porcelain |
		awk -F'\t' -v want="$1" '$1 == "draft" && $2 == want { printf "%s/%s\n", $4, $5; exit }'
}

write_draft() {
	mkdir -p "$(dirname "$DRAFT")"
	cat >"$DRAFT"
}

# ── what counts as annotated ──────────────────────────────────────────────────

@test "an entry needs both a number and a why to count" {
	write_draft <<'EOF'
# Walkthrough

## ?. a.txt
this one has a why but no position

## 2. src/c.txt
<!-- why: -->
EOF
	# Two entries declared; neither is complete: the first has no number, the
	# second still carries the why placeholder.
	[ "$(progress_of feature/x)" = "0/2" ]

	write_draft <<'EOF'
# Walkthrough

## 1. a.txt
now it has both

## 2. src/c.txt
<!-- why: -->
EOF
	[ "$(progress_of feature/x)" = "1/2" ]

	write_draft <<'EOF'
# Walkthrough

## 1. a.txt
now it has both

## 2. src/c.txt
and so does this one
EOF
	[ "$(progress_of feature/x)" = "2/2" ]
}

@test "the key marker on its own is not a why" {
	write_draft <<'EOF'
# Walkthrough

## 1. a.txt
> key

## 2. src/c.txt
a real why
EOF
	# "> key" is a flag, not prose: an entry carrying only the marker is still
	# waiting for the sentence that says why it matters.
	[ "$(progress_of feature/x)" = "1/2" ]
}

@test "the key marker spelled any other way is not a why either" {
	write_draft <<'EOF'
# Walkthrough

## 1. a.txt
> Key

## 2. src/c.txt
>KEY
EOF
	# build accepts every one of these spellings and canonicalises them, so a
	# draft is full of them long before anything rewrites it. Counting only the
	# lower-case form reported both of these entries as annotated -- the pair the
	# panel draws then said the reading order was finished when neither entry
	# carries a single word of why.
	[ "$(progress_of feature/x)" = "0/2" ]
}

@test "reserved markers other than key do not count as a why either" {
	write_draft <<'EOF'
# Walkthrough

## 1. a.txt
> key
> at: 12

## 2. src/c.txt
a real why
EOF
	[ "$(progress_of feature/x)" = "1/2" ]
}

@test "a freshly generated skeleton reports zero of N" {
	run git review walkthrough draft feature/x
	[ "$status" -eq 0 ]
	# N is the number of files in the range PLUS the heads-up, and none of them
	# is annotated yet: every entry is "## ?." with its placeholder intact, and
	# so is the heads-up section.
	[ "$(progress_of feature/x)" = "0/3" ]
	run grep -c '^## ?\. ' "$DRAFT"
	[ "$output" = "2" ]
}

@test "annotated never reaches total while one mark is missing" {
	run git review walkthrough draft feature/x
	[ "$status" -eq 0 ]
	# Fill everything in but leave one entry unnumbered.
	awk '
		/^## \?\. src\/c.txt$/ { print; next }
		/^## \?\. / { n++; sub(/^## \?\. /, "## " n ". "); print; next }
		/^<!-- why: -->$/ { print "why prose"; next }
		{ print }
	' "$DRAFT" >"$DRAFT.x"
	mv "$DRAFT.x" "$DRAFT"
	# One entry of three units done: the other entry has no number and the
	# heads-up placeholder is untouched.
	[ "$(progress_of feature/x)" = "1/3" ]
}

# ── the heads-up is a unit of the pair ────────────────────────────────────────

@test "the heads-up placeholder counts against the pair" {
	write_draft <<'EOF'
# Walkthrough

## Heads-up

<!-- heads-up: the delicate parts of this PR, in a few lines. DELETE this whole
     comment and write it as plain text. -->

## 1. a.txt
why a
EOF
	# Two units, one done: the entry is annotated and the heads-up is not. build
	# refuses on exactly this, so a pair that read 1/1 would have drawn the row
	# as finished over a reading order that cannot start.
	[ "$(progress_of feature/x)" = "1/2" ]
	run git review walkthrough draft --build feature/x
	[ "$status" -eq 1 ]
	[[ "$output" == *"the heads-up placeholder is still there"* ]]
}

@test "prose in the heads-up completes it" {
	write_draft <<'EOF'
# Walkthrough

## Heads-up

the lock ordering in a.txt is the subtle part.

## 1. a.txt
why a

## 2. src/c.txt
why c
EOF
	[ "$(progress_of feature/x)" = "3/3" ]
	run git review walkthrough draft --build feature/x
	[ "$status" -eq 0 ]
}

@test "a deleted heads-up section is not a missing unit" {
	write_draft <<'EOF'
# Walkthrough

## 1. a.txt
why a

## 2. src/c.txt
why c
EOF
	# Deleting the whole section is legal -- an empty heads-up is worse than
	# none -- so the total drops instead of sitting one short of a number the
	# draft can no longer reach.
	[ "$(progress_of feature/x)" = "2/2" ]
	run git review walkthrough draft --build feature/x
	[ "$status" -eq 0 ]
}

@test "a heads-up heading with nothing under it counts as deleted" {
	write_draft <<'EOF'
# Walkthrough

## Heads-up

## 1. a.txt
why a

## 2. src/c.txt
why c
EOF
	# build accepts the bare heading, so the pair has to as well: reporting 2/3
	# here would gray out a Validate and start that was going to succeed.
	[ "$(progress_of feature/x)" = "2/2" ]
	run git review walkthrough draft --build feature/x
	[ "$status" -eq 0 ]
}

@test "a heads-up placeholder left without its heading still counts" {
	write_draft <<'EOF'
# Walkthrough

<!-- heads-up: deleted the heading and left the comment behind -->

## 1. a.txt
why a
EOF
	# build looks for the comment over the whole preamble, not inside the
	# section, and the pair follows it there.
	[ "$(progress_of feature/x)" = "1/2" ]
	run git review walkthrough draft --build feature/x
	[ "$status" -eq 1 ]
	[[ "$output" == *"the heads-up placeholder is still there"* ]]
}

@test "a why that quotes the placeholder is not an unfilled heads-up" {
	write_draft <<'EOF'
# Walkthrough

## 1. a.txt
documenting the format here: the skeleton writes
<!-- heads-up: ... -->
and the author replaces it.

## 2. src/c.txt
why c
EOF
	# Same confinement build uses: quoting a placeholder inside a why is
	# ordinary prose, and counting it would gray out a start that works.
	[ "$(progress_of feature/x)" = "2/2" ]
	run git review walkthrough draft --build feature/x
	[ "$status" -eq 0 ]
}

# ── counted over the file, not over the range ─────────────────────────────────

@test "progress is counted over the file, never crossed with the range" {
	write_draft <<'EOF'
# Walkthrough

## 1. a.txt
why a

## 2. src/c.txt
why c

## 3. gone.txt
a file the PR does not touch
EOF
	# Three entries, three annotated: the count is about the file.
	[ "$(progress_of feature/x)" = "3/3" ]
	# And the mismatch is still the validation's business, not the counter's.
	run git review walkthrough draft --build feature/x
	[ "$status" -eq 1 ]
	[[ "$output" == *"in the walkthrough but not changed in the PR: gone.txt"* ]]
}

@test "annotated equal to total promises nothing about --build" {
	write_draft <<'EOF'
# Walkthrough

## 1. a.txt
why a

## 2. a.txt
the same path twice
EOF
	[ "$(progress_of feature/x)" = "2/2" ]
	run git review walkthrough draft --build feature/x
	[ "$status" -eq 1 ]
	[[ "$output" == *"duplicate paths in walkthrough"* ]]
}

# ── cost ──────────────────────────────────────────────────────────────────────

@test "the number of awk invocations does not grow with the number of drafts" {
	# The budget this verb runs under: it is re-invoked on every panel refresh,
	# and one process per draft is the fault that made walk_entry_fields exist.
	# Counted with a stub on the PATH rather than with timings, so the assertion
	# is about the shape of the code and not about the machine it ran on.
	stub="$TMP/stub"
	mkdir -p "$stub"
	realawk="$(command -v awk)"
	cat >"$stub/awk" <<EOF
#!/bin/sh
echo x >>"$TMP/awk.count"
exec "$realawk" "\$@"
EOF
	chmod +x "$stub/awk"

	one_draft_awks() {
		: >"$TMP/awk.count"
		PATH="$stub:$PATH" git review config --porcelain >/dev/null
		grep -c . "$TMP/awk.count"
	}

	for b in one two three; do
		git switch --quiet develop
		git switch --quiet -c "feature/$b"
		printf '%s\n' "$b" >"$b.txt"
		git add -A
		git commit --quiet -m "$b"
		git push --quiet -u origin "feature/$b"
	done
	git switch --quiet develop

	git review walkthrough draft feature/one >/dev/null
	with_one="$(one_draft_awks)"
	git review walkthrough draft feature/two >/dev/null
	git review walkthrough draft feature/three >/dev/null
	with_three="$(one_draft_awks)"

	[ "$with_one" -eq "$with_three" ]
}
