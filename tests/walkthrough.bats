#!/usr/bin/env bats
#
# Tests for the author-side verb: git review walkthrough (init / build).
#
# The PR (feature/x) changes three files vs develop: a.txt and b.txt (edited) and
# src/c.txt (added). The author runs walkthrough while on feature/x.

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"

	git config --global user.email t@example.com
	git config --global user.name tester
	git config --global init.defaultBranch develop
	git config --global core.autocrlf false

	WORK="$TMP/work"
	git init --quiet "$WORK"
	cd "$WORK"
	git config reviewworkflow.base develop

	printf 'a1\n' >a.txt
	printf 'b1\n' >b.txt
	git add a.txt b.txt
	git commit --quiet -m base
	git branch -M develop

	git switch --quiet -c feature/x
	printf 'a1\na2\n' >a.txt
	printf 'b1\nb2\n' >b.txt
	mkdir -p src
	printf 'hello\n' >src/c.txt
	git add a.txt b.txt src/c.txt
	git commit --quiet -m c1
}

teardown() {
	rm -rf "$TMP"
}

# ── init ──────────────────────────────────────────────────────────────────────

@test "init lists exactly the changed files, as ?. skeleton entries" {
	run git review walkthrough init
	[ "$status" -eq 0 ]
	[ -f .review/walkthrough.md ]
	# Exactly the three changed paths appear as skeleton entries, no more, no less.
	run grep -c '^## ?\. ' .review/walkthrough.md
	[ "$output" = "3" ]
	grep -q '^## ?\. a.txt$' .review/walkthrough.md
	grep -q '^## ?\. b.txt$' .review/walkthrough.md
	grep -q '^## ?\. src/c.txt$' .review/walkthrough.md
	# Each entry carries a why placeholder.
	run grep -c '^<!-- why: -->$' .review/walkthrough.md
	[ "$output" = "3" ]
}

@test "init excludes the .review/ sidecar itself from the listing" {
	# A prior walkthrough committed to the PR must never list itself on regen.
	mkdir -p .review
	printf 'stale\n' >.review/walkthrough.md
	git add .review/walkthrough.md
	git commit --quiet -m "old walkthrough"
	run git review walkthrough init --force
	[ "$status" -eq 0 ]
	run grep -c '\.review/' .review/walkthrough.md
	# grep -c prints 0 and exits 1 when nothing matches; assert the count is 0.
	[ "$output" = "0" ]
}

@test "init refuses to overwrite an existing walkthrough without --force" {
	git review walkthrough init
	before="$(cat .review/walkthrough.md)"
	run git review walkthrough init
	[ "$status" -ne 0 ]
	[[ "$output" == *"already exists"* ]]
	# The existing file is untouched.
	[ "$(cat .review/walkthrough.md)" = "$before" ]
}

@test "init --force overwrites an existing walkthrough" {
	git review walkthrough init
	printf 'garbage\n' >.review/walkthrough.md
	run git review walkthrough init --force
	[ "$status" -eq 0 ]
	grep -q '^## ?\. a.txt$' .review/walkthrough.md
}

@test "init with no base configured and no --base fails" {
	git config --unset reviewworkflow.base
	run git review walkthrough init
	[ "$status" -ne 0 ]
	[[ "$output" == *"no base set"* ]]
	[ ! -f .review/walkthrough.md ]
}

@test "init --base overrides the configured base" {
	git config reviewworkflow.base nonexistent-branch
	run git review walkthrough init --base develop
	[ "$status" -eq 0 ]
	run grep -c '^## ?\. ' .review/walkthrough.md
	[ "$output" = "3" ]
}

# ── build ─────────────────────────────────────────────────────────────────────

# Write a filled-in, deliberately out-of-order walkthrough covering exactly the
# three PR files.
write_unordered() {
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

Intro prose the parser ignores.

## 2. a.txt
why a

## 3. b.txt
why b

## 1. src/c.txt
why c
EOF
}

@test "build orders by number, renumbers 1..N and produces the exact expected file" {
	mkdir -p .review
	write_unordered
	run git review walkthrough build
	[ "$status" -eq 0 ]
	# Byte-for-byte expected output: fixed intro, entries in author-number order,
	# renumbered 1..N, each why body trimmed with a single trailing blank line.
	expected="$(printf '# Walkthrough\n\n## 1. src/c.txt\nwhy c\n\n## 2. a.txt\nwhy a\n\n## 3. b.txt\nwhy b\n\n')"
	[ "$(cat .review/walkthrough.md)" = "$expected" ]
}

