#!/usr/bin/env bats
#
# Tests for keeping a walkthrough current after the PR moves on: init updating in
# place instead of refusing, the "> at:" anchors that spot a why written against
# an older version of its file, and the agent circuit on the author's side
# (init --stdout / build --from).
#
# The PR (feature/x) starts out changing two files vs develop: a.txt and b.txt.
# Every test below adds to it, which is the situation the whole feature exists
# for -- a PR that was finished, annotated, and then touched again.

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
	git add a.txt b.txt
	git commit --quiet -m c1
}

teardown() {
	rm -rf "$TMP"
}

# Portable in-place edit (the same helper step-replay.bats and
# walkthrough-draft.bats carry, and for the same reason): BSD/macOS sed
# consumes the script as -i's backup suffix, so the bare `sed -i 'script'
# file` form errors on the macOS runner.
edit_file() {
	tmp="$(mktemp)"
	sed "$1" "$2" >"$tmp" && mv "$tmp" "$2"
}

# A finished walkthrough for the two files the PR starts with, built so it
# carries whatever build stamps (anchors included) rather than only what a
# heredoc can spell.
write_and_build() {
	mkdir -p .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## Heads-up

the delicate bit is the counter

## 1. a.txt
> key
why a

## 2. b.txt
why b
EOF
	git review walkthrough build >/dev/null
}

# Everything from the first entry heading on: the part of the file that is
# content rather than scaffolding, and the only part two verbs have to agree on.
entries_of() {
	awk '/^## ([0-9]+|\?)\. / { on = 1 } on { print }' "$1"
}

# The body of an entry, marker lines and all.
entry_body() {
	awk -v want="$1" '
		/^## / {
			line = substr($0, 4)
			if (sub(/^[0-9]+\. /, "", line) || sub(/^\?\. /, "", line)) {
				cur = (line == want)
			} else {
				cur = 0
			}
			next
		}
		cur { print }
	' .review/walkthrough.md
}

# ── init: update in place ─────────────────────────────────────────────────────

@test "init updates an existing walkthrough instead of refusing" {
	write_and_build
	printf 'new\n' >c.txt
	git add c.txt
	git commit --quiet -m c2

	run git review walkthrough init
	[ "$status" -eq 0 ]
	[[ "$output" == *"updated .review/walkthrough.md"* ]]
	[[ "$output" == *"2 kept"* ]]
	[[ "$output" == *"1 added"* ]]
	[[ "$output" == *"0 dropped"* ]]

	# The two finished entries keep their number, their why and their marker.
	grep -q '^## 1\. a\.txt$' .review/walkthrough.md
	grep -q '^## 2\. b\.txt$' .review/walkthrough.md
	[[ "$(entry_body a.txt)" == *"why a"* ]]
	[[ "$(entry_body a.txt)" == *"> key"* ]]
	[[ "$(entry_body b.txt)" == *"why b"* ]]
	# The new file arrives unnumbered, with a placeholder to fill in.
	grep -q '^## ?\. c\.txt$' .review/walkthrough.md
	[[ "$(entry_body c.txt)" == "<!-- why: -->" ]]
	# And the heads-up is carried through untouched.
	grep -q '^the delicate bit is the counter$' .review/walkthrough.md
}

@test "init drops entries whose file left the range and names them on stderr" {
	write_and_build
	# b.txt goes back to its base content, so the PR no longer changes it.
	printf 'b1\n' >b.txt
	git add b.txt
	git commit --quiet -m revert-b

	run git review walkthrough init
	[ "$status" -eq 0 ]
	[[ "$output" == *"1 dropped"* ]]
	[[ "$output" == *"the PR no longer changes these files"* ]]
	[[ "$output" == *"b.txt"* ]]
	[[ "$output" == *"git checkout -- .review/walkthrough.md"* ]]

	# Gone from the file, and a.txt is untouched.
	run grep -c '^## [0-9?]*\. b\.txt$' .review/walkthrough.md
	[ "$output" = "0" ]
	grep -q '^## 1\. a\.txt$' .review/walkthrough.md
	[[ "$(entry_body a.txt)" == *"why a"* ]]
}

