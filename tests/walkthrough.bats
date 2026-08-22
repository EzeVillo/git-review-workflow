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

# The built file with the instruction block taken out: exactly the bytes every
# expectation below was written against before the block existed. The block is
# emitted between the "# Walkthrough" heading and the preamble, and its two
# endpoints are object SHAs, so it cannot be spelled out in an expected string
# here; its own content is asserted in tests/walkthrough-prompt-block.bats.
# The blank line that follows the closing marker goes with it, so what is left is
# the heading, a blank line and the preamble -- the old shape exactly.
built_body() {
	awk '
		index($0, "<!-- git-review-range:") == 1 { skip = 1; next }
		skip {
			if (index($0, "-->")) { skip = 0; drop = 1 }
			next
		}
		drop && $0 == "" { drop = 0; next }
		{ drop = 0; print }
	' "${1:-.review/walkthrough.md}"
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
	# The skeleton instructions may mention .review/walkthrough-guide.md; only
	# entry headings count as "listed".
	mkdir -p .review
	printf 'stale\n' >.review/walkthrough.md
	git add .review/walkthrough.md
	git commit --quiet -m "old walkthrough"
	run git review walkthrough init --force
	[ "$status" -eq 0 ]
	run grep -c '^## ?\. \.review/' .review/walkthrough.md
	# grep -c prints 0 and exits 1 when nothing matches; assert the count is 0.
	[ "$output" = "0" ]
}

@test "build's drift check never flags the committed sidecar itself as missing (FR-022)" {
	# Every other reader of "what does this review touch" now includes the
	# sidecar once it is committed (FR-020) — build's drift check is the one
	# place that must keep excluding it, or every author's first build after
	# committing their own walkthrough would fail on itself.
	mkdir -p .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. a.txt
why a

## 2. b.txt
why b

## 3. src/c.txt
why c
EOF
	git add .review/walkthrough.md
	git commit --quiet -m "commit walkthrough"
	run git review walkthrough build --check
	[ "$status" -eq 0 ]
	[[ "$output" == *"walkthrough ok"* ]]
	[[ "$output" != *"missing from the walkthrough"* ]]
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
	[ "$(built_body)" = "$expected" ]
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
	[ "$(built_body)" = "$expected" ]
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
	[ "$(built_body)" = "$expected" ]
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
	[ "$(built_body)" = "$expected" ]
	# The quoted literals are now committed prose: rebuilding must not trip either.
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[ "$(built_body)" = "$expected" ]
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
	[ "$(built_body)" = "$expected" ]
}

# ── the "> key" marker ────────────────────────────────────────────────────────

@test "init closes with the author's own note and build command" {
	run git review walkthrough init
	[ "$status" -eq 0 ]
	# The skeleton body is shared with the reviewer's draft, but its closing note is
	# not: the command that validates it differs, and so does what "uncommitted
	# changes" means. Pinned from the author's end too, so switching the two
	# passages can never hand the author the reviewer's copy.
	grep -q 'Then validate and write with:  git review walkthrough build -->' .review/walkthrough.md
	grep -q 'Commit the PR before authoring it' .review/walkthrough.md
	! grep -q 'walkthrough draft' .review/walkthrough.md
}

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
	[ "$(built_body)" = "$expected" ]
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
	[ "$(built_body)" = "$expected" ]
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
	[ "$(built_body)" = "$expected" ]
}

