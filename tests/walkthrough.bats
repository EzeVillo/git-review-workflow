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
# three PR files, with a heads-up preamble.
write_unordered() {
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## Heads-up

the token lifetime changed

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
	# Byte-for-byte expected output: the heading, the author's preamble, then the
	# entries in author-number order, renumbered 1..N, each why body trimmed with a
	# single trailing blank line.
	expected="$(printf '# Walkthrough\n\n## Heads-up\n\nthe token lifetime changed\n\n## 1. src/c.txt\nwhy c\n\n## 2. a.txt\nwhy a\n\n## 3. b.txt\nwhy b\n\n')"
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
	# order, to also prove reordering), delete each why-comment replacing the whole
	# line with prose, and drop the heads-up section (this PR has nothing delicate).
	sed -e 's/^## ?\. a\.txt$/## 2. a.txt/' \
		-e 's/^## ?\. b\.txt$/## 3. b.txt/' \
		-e 's|^## ?\. src/c\.txt$|## 1. src/c.txt|' \
		-e 's/^<!-- why: -->$/looks fine/' \
		-e '/^## Heads-up$/,/-->/d' \
		.review/walkthrough.md >.review/wt.tmp
	mv .review/wt.tmp .review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	# build strips the intro and produces the canonical ordered file.
	expected="$(printf '# Walkthrough\n\n## 1. src/c.txt\nlooks fine\n\n## 2. a.txt\nlooks fine\n\n## 3. b.txt\nlooks fine\n\n')"
	[ "$(cat .review/walkthrough.md)" = "$expected" ]
	! grep -q 'PLACEHOLDERS' .review/walkthrough.md
}

# ── heads-up preamble ─────────────────────────────────────────────────────────

@test "init writes a Heads-up section with its placeholder" {
	run git review walkthrough init
	[ "$status" -eq 0 ]
	grep -q '^## Heads-up$' .review/walkthrough.md
	grep -q '<!-- heads-up:' .review/walkthrough.md
	# The heads-up sits above the entries, where it is read first.
	head="$(grep -n '^## Heads-up$' .review/walkthrough.md | cut -d: -f1)"
	first="$(grep -n '^## ?\. ' .review/walkthrough.md | head -n 1 | cut -d: -f1)"
	[ "$head" -lt "$first" ]
}

@test "build keeps the authored heads-up and drops the skeleton instructions" {
	# The realistic loop: fill in the heads-up rather than deleting it.
	git review walkthrough init
	awk '/^<!-- heads-up/ { skip = 1; print "session tokens now expire; anything caching them is suspect"; next }
	     skip { if (/-->/) skip = 0; next }
	     { print }' .review/walkthrough.md >.review/wt.tmp
	mv .review/wt.tmp .review/walkthrough.md
	sed -e 's/^## ?\. a\.txt$/## 1. a.txt/' \
		-e 's/^## ?\. b\.txt$/## 2. b.txt/' \
		-e 's|^## ?\. src/c\.txt$|## 3. src/c.txt|' \
		-e 's/^<!-- why: -->$/looks fine/' \
		.review/walkthrough.md >.review/wt.tmp
	mv .review/wt.tmp .review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	expected="$(printf '# Walkthrough\n\n## Heads-up\n\nsession tokens now expire; anything caching them is suspect\n\n## 1. a.txt\nlooks fine\n\n## 2. b.txt\nlooks fine\n\n## 3. src/c.txt\nlooks fine\n\n')"
	[ "$(cat .review/walkthrough.md)" = "$expected" ]
}

@test "build fails on a leftover heads-up placeholder without modifying the file" {
	mkdir -p .review
	printf '# Walkthrough\n\n## Heads-up\n\n<!-- heads-up: the delicate parts -->\n\n## 1. a.txt\nx\n\n## 2. b.txt\ny\n\n## 3. src/c.txt\nz\n' >.review/walkthrough.md
	before="$(cat .review/walkthrough.md)"
	run git review walkthrough build
	[ "$status" -ne 0 ]
	[[ "$output" == *"heads-up placeholder is still there"* ]]
	[ "$(cat .review/walkthrough.md)" = "$before" ]
}