@test "init update keeps an unnumbered entry that already has prose" {
	# Mid-authoring: the why is written, the number is not. walk_parse ignores
	# such an entry, so an update that leaned on it would silently destroy the
	# one thing the author had just typed.
	mkdir -p .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## Heads-up

careful here

## ?. a.txt
half-written why

## ?. b.txt
<!-- why: -->
EOF
	printf 'new\n' >c.txt
	git add c.txt
	git commit --quiet -m c2

	run git review walkthrough init
	[ "$status" -eq 0 ]
	[[ "$output" == *"2 kept"* ]]
	[[ "$output" == *"1 added"* ]]
	[[ "$(entry_body a.txt)" == *"half-written why"* ]]
	grep -q '^careful here$' .review/walkthrough.md
}

@test "init update carries an unfilled heads-up placeholder through" {
	# The placeholder has to survive, or the update answers build's "the heads-up
	# placeholder is still there" on the author's behalf.
	mkdir -p .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## Heads-up

<!-- heads-up: the delicate parts of this PR, in a few lines. -->

## 1. a.txt
why a

## 2. b.txt
why b
EOF
	printf 'new\n' >c.txt
	git add c.txt
	git commit --quiet -m c2

	run git review walkthrough init
	[ "$status" -eq 0 ]
	grep -q '^<!-- heads-up' .review/walkthrough.md
	# And build still refuses it, exactly as it did before the update. The new
	# entry is numbered first so the unfilled-entry rule does not fire ahead of
	# the heads-up one.
	edit_file 's/^## ?\. c\.txt$/## 3. c.txt/; s/^<!-- why: -->$/why c/' .review/walkthrough.md
	run git review walkthrough build
	[ "$status" -eq 1 ]
	[[ "$output" == *"heads-up placeholder is still there"* ]]
}

@test "init update tells whoever fills it in to leave finished entries alone" {
	write_and_build
	printf 'new\n' >c.txt
	git add c.txt
	git commit --quiet -m c2

	run git review walkthrough init
	[ "$status" -eq 0 ]
	grep -q 'Update the reading order for this PR' .review/walkthrough.md
	grep -q 'are FINISHED: leave them exactly as they are' .review/walkthrough.md
	# The blank-slate wording is gone, so an agent is not told that a file full
	# of finished prose is a set of placeholders.
	run grep -c 'The entries below are' .review/walkthrough.md
	[ "$output" = "0" ]
}

@test "init --force still discards everything and writes a blank skeleton" {
	write_and_build
	run git review walkthrough init --force
	[ "$status" -eq 0 ]
	[[ "$output" == *"wrote .review/walkthrough.md"* ]]
	grep -q '^## ?\. a\.txt$' .review/walkthrough.md
	run grep -c 'why a' .review/walkthrough.md
	[ "$output" = "0" ]
	run grep -c '^> key$' .review/walkthrough.md
	[ "$output" = "0" ]
}

@test "init update over a current walkthrough changes not one entry" {
	write_and_build
	entries_of .review/walkthrough.md >"$TMP/before.md"
	run git review walkthrough init
	[ "$status" -eq 0 ]
	[[ "$output" == *"2 kept, 0 added, 0 dropped"* ]]
	# Every entry byte for byte: number, markers, anchor, prose. What init does
	# add back is its instruction comment, which build strips again -- the two
	# verbs disagree about scaffolding on purpose, never about content.
	entries_of .review/walkthrough.md >"$TMP/after.md"
	run diff -u "$TMP/before.md" "$TMP/after.md"
	if [ "$status" -ne 0 ]; then
		echo "$output"
		false
	fi
	grep -q '^the delicate bit is the counter$' .review/walkthrough.md
}

# ── draft: update in place, the reviewer side of the same thing ───────────────
#
# The reason it exists is not the same as init's. A draft cannot fall out of step
# DURING a review -- start freezes the tip -- but it outlives the review, and the
# next one is over a range that moved. --offline throughout: this fixture has no
# remote, and offline is the flag that resolves both ends locally.

DRAFT_OF() { printf '%s/review-walkthrough/%s.md' "$(git rev-parse --git-dir)" "$1"; }

# A draft with both of its entries written, the way a reviewer would leave one.
write_draft() {
	d="$(DRAFT_OF feature/x)"
	mkdir -p "$(dirname "$d")"
	cat >"$d" <<'EOF'
# Walkthrough

## Heads-up

read the counter first

## 1. a.txt
reviewer why a

## 2. b.txt
reviewer why b
EOF
}