@test "build succeeds on a real init skeleton filled in place (intro does not trip validation)" {
	# The end-to-end author loop: the intro comment init writes must never be
	# mistaken for an unfilled entry or why-placeholder by build's greps.
	run git review walkthrough init
	[ "$status" -eq 0 ]
	# The intro is present and carries the guidance text.
	grep -q 'PLACEHOLDERS' .review/walkthrough.md
	# Edit in place exactly as the instructions say: number each "?" (out of
	# order, to also prove reordering), and delete each why-comment, replacing
	# the whole line with prose.
	sed -e 's/^## ?\. a\.txt$/## 2. a.txt/' \
		-e 's/^## ?\. b\.txt$/## 3. b.txt/' \
		-e 's|^## ?\. src/c\.txt$|## 1. src/c.txt|' \
		-e 's/^<!-- why: -->$/looks fine/' \
		.review/walkthrough.md >.review/wt.tmp
	mv .review/wt.tmp .review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	# build strips the intro and produces the canonical ordered file.
	expected="$(printf '# Walkthrough\n\n## 1. src/c.txt\nlooks fine\n\n## 2. a.txt\nlooks fine\n\n## 3. b.txt\nlooks fine\n\n')"
	[ "$(cat .review/walkthrough.md)" = "$expected" ]
	! grep -q 'PLACEHOLDERS' .review/walkthrough.md
}

@test "build --check on a valid walkthrough passes and writes nothing" {
	mkdir -p .review
	write_unordered
	before="$(cat .review/walkthrough.md)"
	run git review walkthrough build --check
	[ "$status" -eq 0 ]
	[[ "$output" == *"walkthrough ok"* ]]
	# --check never rewrites the file (still unordered).
	[ "$(cat .review/walkthrough.md)" = "$before" ]
}

@test "build --check fails on a leftover ?. placeholder without modifying the file" {
	mkdir -p .review
	printf '# Walkthrough\n\n## ?. a.txt\nx\n\n## 2. b.txt\ny\n\n## 3. src/c.txt\nz\n' >.review/walkthrough.md
	before="$(cat .review/walkthrough.md)"
	run git review walkthrough build --check
	[ "$status" -ne 0 ]
	[[ "$output" == *"unfilled entries"* ]]
	[ "$(cat .review/walkthrough.md)" = "$before" ]
}

@test "build --check fails on a leftover why-comment" {
	mkdir -p .review
	printf '# Walkthrough\n\n## 1. a.txt\n<!-- why: -->\n\n## 2. b.txt\ny\n\n## 3. src/c.txt\nz\n' >.review/walkthrough.md
	run git review walkthrough build --check
	[ "$status" -ne 0 ]
	[[ "$output" == *"unfilled why-comments"* ]]
}

@test "build --check fails on a duplicate path" {
	mkdir -p .review
	printf '# Walkthrough\n\n## 1. a.txt\nx\n\n## 2. a.txt\ny\n\n## 3. src/c.txt\nz\n' >.review/walkthrough.md
	run git review walkthrough build --check
	[ "$status" -ne 0 ]
	[[ "$output" == *"duplicate path"* ]]
	[[ "$output" == *"a.txt"* ]]
}

@test "build --check fails on drift when a changed file is missing from the walkthrough" {
	mkdir -p .review
	# b.txt is changed in the PR but not listed.
	printf '# Walkthrough\n\n## 1. a.txt\nx\n\n## 2. src/c.txt\nz\n' >.review/walkthrough.md
	run git review walkthrough build --check
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing from the walkthrough"* ]]
	[[ "$output" == *"b.txt"* ]]
}

@test "build --check fails on drift when the walkthrough lists an unchanged file" {
	mkdir -p .review
	printf '# Walkthrough\n\n## 1. a.txt\nx\n\n## 2. b.txt\ny\n\n## 3. src/c.txt\nz\n\n## 4. nope.txt\nq\n' >.review/walkthrough.md
	run git review walkthrough build --check
	[ "$status" -ne 0 ]
	[[ "$output" == *"not changed in the PR"* ]]
	[[ "$output" == *"nope.txt"* ]]
}

@test "build without a walkthrough file fails" {
	run git review walkthrough build
	[ "$status" -ne 0 ]
	[[ "$output" == *"not found"* ]]
}

@test "build is idempotent: building an already-built file leaves it unchanged" {
	mkdir -p .review
	write_unordered
	git review walkthrough build
	first="$(cat .review/walkthrough.md)"
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[ "$(cat .review/walkthrough.md)" = "$first" ]
}

@test "build rejects --base and init rejects --check (flag/subcommand mismatch)" {
	mkdir -p .review
	write_unordered
	run git review walkthrough build --base develop
	[ "$status" -ne 0 ]
	[[ "$output" == *"only"* ]]
	run git review walkthrough init --check
	[ "$status" -ne 0 ]
	[[ "$output" == *"only"* ]]
}