@test "build takes a why quoting the placeholder literals as prose, not as unfilled" {
	# Writing about the walkthrough format is ordinary PR prose: a why that quotes
	# "<!-- heads-up" or "<!-- why" mid-line must build, and must survive verbatim.
	mkdir -p .review
	printf '# Walkthrough\n\n## Heads-up\n\nthe guards are greps; watch the anchoring\n\n## 1. a.txt\nthe build guard for the `<!-- heads-up: ... -->` placeholder\n\n## 2. b.txt\nand the one for `<!-- why: -->`, same shape\n\n## 3. src/c.txt\nz\n' >.review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" == *"3 entries, ordered and renumbered"* ]]
	expected="$(printf '# Walkthrough\n\n## Heads-up\n\nthe guards are greps; watch the anchoring\n\n## 1. a.txt\nthe build guard for the `<!-- heads-up: ... -->` placeholder\n\n## 2. b.txt\nand the one for `<!-- why: -->`, same shape\n\n## 3. src/c.txt\nz\n\n')"
	[ "$(cat .review/walkthrough.md)" = "$expected" ]
	# The quoted literals are now committed prose: rebuilding must not trip either.
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[ "$(cat .review/walkthrough.md)" = "$expected" ]
}

@test "build still fails when a placeholder literal opens a line inside a why" {
	# The anchored guard keeps its teeth where it matters: an unreplaced why
	# comment is a line of its own, wherever the author left it.
	mkdir -p .review
	printf '# Walkthrough\n\n## 1. a.txt\nx\n\n## 2. b.txt\n<!-- why: -->\n\n## 3. src/c.txt\nz\n' >.review/walkthrough.md
	before="$(cat .review/walkthrough.md)"
	run git review walkthrough build
	[ "$status" -ne 0 ]
	[[ "$output" == *"unfilled why-comments remain"* ]]
	[ "$(cat .review/walkthrough.md)" = "$before" ]
}

@test "build drops a Heads-up heading left empty" {
	# Deleting the placeholder without writing anything must not leave a bare
	# heading behind: an empty section is worse than none.
	mkdir -p .review
	printf '# Walkthrough\n\n## Heads-up\n\n## 1. a.txt\nx\n\n## 2. b.txt\ny\n\n## 3. src/c.txt\nz\n' >.review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	expected="$(printf '# Walkthrough\n\n## 1. a.txt\nx\n\n## 2. b.txt\ny\n\n## 3. src/c.txt\nz\n\n')"
	[ "$(cat .review/walkthrough.md)" = "$expected" ]
}

# ── the "> key" marker ────────────────────────────────────────────────────────

@test "init explains the key marker in its instructions" {
	run git review walkthrough init
	[ "$status" -eq 0 ]
	grep -q '"> key"' .review/walkthrough.md
}

@test "build keeps the key marker, hoists it to the top of the why and counts it" {
	mkdir -p .review
	printf '# Walkthrough\n\n## 1. a.txt\nthe core change\n> key\n\n## 2. b.txt\nmechanical rename\n\n## 3. src/c.txt\n> key\nnew helper\n' >.review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" == *"3 entries (2 key)"* ]]
	# Canonical output: the marker always leads the body, wherever it was written.
	expected="$(printf '# Walkthrough\n\n## 1. a.txt\n> key\nthe core change\n\n## 2. b.txt\nmechanical rename\n\n## 3. src/c.txt\n> key\nnew helper\n\n')"
	[ "$(cat .review/walkthrough.md)" = "$expected" ]
}