@test "draft updates an existing draft instead of refusing" {
	write_draft
	printf 'new
' >c.txt
	git add c.txt
	git commit --quiet -m c2

	run git review walkthrough draft --offline feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"updated "* ]]
	[[ "$output" == *"2 kept"* ]]
	[[ "$output" == *"1 added"* ]]

	d="$(DRAFT_OF feature/x)"
	# The reviewer's prose survives, numbering and all.
	grep -q '^## 1\. a\.txt$' "$d"
	grep -q '^## 2\. b\.txt$' "$d"
	grep -q '^reviewer why a$' "$d"
	grep -q '^reviewer why b$' "$d"
	grep -q '^read the counter first$' "$d"
	# And the file that entered the range arrives as a placeholder.
	grep -q '^## ?\. c\.txt$' "$d"
}

@test "draft update names the dropped entries and offers no way back" {
	write_draft
	# b.txt goes back to its base content, so the PR no longer changes it.
	printf 'b1
' >b.txt
	git add b.txt
	git commit --quiet -m revert-b

	run git review walkthrough draft --offline feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"1 entry/entries dropped"* ]]
	[[ "$output" == *"b.txt"* ]]
	# No "git checkout" hint here, unlike init: this file is not in git, so the
	# note naming the paths is all the reviewer gets, and promising a way back
	# would be promising something that does not exist.
	[[ "$output" != *"git checkout --"* ]]
	! grep -q '^## 2\. b\.txt$' "$(DRAFT_OF feature/x)"
}

@test "draft --force still discards everything and writes a blank skeleton" {
	write_draft
	run git review walkthrough draft --offline --force feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"wrote "* ]]
	[[ "$output" != *"kept"* ]]

	d="$(DRAFT_OF feature/x)"
	! grep -q 'reviewer why a' "$d"
	grep -q '^## ?\. a\.txt$' "$d"
}

@test "draft update over a current draft changes not one entry" {
	write_draft
	d="$(DRAFT_OF feature/x)"
	before="$(cat "$d")"

	run git review walkthrough draft --offline feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"2 kept"* ]]
	[[ "$output" == *"0 added"* ]]
	[[ "$output" == *"0 dropped"* ]]
	# Same entries, in the same order, with the same prose: an update with
	# nothing to reconcile is not an excuse to rewrite what is written.
	[ "$(entries_of "$d")" = "$(printf '%s
' "$before" | awk '/^## ([0-9]+|\?)\. / { on = 1 } on { print }')" ]
}

# ── init --stdout ─────────────────────────────────────────────────────────────

@test "init --stdout writes nothing and names build --from as the way back" {
	run git review walkthrough init --stdout
	[ "$status" -eq 0 ]
	[ ! -e .review/walkthrough.md ]
	[[ "$output" == *"# Walkthrough"* ]]
	[[ "$output" == *"## ?. a.txt"* ]]
	[[ "$output" == *"git review walkthrough build --from <file>"* ]]
	# The bare "build" closing line would point at the work tree, not at what
	# the agent is about to write.
	[[ "$output" != *"validate and write with:  git review walkthrough build"* ]]
}

@test "init --stdout over an existing walkthrough prints the update, file untouched" {
	write_and_build
	before="$(cat .review/walkthrough.md)"
	printf 'new\n' >c.txt
	git add c.txt
	git commit --quiet -m c2

	run git review walkthrough init --stdout
	[ "$status" -eq 0 ]
	[ "$(cat .review/walkthrough.md)" = "$before" ]
	[[ "$output" == *"## 1. a.txt"* ]]
	[[ "$output" == *"why a"* ]]
	[[ "$output" == *"## ?. c.txt"* ]]
}

@test "init --stdout --force is refused" {
	run git review walkthrough init --stdout --force
	[ "$status" -eq 1 ]
	[[ "$output" == *"nothing to force"* ]]
	[ ! -e .review/walkthrough.md ]
}

# ── build --from ──────────────────────────────────────────────────────────────

@test "build --from installs a walkthrough written outside the work tree" {
	cat >"$TMP/order.md" <<'EOF'
# Walkthrough

## Heads-up

watch the counter

## 2. a.txt
why a

## 1. b.txt
why b
EOF
	run git review walkthrough build --from "$TMP/order.md"
	[ "$status" -eq 0 ]
	[[ "$output" == *"built .review/walkthrough.md"* ]]
	# Installed, and renumbered by the author's numbers like any other build.
	grep -q '^## 1\. b\.txt$' .review/walkthrough.md
	grep -q '^## 2\. a\.txt$' .review/walkthrough.md
	grep -q '^watch the counter$' .review/walkthrough.md
}