@test "build notes that marking every entry defeats the marker but still builds" {
	mkdir -p .review
	printf '# Walkthrough\n\n## 1. a.txt\n> key\nx\n\n## 2. b.txt\n> key\ny\n\n## 3. src/c.txt\n> key\nz\n' >.review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" == *"every entry is marked"* ]]
	expected="$(printf '# Walkthrough\n\n## 1. a.txt\n> key\nx\n\n## 2. b.txt\n> key\ny\n\n## 3. src/c.txt\n> key\nz\n\n')"
	[ "$(built_body)" = "$expected" ]
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

# ── CRLF line endings ─────────────────────────────────────────────────────────

# Write the walkthrough on stdin to the sidecar with CRLF endings, the way an
# editor (or a checkout) on Windows leaves it, and assert the file on disk really
# carries the CRs. The proof deliberately avoids awk: the gawk that ships with Git
# for Windows reads in text mode and eats the CR, which is exactly why this class
# of bug is invisible there. wc -c counts bytes and is honest on every platform.
# On Windows the assertions below therefore hold even without the strip; the teeth
# of these tests are on Linux and macOS, where the CR reaches the parsers.
write_crlf() {
	mkdir -p .review
	cat >"$TMP/wt.lf"
	while IFS= read -r line; do printf '%s\r\n' "$line"; done \
		<"$TMP/wt.lf" >.review/walkthrough.md
	lf_bytes=$(($(wc -c <"$TMP/wt.lf")))
	lf_lines=$(($(wc -l <"$TMP/wt.lf")))
	crlf_bytes=$(($(wc -c <.review/walkthrough.md)))
	[ "$lf_lines" -gt 0 ]
	[ "$crlf_bytes" -eq "$((lf_bytes + lf_lines))" ]
}

@test "build accepts a CRLF walkthrough, sees its key marker and rewrites it as LF" {
	write_crlf <<'EOF'
# Walkthrough

## Heads-up

the token lifetime changed

## 2. a.txt
> key
why a

## 3. b.txt
why b

## 1. src/c.txt
why c
EOF
	run git review walkthrough build
	[ "$status" -eq 0 ]
	# A CR on the paths used to make both sides of the drift comparison disjoint,
	# so build reported the same three files as missing AND as extra.
	[[ "$output" != *"missing from the walkthrough"* ]]
	[[ "$output" != *"not changed in the PR"* ]]
	# The marker survives: a CR made "> key" fail the anchored key regex.
	[[ "$output" == *"3 entries (1 key), ordered and renumbered"* ]]
	# The rewrite is byte-for-byte the canonical LF file — no CR anywhere, so the
	# author's build heals the sidecar for every reviewer.
	# A surviving CR would show up inside this string comparison ($(cat) strips
	# trailing newlines, never carriage returns), so equality proves LF endings.
	expected="$(printf '# Walkthrough\n\n## Heads-up\n\nthe token lifetime changed\n\n## 1. src/c.txt\nwhy c\n\n## 2. a.txt\n> key\nwhy a\n\n## 3. b.txt\nwhy b\n\n')"
	[ "$(built_body)" = "$expected" ]
}

@test "build --check passes on a CRLF walkthrough and leaves it untouched" {
	write_crlf <<'EOF'
# Walkthrough

## 1. a.txt
why a

## 2. b.txt
why b

## 3. src/c.txt
why c
EOF
	cp .review/walkthrough.md "$TMP/before.md"
	run git review walkthrough build --check
	[ "$status" -eq 0 ]
	[[ "$output" == *"walkthrough ok: 3 entries, in sync with the PR"* ]]
	# --check never writes: the file is still byte-for-byte the CRLF one.
	cmp -s "$TMP/before.md" .review/walkthrough.md
}

@test "build still reports real drift on a CRLF walkthrough" {
	# The strip must not paper over genuine drift: b.txt is changed by the PR and
	# absent here, and d.txt is listed but unchanged. Each side names its own files.
	write_crlf <<'EOF'
# Walkthrough

## 1. a.txt
why a

## 2. src/c.txt
why c

## 3. d.txt
why d
EOF
	run git review walkthrough build
	[ "$status" -ne 0 ]
	[[ "$output" == *"changed in the PR but missing from the walkthrough: b.txt"* ]]
	[[ "$output" == *"in the walkthrough but not changed in the PR: d.txt"* ]]
	# Neither side may name a file that belongs to the other.
	missing_line="$(printf '%s\n' "$output" | grep 'missing from the walkthrough')"
	extra_line="$(printf '%s\n' "$output" | grep 'not changed in the PR')"
	[[ "$missing_line" != *"d.txt"* ]]
	[[ "$extra_line" != *"b.txt"* ]]
	[[ "$extra_line" != *"a.txt"* ]]
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
	[ "$(built_body)" = "$expected" ]
}

@test "editing only the sidecar does not count as an uncommitted change" {
	# A dirty .review/walkthrough.md is normal while authoring: no warning.
	run git review walkthrough init
	[ "$status" -eq 0 ]
	[[ "$output" != *"uncommitted changes"* ]]
}

# ── non-ASCII paths ───────────────────────────────────────────────────────────

# Add a non-ASCII path to the PR and prove the hazard is live on this platform
# before anything is asserted about it: under git's default core.quotePath such a
# path comes out escaped and quoted ("src/caf\303\251.js"), so it can never equal
# the literal path an author writes in a walkthrough. Where git does not quote it
# the name never round-tripped through the filesystem and there is nothing to
# exercise, so the test skips instead of passing vacuously.
#
# The name is built from octal escapes rather than written literally so this file
# stays pure ASCII (the bats that runs on Windows CI is byte-fragile), and the
# character is one with no canonical decomposition, so macOS filesystem unicode
# normalisation cannot turn this into a flaky test. An accented name like
# src/cafe\303\251.js breaks, and is fixed, identically.
add_nonascii_file() {
	NONASCII="src/$(printf '\346\226\207\346\233\270').txt"
	mkdir -p src .review
	printf 'u\n' >"$NONASCII"
	git add "$NONASCII"
	git commit --quiet -m c2-add-nonascii
	quoted="$(git -c core.quotePath=true diff --name-only develop HEAD | grep -c '^"' || true)"
	[ "$quoted" -eq 1 ] || skip "this platform does not round-trip a non-ASCII path"
}

@test "init lists a non-ASCII path literally, not C-escaped" {
	add_nonascii_file
	run git review walkthrough init
	[ "$status" -eq 0 ]
	# The skeleton is the file the author edits: an escaped, quoted path there is
	# unreadable, and stops matching the moment they write the real one.
	grep -qxF "## ?. $NONASCII" .review/walkthrough.md
	# No entry may carry git's C-style quoting.
	run grep -c '^## ?\. "' .review/walkthrough.md
	[ "$output" = "0" ]
	# All four changed files are listed, exactly once each.
	run grep -c '^## ?\. ' .review/walkthrough.md
	[ "$output" = "4" ]
}

@test "init skeleton names no guide when neither is in force" {
	# The bullet used to name .review/walkthrough-guide.md whether it existed or
	# not. Five lines about a file that is not there is five lines of the
	# annotating agent's attention spent on nothing.
	run git review walkthrough init
	[ "$status" -eq 0 ]
	run grep -c 'Authoring guide' .review/walkthrough.md
	[ "$output" = "0" ]
}

@test "init skeleton names the shared guide when it is in force" {
	mkdir -p .review
	printf 'mark entry points as key\n' >.review/walkthrough-guide.md
	run git review walkthrough init
	[ "$status" -eq 0 ]
	grep -q 'Authoring guide for this repository' .review/walkthrough.md
	grep -q '\.review/walkthrough-guide\.md  (this repository, shared)' .review/walkthrough.md
	grep -qi 'cannot change this format' .review/walkthrough.md
	# One guide, so there is no precedence to declare.
	run grep -c 'BOTH apply' .review/walkthrough.md
	[ "$output" = "0" ]
}

@test "init skeleton names both guides and who wins" {
	mkdir -p .review
	printf 'team rules\n' >.review/walkthrough-guide.md
	printf 'my rules\n' >"$(git rev-parse --git-dir)/review-walkthrough-guide.md"
	run git review walkthrough init
	[ "$status" -eq 0 ]
	grep -q '\.review/walkthrough-guide\.md  (this repository, shared)' .review/walkthrough.md
	grep -q 'review-walkthrough-guide\.md  (the reviewer, private)' .review/walkthrough.md
	grep -q "BOTH apply, and where they disagree" .review/walkthrough.md
	grep -q "the reviewer's guide wins." .review/walkthrough.md
}

@test "init skeleton ignores a guide that holds only whitespace" {
	# Same rule as an empty draft: a file with nothing in it is not a set of
	# conventions, and naming it would send the agent to read blank lines.
	mkdir -p .review
	printf '   \n\t\n\n' >.review/walkthrough-guide.md
	run git review walkthrough init
	[ "$status" -eq 0 ]
	run grep -c 'Authoring guide' .review/walkthrough.md
	[ "$output" = "0" ]
}

@test "init notes how to create a guide when there is none" {
	run git review walkthrough init
	[ "$status" -eq 0 ]
	[[ "$output" == *"no authoring guide"* ]]
	[[ "$output" == *"git review walkthrough guide"* ]]
	[[ "$output" != *"in force"* ]]
}

@test "init notes the shared guide when it is in force" {
	mkdir -p .review
	printf '# team rules\nmark entry points as key\n' >.review/walkthrough-guide.md
	run git review walkthrough init
	[ "$status" -eq 0 ]
	[[ "$output" == *"authoring guide in force at .review/walkthrough-guide.md"* ]]
	[[ "$output" != *"no authoring guide"* ]]
}

@test "init notes both guides and the precedence between them" {
	mkdir -p .review
	printf 'team rules\n' >.review/walkthrough-guide.md
	printf 'my rules\n' >"$(git rev-parse --git-dir)/review-walkthrough-guide.md"
	run git review walkthrough init
	[ "$status" -eq 0 ]
	[[ "$output" == *"two authoring guides are in force"* ]]
	[[ "$output" == *"yours wins where they disagree"* ]]
}

@test "init says a guide is empty rather than telling you to create it" {
	mkdir -p .review
	: >.review/walkthrough-guide.md
	run git review walkthrough init
	[ "$status" -eq 0 ]
	[[ "$output" == *"exists but is empty"* ]]
	[[ "$output" != *"no authoring guide"* ]]
}

@test "build accepts a walkthrough naming a non-ASCII path" {
	add_nonascii_file
	cat >.review/walkthrough.md <<EOF
# Walkthrough

## 1. a.txt
why a

## 2. b.txt
why b

## 3. src/c.txt
why c

## 4. $NONASCII
> key
why u
EOF
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" == *"4 entries (1 key), ordered and renumbered"* ]]
	# The escaped path used to sit on one side of the drift comparison and the
	# literal one on the other, so build named the same file as missing AND extra.
	[[ "$output" != *"missing from the walkthrough"* ]]
	[[ "$output" != *"not changed in the PR"* ]]
	# The rewrite keeps the path literal and its marker attached.
	expected="$(printf '# Walkthrough\n\n## 1. a.txt\nwhy a\n\n## 2. b.txt\nwhy b\n\n## 3. src/c.txt\nwhy c\n\n## 4. %s\n> key\nwhy u\n\n' "$NONASCII")"
	[ "$(built_body)" = "$expected" ]
}

@test "build still reports real drift on a PR holding a non-ASCII path" {
	# The unescaping must not paper over drift: the non-ASCII file is changed by
	# the PR and absent from the walkthrough, and d.txt is listed but unchanged.
	add_nonascii_file
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. a.txt
why a

## 2. b.txt
why b

## 3. src/c.txt
why c

## 4. d.txt
why d
EOF
	run git review walkthrough build
	[ "$status" -ne 0 ]
	[[ "$output" == *"changed in the PR but missing from the walkthrough: $NONASCII"* ]]
	[[ "$output" == *"in the walkthrough but not changed in the PR: d.txt"* ]]
	# Named readably: no C-escaping survives into the diagnostic.
	[[ "$output" != *'\'* ]]
	# Neither side may name a file that belongs to the other.
	missing_line="$(printf '%s\n' "$output" | grep 'missing from the walkthrough')"
	extra_line="$(printf '%s\n' "$output" | grep 'not changed in the PR')"
	[[ "$missing_line" != *"d.txt"* ]]
	[[ "$extra_line" != *"$NONASCII"* ]]
}

# ── UTF-8 BOM ─────────────────────────────────────────────────────────────────

# Write the walkthrough on stdin to the sidecar behind a UTF-8 BOM — what Notepad,
# PowerShell's Out-File and PowerShell's > all put in front of a file by default —
# and prove the bytes really are there. The proof deliberately avoids awk: the
# whole point is that a reader must not depend on which awk sees the file first.
write_bom() {
	mkdir -p .review
	cat >"$TMP/wt.lf"
	{ printf '\357\273\277'; cat "$TMP/wt.lf"; } >.review/walkthrough.md
	lf_bytes=$(($(wc -c <"$TMP/wt.lf")))
	bom_bytes=$(($(wc -c <.review/walkthrough.md)))
	[ "$lf_bytes" -gt 0 ]
	[ "$bom_bytes" -eq "$((lf_bytes + 3))" ]
	[ "$(head -c 3 .review/walkthrough.md)" = "$(printf '\357\273\277')" ]
}

@test "build strips a UTF-8 BOM instead of baking it into the preamble" {
	write_bom <<'EOF'
# Walkthrough

## Heads-up

the token lifetime changed

## 1. a.txt
why a

## 2. b.txt
why b

## 3. src/c.txt
why c
EOF
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" == *"3 entries, ordered and renumbered"* ]]
	# The BOM used to hide "# Walkthrough" from the preamble reader, which copied
	# it into the heads-up — a second heading that survived every later rebuild.
	# A surviving BOM would break this comparison too ($(cat) strips trailing
	# newlines, never a leading BOM), so equality proves both.
	expected="$(printf '# Walkthrough\n\n## Heads-up\n\nthe token lifetime changed\n\n## 1. a.txt\nwhy a\n\n## 2. b.txt\nwhy b\n\n## 3. src/c.txt\nwhy c\n\n')"
	[ "$(built_body)" = "$expected" ]
	run grep -c '^# Walkthrough$' .review/walkthrough.md
	[ "$output" = "1" ]
	# Building again is a no-op, so nothing was baked in to resurface later.
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[ "$(built_body)" = "$expected" ]
}

@test "build strips a BOM from a walkthrough that opens with an entry" {
	write_bom <<'EOF'
## 1. a.txt
why a

## 2. b.txt
why b

## 3. src/c.txt
why c
EOF
	run git review walkthrough build
	[ "$status" -eq 0 ]
	# The BOM used to hide the first entry from the parser outright, so build
	# blamed the PR for a.txt being missing from a walkthrough that lists it.
	[[ "$output" == *"3 entries, ordered and renumbered"* ]]
	[[ "$output" != *"missing from the walkthrough"* ]]
	expected="$(printf '# Walkthrough\n\n## 1. a.txt\nwhy a\n\n## 2. b.txt\nwhy b\n\n## 3. src/c.txt\nwhy c\n\n')"
	[ "$(built_body)" = "$expected" ]
}

# ── stray whitespace on an entry heading ──────────────────────────────────────

@test "build accepts trailing whitespace after an entry path" {
	mkdir -p .review
	# One space after a.txt and one tab after b.txt: invisible in every editor, and
	# they used to make the entry compare unequal to git's path, so build named the
	# identical file on both sides of a drift error.
	{
		printf '# Walkthrough\n\n'
		printf '## 1. a.txt \nwhy a\n\n'
		printf '## 2. b.txt\t\nwhy b\n\n'
		printf '## 3. src/c.txt\nwhy c\n'
	} >.review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" == *"3 entries, ordered and renumbered"* ]]
	[[ "$output" != *"missing from the walkthrough"* ]]
	[[ "$output" != *"not changed in the PR"* ]]
	# The rewrite drops the stray whitespace, so the author's build heals the
	# sidecar for every reviewer.
	expected="$(printf '# Walkthrough\n\n## 1. a.txt\nwhy a\n\n## 2. b.txt\nwhy b\n\n## 3. src/c.txt\nwhy c\n\n')"
	[ "$(built_body)" = "$expected" ]
}

@test "build keeps the key marker on an entry whose heading has trailing space" {
	mkdir -p .review
	{
		printf '# Walkthrough\n\n'
		printf '## 1. a.txt \n> key\nwhy a\n\n'
		printf '## 2. b.txt\nwhy b\n\n'
		printf '## 3. src/c.txt\nwhy c\n'
	} >.review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	# The body is looked up by path, so an untrimmed heading lost the body with it.
	[[ "$output" == *"3 entries (1 key), ordered and renumbered"* ]]
	expected="$(printf '# Walkthrough\n\n## 1. a.txt\n> key\nwhy a\n\n## 2. b.txt\nwhy b\n\n## 3. src/c.txt\nwhy c\n\n')"
	[ "$(built_body)" = "$expected" ]
}

@test "build refuses an entry heading that is not in the canonical form" {
	mkdir -p .review
	{
		printf '# Walkthrough\n\n'
		printf '##  1. a.txt\nwhy a\n\n'
		printf '## 2) b.txt\nwhy b\n\n'
		printf '## 3. src/c.txt\nwhy c\n'
	} >.review/walkthrough.md
	cp .review/walkthrough.md "$TMP/before.md"
	run git review walkthrough build
	[ "$status" -ne 0 ]
	# The parser ignores both headings by design, so without this check build
	# reported the two files as changed-but-missing: blaming the PR for a typo.
	[[ "$output" == *"not in the '## N. <path>' form"* ]]
	[[ "$output" == *"##  1. a.txt"* ]]
	[[ "$output" == *"## 2) b.txt"* ]]
	[[ "$output" != *"missing from the walkthrough"* ]]
	# A refusal writes nothing.
	cmp -s "$TMP/before.md" .review/walkthrough.md
}

@test "build leaves a numbered sub-heading inside a why body alone" {
	mkdir -p .review
	# "### 2. ..." is prose inside a body, not a malformed entry heading: the
	# canonical-form check must not reach for it.
	{
		printf '# Walkthrough\n\n'
		printf '## 1. a.txt\nwhy a\n\n'
		printf '### 2. a sub-heading, not an entry\nstill why a\n\n'
		printf '## 2. b.txt\nwhy b\n\n'
		printf '## 3. src/c.txt\nwhy c\n'
	} >.review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" == *"3 entries, ordered and renumbered"* ]]
	[[ "$output" != *"not in the '## N. <path>' form"* ]]
	# It stays in the body it belongs to.
	grep -qxF '### 2. a sub-heading, not an entry' .review/walkthrough.md
	run grep -c '^## ' .review/walkthrough.md
	[ "$output" = "3" ]
}