@test "build --check reports the key count and writes nothing" {
	mkdir -p .review
	printf '# Walkthrough\n\n## 1. a.txt\n> key\nthe core change\n\n## 2. b.txt\ny\n\n## 3. src/c.txt\nz\n' >.review/walkthrough.md
	before="$(cat .review/walkthrough.md)"
	run git review walkthrough build --check
	[ "$status" -eq 0 ]
	[[ "$output" == *"3 entries (1 key)"* ]]
	[ "$(cat .review/walkthrough.md)" = "$before" ]
}

@test "build reports no key count when nothing is marked" {
	mkdir -p .review
	write_unordered
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" == *"3 entries, ordered and renumbered"* ]]
	[[ "$output" != *"key)"* ]]
}

@test "build rejects a key marker written with a value" {
	mkdir -p .review
	printf '# Walkthrough\n\n## 1. a.txt\n> key: it touches the token\n\n## 2. b.txt\ny\n\n## 3. src/c.txt\nz\n' >.review/walkthrough.md
	before="$(cat .review/walkthrough.md)"
	run git review walkthrough build
	[ "$status" -ne 0 ]
	[[ "$output" == *"takes no value"* ]]
	[ "$(cat .review/walkthrough.md)" = "$before" ]
}

@test "build normalizes a key marker written with odd spacing or case" {
	# Near-misses are recognised and rewritten canonically, never left to leak
	# into the why as literal prose the reviewer would see.
	mkdir -p .review
	printf '# Walkthrough\n\n## 1. a.txt\n>key\nthe core change\n\n## 2. b.txt\nmechanical rename\n\n## 3. src/c.txt\n>  Key\nnew helper\n' >.review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" == *"3 entries (2 key)"* ]]
	expected="$(printf '# Walkthrough\n\n## 1. a.txt\n> key\nthe core change\n\n## 2. b.txt\nmechanical rename\n\n## 3. src/c.txt\n> key\nnew helper\n\n')"
	[ "$(cat .review/walkthrough.md)" = "$expected" ]
	# The marker reaches the reviewer only in its canonical spelling: no variant
	# survives anywhere in the built file.
	run grep -c '^> key$' .review/walkthrough.md
	[ "$output" = "2" ]
	! grep -q 'Key' .review/walkthrough.md
	! grep -q '^>key' .review/walkthrough.md
}

@test "build rejects a key marker given a value in any spelling" {
	mkdir -p .review
	printf '# Walkthrough\n\n## 1. a.txt\n>Key: it touches the token\n\n## 2. b.txt\ny\n\n## 3. src/c.txt\nz\n' >.review/walkthrough.md
	before="$(cat .review/walkthrough.md)"
	run git review walkthrough build
	[ "$status" -ne 0 ]
	[[ "$output" == *"takes no value"* ]]
	[ "$(cat .review/walkthrough.md)" = "$before" ]
}

@test "build leaves a quoted line that merely starts with key-like prose alone" {
	# The value guard must not fire on a blockquote whose first word only looks
	# like the marker: that is prose, and it builds and survives untouched.
	mkdir -p .review
	printf '# Walkthrough\n\n## 1. a.txt\n> keyword lookups are cached now\n\n## 2. b.txt\ny\n\n## 3. src/c.txt\nz\n' >.review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" != *"key)"* ]]
	expected="$(printf '# Walkthrough\n\n## 1. a.txt\n> keyword lookups are cached now\n\n## 2. b.txt\ny\n\n## 3. src/c.txt\nz\n\n')"
	[ "$(cat .review/walkthrough.md)" = "$expected" ]
}

@test "build notes that marking every entry defeats the marker but still builds" {
	mkdir -p .review
	printf '# Walkthrough\n\n## 1. a.txt\n> key\nx\n\n## 2. b.txt\n> key\ny\n\n## 3. src/c.txt\n> key\nz\n' >.review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" == *"every entry is marked"* ]]
	expected="$(printf '# Walkthrough\n\n## 1. a.txt\n> key\nx\n\n## 2. b.txt\n> key\ny\n\n## 3. src/c.txt\n> key\nz\n\n')"
	[ "$(cat .review/walkthrough.md)" = "$expected" ]
}