@test "build --from - reads standard input" {
	cat >"$TMP/order.md" <<'EOF'
# Walkthrough

## 1. a.txt
why a

## 2. b.txt
why b
EOF
	run sh -c 'git review walkthrough build --from - <"$1"' _ "$TMP/order.md"
	[ "$status" -eq 0 ]
	grep -q '^## 1\. a\.txt$' .review/walkthrough.md
}

@test "build --from validates by the same rules and leaves the old file intact" {
	write_and_build
	before="$(cat .review/walkthrough.md)"

	# Drift: the incoming file is missing a path the PR changes.
	cat >"$TMP/short.md" <<'EOF'
# Walkthrough

## 1. a.txt
why a
EOF
	run git review walkthrough build --from "$TMP/short.md"
	[ "$status" -eq 1 ]
	[[ "$output" == *"missing from the walkthrough"* ]]
	[[ "$output" == *"b.txt"* ]]
	[ "$(cat .review/walkthrough.md)" = "$before" ]

	# Unfilled placeholders.
	cat >"$TMP/unfilled.md" <<'EOF'
# Walkthrough

## ?. a.txt
why a

## 2. b.txt
why b
EOF
	run git review walkthrough build --from "$TMP/unfilled.md"
	[ "$status" -eq 1 ]
	[[ "$output" == *"unfilled entries remain"* ]]
	[ "$(cat .review/walkthrough.md)" = "$before" ]

	# An unreadable source names the source, not the target.
	run git review walkthrough build --from "$TMP/nope.md"
	[ "$status" -eq 1 ]
	[[ "$output" == *"could not read"* ]]
	[ "$(cat .review/walkthrough.md)" = "$before" ]
}

@test "build --from does not demand --force over an existing walkthrough" {
	# build already rewrites the sidecar on every ordinary run, and the file is
	# tracked, so requiring consent here would make --force reflex typing.
	write_and_build
	cat >"$TMP/order.md" <<'EOF'
# Walkthrough

## 1. b.txt
new why b

## 2. a.txt
new why a
EOF
	run git review walkthrough build --from "$TMP/order.md"
	[ "$status" -eq 0 ]
	grep -q 'new why b' .review/walkthrough.md
}

@test "build rejects --stdout and init rejects --from" {
	run git review walkthrough build --stdout
	[ "$status" -eq 1 ]
	[[ "$output" == *"init --stdout"* ]]
	run git review walkthrough init --from "$TMP/x.md"
	[ "$status" -eq 1 ]
	[[ "$output" == *"build --from"* ]]
	[ ! -e .review/walkthrough.md ]
}

# ── Anchors ───────────────────────────────────────────────────────────────────

@test "build stamps an at anchor under every entry" {
	write_and_build
	run grep -c '^> at: [0-9a-f]\{40\}$' .review/walkthrough.md
	[ "$output" = "2" ]
	# The anchor is the blob the tip actually holds for that path.
	want="$(git rev-parse HEAD:a.txt)"
	[[ "$(entry_body a.txt)" == *"> at: $want"* ]]
	# It sits with the other marker, above the prose.
	[ "$(entry_body a.txt | sed -n 1p)" = "> key" ]
	[ "$(entry_body a.txt | sed -n 2p)" = "> at: $want" ]
}

@test "build notes the whys whose file changed since they were written" {
	write_and_build
	printf 'a1\na2\na3\n' >a.txt
	git add a.txt
	git commit --quiet -m c2

	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" == *"written against an older version of their file"* ]]
	[[ "$output" == *"a.txt"* ]]
	# b.txt did not change, so it is not named.
	[[ "$output" != *"b.txt"* ]]
	# A note, never a failure: the walkthrough is still built.
	[[ "$output" == *"built .review/walkthrough.md"* ]]
	# And the anchor is brought up to date, so the next build is quiet.
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" != *"older version of their file"* ]]
}

@test "build --check reports stale whys without writing" {
	write_and_build
	before="$(cat .review/walkthrough.md)"
	printf 'a1\na2\na3\n' >a.txt
	git add a.txt
	git commit --quiet -m c2

	run git review walkthrough build --check
	[ "$status" -eq 0 ]
	[[ "$output" == *"written against an older version of their file"* ]]
	[[ "$output" == *"walkthrough ok"* ]]
	[ "$(cat .review/walkthrough.md)" = "$before" ]
}

@test "anchors are not duplicated across rebuilds" {
	write_and_build
	git review walkthrough build >/dev/null
	git review walkthrough build >/dev/null
	run grep -c '^> at: ' .review/walkthrough.md
	[ "$output" = "2" ]
}

@test "an unanchored walkthrough is never reported as stale" {
	# Every walkthrough written before anchors existed has none, and telling
	# their authors that every why is old would be worse than saying nothing.
	mkdir -p .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. a.txt
why a

## 2. b.txt
why b
EOF
	run git review walkthrough build
	[ "$status" -eq 0 ]
	[[ "$output" != *"older version of their file"* ]]
}

@test "the anchor never reaches the reviewer" {
	write_and_build
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough
	git switch --quiet develop
	# --offline: this fixture has no remote, and what is under test is what the
	# reviewer is shown, not where the tip came from.
	git review start --offline feature/x >/dev/null

	run git review status --why a.txt
	[ "$status" -eq 0 ]
	[[ "$output" == *"why a"* ]]
	[[ "$output" != *"at:"* ]]
	[[ "$output" != *"key"* ]]
}

# ── config --porcelain: the state of the author's own walkthrough ─────────────

@test "config --porcelain reports the walkthrough as absent when there is none" {
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *"walkthrough	absent	"*"/.review/walkthrough.md	0	0"* ]]
}

@test "config --porcelain reports in-sync right after a build" {
	write_and_build
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *"walkthrough	in-sync	"*"/.review/walkthrough.md	3	3"* ]]
}

@test "committing the walkthrough itself does not make it stale" {
	# The ordinary author's flow ends in a commit of the sidecar, which moves
	# HEAD. Without excluding .review/ the panel called the file out of date the
	# moment it was written.
	write_and_build
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *"walkthrough	in-sync	"* ]]
}

@test "config --porcelain reports stale once the PR moves on" {
	write_and_build
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough

	# A file that no entry covers.
	printf 'new\n' >c.txt
	git add c.txt
	git commit --quiet -m c2
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *"walkthrough	stale	"* ]]
}

@test "a file the walkthrough already covers changing is stale too" {
	# The drift check compares the set of paths and would pass this in green;
	# the row is what says the whys may no longer describe their files.
	write_and_build
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough
	printf 'a1\na2\na3\n' >a.txt
	git add a.txt
	git commit --quiet -m c2
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *"walkthrough	stale	"* ]]
}

@test "a walkthrough with no instruction block reports unknown, not stale" {
	# Deleting the block by hand is legal, so its absence is a missing answer and
	# never a wrong one.
	mkdir -p .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. a.txt
why a

## 2. b.txt
why b
EOF
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *"walkthrough	unknown	"* ]]
}

@test "the walkthrough progress pair counts the heads-up like the drafts do" {
	# Skeleton: two entries plus a heads-up section, none of them written.
	git review walkthrough init >/dev/null
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *"walkthrough	"*"	0	3"* ]]
}

@test "config --porcelain reports the walkthrough with a branch argument too" {
	# --offline because this fixture has no remote; what is under test is that the
	# row survives a branch argument, not how the tip is resolved.
	write_and_build
	run git review config --porcelain --offline feature/x
	[ "$status" -eq 0 ]
	[[ "$output" == *"walkthrough	in-sync	"* ]]
}