@test "build suggests marking something on a large walkthrough with no key entry" {
	# Six changed files, none marked: past the point where reading order alone is
	# enough guidance.
	for f in d e f; do
		printf '%s\n' "$f" >"$f.txt"
	done
	git add d.txt e.txt f.txt
	git commit --quiet -m more
	mkdir -p .review
	printf '# Walkthrough\n\n## 1. a.txt\nx\n\n## 2. b.txt\ny\n\n## 3. src/c.txt\nz\n\n## 4. d.txt\nd\n\n## 5. e.txt\ne\n\n## 6. f.txt\nf\n' >.review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" == *"no entry is marked"* ]]
	grep -q '^## 6\. f.txt$' .review/walkthrough.md
}

@test "build stays quiet about the marker on a small unmarked walkthrough" {
	mkdir -p .review
	write_unordered
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" != *"> key"* ]]
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

# ── uncommitted-changes diagnostics ─────────────────────────────────────────────

@test "init refuses with a commit hint when the PR changes are only uncommitted" {
	# A branch sitting on the base commit, its changes only in the working tree.
	git switch --quiet -c p develop
	printf 'a1\nlocal\n' >a.txt
	run git review walkthrough init
	[ "$status" -ne 0 ]
	[[ "$output" == *"uncommitted changes"* ]]
	[[ "$output" == *"commit the PR first"* ]]
	# It refused before writing anything.
	[ ! -f .review/walkthrough.md ]
}

@test "init on a branch at base with a clean tree keeps the plain no-changes error" {
	# No uncommitted work: the original message stands, no commit hint.
	git switch --quiet -c p develop
	run git review walkthrough init
	[ "$status" -ne 0 ]
	[[ "$output" == *"nothing to walk through"* ]]
	[[ "$output" != *"uncommitted changes"* ]]
}

@test "init warns about uncommitted changes but still writes the skeleton" {
	# feature/x already carries committed PR changes; add an uncommitted one too.
	printf 'a1\na2\nlocal\n' >a.txt
	run git review walkthrough init
	[ "$status" -eq 0 ]
	[ -f .review/walkthrough.md ]
	# The three committed files are listed and the note fired.
	run grep -c '^## ?\. ' .review/walkthrough.md
	[ "$output" = "3" ]
}

@test "init warning names uncommitted changes on stderr" {
	printf 'a1\na2\nlocal\n' >a.txt
	run git review walkthrough init
	[ "$status" -eq 0 ]
	[[ "$output" == *"uncommitted changes"* ]]
}

@test "build refuses with a commit hint when the PR changes are only uncommitted" {
	# The merge-base guard fires before the walkthrough is even read.
	git switch --quiet -c p develop
	printf 'a1\nlocal\n' >a.txt
	mkdir -p .review
	printf '# Walkthrough\n\n## 1. a.txt\nwhy\n' >.review/walkthrough.md
	run git review walkthrough build
	[ "$status" -ne 0 ]
	[[ "$output" == *"uncommitted changes"* ]]
	[[ "$output" == *"commit the PR first"* ]]
}

@test "build warns about uncommitted changes but still builds the file" {
	mkdir -p .review
	write_unordered
	# An uncommitted edit to an already-committed reviewable file: no drift, warn only.
	printf 'a1\na2\nlocal\n' >a.txt
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" == *"uncommitted changes"* ]]
	expected="$(printf '# Walkthrough\n\n## Heads-up\n\nthe token lifetime changed\n\n## 1. src/c.txt\nwhy c\n\n## 2. a.txt\nwhy a\n\n## 3. b.txt\nwhy b\n\n')"
	[ "$(cat .review/walkthrough.md)" = "$expected" ]
}

@test "editing only the sidecar does not count as an uncommitted change" {
	# A dirty .review/walkthrough.md is normal while authoring: no warning.
	run git review walkthrough init
	[ "$status" -eq 0 ]
	[[ "$output" != *"uncommitted changes"* ]]
}