@test "the walkthrough row names the branch it annotates" {
	# What the clients call the row with. Without it the panel says
	# "Walkthrough" under a section already called Walkthrough.
	write_and_build
	run git review config --porcelain
	[ "$status" -eq 0 ]
	row="$(printf '%s
' "$output" | grep '^walkthrough	')"
	[ "$(printf '%s
' "$row" | cut -f6)" = "feature/x" ]
}

@test "a detached HEAD omits the branch field and still reports the row" {
	# The file and both verbs work with a detached HEAD, so the row stays; only
	# its name is a question with no answer, and a blank field is not an answer
	# either -- omit, never blank.
	write_and_build
	git checkout --quiet --detach HEAD
	run git review config --porcelain
	[ "$status" -eq 0 ]
	row="$(printf '%s
' "$output" | grep '^walkthrough	')"
	[ "$(printf '%s
' "$row" | cut -f2)" = "in-sync" ]
	[ "$(printf '%s
' "$row" | awk -F'	' '{print NF}')" -eq 5 ]
}

@test "the reported walkthrough path is absolute and openable" {
	write_and_build
	run git review config --porcelain
	[ "$status" -eq 0 ]
	row="$(printf '%s\n' "$output" | grep '^walkthrough	')"
	path="$(printf '%s\n' "$row" | cut -f3)"
	case "$path" in
	/*) ;;
	[A-Za-z]:[\/]*) ;;
	*) false ;;
	esac
	[ -f "$path" ]
}

# ── Un walkthrough que llegó con un merge ─────────────────────────────────────
#
# El PR se mergea, el sidecar viaja a la base con él, y la rama siguiente toca
# uno de los mismos archivos. Reconciliar contra eso conserva un why sobre un
# cambio que ya salió, y ese texto se commitea al PR nuevo.

# Deja la base con el walkthrough de un PR ya mergeado, y HEAD en una rama nueva
# que toca uno de sus archivos.
merged_walkthrough() {
	git switch --quiet -c feature/login
	printf 'a1\na2\nlogin\n' >a.txt
	git add a.txt
	git commit --quiet -m "feat: login"
	mkdir -p .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## Heads-up

el login toca la sesion

## 1. a.txt
el flujo de login entra por aca

## 2. b.txt
la query de usuario
EOF
	git review walkthrough build >/dev/null 2>&1
	git add -A
	git commit --quiet -m "docs: walkthrough"
	git switch --quiet develop
	git merge --quiet --no-ff -m "merge login" feature/login
	git switch --quiet -c feature/mfa
	printf 'a1\na2\nlogin\nmfa\n' >a.txt
	git add a.txt
	git commit --quiet -m "feat: mfa"
}

@test "init starts over on a walkthrough that came in with a merge" {
	merged_walkthrough
	run git review walkthrough init
	[ "$status" -eq 0 ]
	[[ "$output" == *"not this PR's"* ]]
	[[ "$output" == *"came in with the merge"* ]]
	[[ "$output" == *"git checkout -- .review/walkthrough.md"* ]]

	# Skeleton, not a reconciliation: the why of the merged PR is gone.
	grep -q '^## ?\. a\.txt$' .review/walkthrough.md
	run grep -c 'el flujo de login entra por aca' .review/walkthrough.md
	[ "$output" = "0" ]
	# And its heads-up went with it: that prose was about the other change too.
	run grep -c 'el login toca la sesion' .review/walkthrough.md
	[ "$output" = "0" ]
}

@test "starting over needs no --force, and the old one is still in git" {
	# The one case that decides for itself. Everything the note promises has to
	# hold, or "started a new one" is a way of saying prose was destroyed.
	merged_walkthrough
	run git review walkthrough init
	[ "$status" -eq 0 ]
	run git checkout -- .review/walkthrough.md
	[ "$status" -eq 0 ]
	grep -q 'el flujo de login entra por aca' .review/walkthrough.md
}

@test "config --porcelain calls it superseded, not stale" {
	# Nothing about it fell behind: it belongs to a range that closed. The panel
	# needs the two apart to offer the right thing.
	merged_walkthrough
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *"walkthrough	superseded	"* ]]
	[[ "$output" != *"walkthrough	stale	"* ]]
}

@test "a walkthrough of this PR is never called superseded" {
	# The guard against the cheap test being too eager: a tip that is not in the
	# base is this PR's, however far behind it has fallen.
	write_and_build
	printf 'new\n' >c.txt
	git add c.txt
	git commit --quiet -m c2
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *"walkthrough	stale	"* ]]
	# And init reconciles it, as it does for any PR that moved on.
	run git review walkthrough init
	[ "$status" -eq 0 ]
	[[ "$output" == *"2 kept"* ]]
	[[ "$output" != *"not this PR's"* ]]
}

@test "with the tip gone from the clone it is unknown, never superseded" {
	# "Cannot tell" must not read as "no": a fresh clone would go straight back
	# to reconciling against a merged PR.
	write_and_build
	# El contenedor no trae python; sed alcanza y es lo que usa el resto de la suite.
	edit_file 's/^\(       tip   \)[0-9a-f]\{40\}/\10000000000000000000000000000000000000000/' .review/walkthrough.md
	grep -q '^       tip   0\{40\}' .review/walkthrough.md
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *"walkthrough	unknown	"* ]]
}
