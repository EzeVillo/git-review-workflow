#!/usr/bin/env bats
#
# Tests for the two flags that let something other than a person fill a draft in:
# --stdout hands the skeleton out without writing anywhere, and --build --from
# takes the filled-in copy back and installs it.
#
# The pairing is the point. An agent that has to write into $GIT_DIR to be given
# the brief is an agent that has to be trusted with the gitdir; with these two it
# never touches it, and the CLI stays the only thing that writes there.

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

	# The PR under test. One path carries a space and a non-ASCII byte, because a
	# source that arrives from outside goes through exactly the same path
	# comparison a hand-written draft does.
	git switch --quiet -c feature/plain
	printf 'a1\na2\n' >a.txt
	mkdir -p src
	printf 'hello\n' >src/c.txt
	printf 'x\n' >"src/cafe con espacio.js"
	git add -A
	git commit --quiet -m work
	git push --quiet -u origin feature/plain

	# A branch with nothing in it vs the base, for the refusals.
	git switch --quiet develop
	git switch --quiet -c feature/empty
	git push --quiet -u origin feature/empty

	git switch --quiet develop
	GITDIR="$(git rev-parse --git-dir)"
	NS="$GITDIR/review-walkthrough"
	DRAFT="$NS/feature/plain.md"
}

teardown() {
	rm -rf "$TMP"
}

# A valid reading order over feature/plain's three files, written the way an
# agent would hand one back: no skeleton scaffolding, just the content.
write_order() {
	cat >"$1" <<'EOF'
# Walkthrough

## Heads-up

mind the encoding of that one path

## 2. a.txt
why a

## 1. src/c.txt
why c

## 3. src/cafe con espacio.js
why the odd name
EOF
}

# The skeleton minus its closing instruction, which is the one passage that
# legitimately differs between the written and the printed form.
without_closing() {
	awk '
		/^     Then validate and/ { skip = 1 }
		skip {
			if (index($0, "-->")) skip = 0
			next
		}
		{ print }
	' "$1"
}

# git review, with MSYS's argument path conversion switched off.
#
# Only for the assertions that quote the path back. Git for Windows' git.exe is
# a native Windows program, so under Git Bash MSYS rewrites every argument that
# looks like an absolute POSIX path before git.exe is spawned: a --from of
# "/tmp/tmp.XXXX/order.md" arrives as
# "C:/Users/EZEVI_~1/AppData/Local/Temp/tmp.XXXX/order.md". The verb then names
# that string back -- correctly, it is what it was handed -- and an assertion
# written against the path the test typed fails on the Windows runner and
# nowhere else. Off Windows the variable is unset and nothing reads it, so the
# three runners assert the same sentence about the same string.
review_verbatim_paths() {
	MSYS_NO_PATHCONV=1 git review "$@"
}

# Every temp file anywhere under the gitdir, as a newline-separated list. A glob
# and not find(1), for the reason walkthrough-draft.bats spells out at its own
# draft_temps: under Git Bash a stray PATH resolves find to Windows' own
# find.exe, whose -name means nothing to it, and CI runs this suite on a real
# Windows runner -- where the assertion would then pass or fail for reasons that
# have nothing to do with --stdout.
#
# The levels are spelled out instead of using **, because globstar is bash 4 and
# macOS ships bash 3.2. What breaks there is not the glob -- nullglob is still
# set, and ** degrades to a plain * -- it is the diagnostic: shopt prints
# "globstar: invalid shell option name" on STDERR, `run` folds stderr into
# $output, and the caller's `[ -z "$output" ]` reads that sentence as a temp file
# left behind. A red macOS-only test over a verb that is doing its job.
#
# Five levels is three more than the deepest a draft can sit at: the namespace,
# plus one directory per '/' in a branch name. nullglob on its own is bash 3.2
# material, and this is a bats file, not a POSIX verb.
gitdir_temps() (
	shopt -s nullglob
	printf '%s\n' \
		"$GITDIR"/*.tmp.* \
		"$GITDIR"/*/*.tmp.* \
		"$GITDIR"/*/*/*.tmp.* \
		"$GITDIR"/*/*/*/*.tmp.* \
		"$GITDIR"/*/*/*/*/*.tmp.*
)

# ── --stdout writes nothing ───────────────────────────────────────────────────

@test "--stdout prints the skeleton and creates nothing at all" {
	before="$(git status --porcelain)"
	[ ! -d "$NS" ]

	run git review walkthrough draft --stdout feature/plain
	[ "$status" -eq 0 ]
	[ -n "$output" ]
	printf '%s\n' "$output" | grep -q '^## ?\. a.txt$'

	# Not "no draft was created": nothing at all, temp files included.
	[ ! -d "$NS" ]
	[ "$(git status --porcelain)" = "$before" ]
	run gitdir_temps
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "--stdout emits the same bytes the file would hold, bar the closing line" {
	git review walkthrough draft --stdout feature/plain >"$TMP/printed.md"
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	[ -f "$DRAFT" ]

	without_closing "$TMP/printed.md" >"$TMP/printed.body"
	without_closing "$DRAFT" >"$TMP/written.body"
	run cmp -s "$TMP/printed.body" "$TMP/written.body"
	[ "$status" -eq 0 ]
}

@test "the closing line of --stdout points at --from, and never at a bare --build" {
	run git review walkthrough draft --stdout feature/plain
	[ "$status" -eq 0 ]
	# Without this assertion the switch could silently revert: the printed file
	# would then tell the agent to run a --build that reads a different file.
	printf '%s\n' "$output" | grep -q 'git review walkthrough draft --build --from <file> feature/plain'
	printf '%s\n' "$output" | grep -q 'or --from - to read it from standard input'
	! printf '%s\n' "$output" | grep -q 'draft --build feature/plain'

	# And the written form still says the other thing, unchanged.
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	grep -q 'git review walkthrough draft --build feature/plain' "$DRAFT"
	! grep -q -- '--from' "$DRAFT"
}

@test "following the printed closing line installs what the agent wrote" {
	# The whole silent failure, end to end: capture the skeleton, fill it in, and
	# run the literal command the skeleton printed. Asserting the text alone would
	# not catch a command that is well-formed and reads the wrong file.
	git review walkthrough draft --stdout feature/plain >"$TMP/printed.md"
	line="$(grep -o 'git review walkthrough draft --build --from <file>.*' "$TMP/printed.md")"
	[ -n "$line" ]
	write_order "$TMP/filled.md"
	cmd="${line/<file>/$TMP/filled.md}"

	run bash -c "$cmd"
	[ "$status" -eq 0 ]
	[ -f "$DRAFT" ]
	grep -q '^## 1\. src/c.txt$' "$DRAFT"
	grep -q '^## 2\. a.txt$' "$DRAFT"
	grep -q 'why the odd name' "$DRAFT"
}

@test "--stdout over an existing draft prints and leaves it byte for byte alone" {
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	write_order "$DRAFT"
	cp "$DRAFT" "$TMP/before.md"

	# Printing cannot destroy anything, so the "already exists" guard has nothing
	# to protect here and deliberately does not fire.
	run git review walkthrough draft --stdout feature/plain
	[ "$status" -eq 0 ]
	[ -n "$output" ]
	run cmp -s "$TMP/before.md" "$DRAFT"
	[ "$status" -eq 0 ]
}

@test "--stdout works where the draft file could not be written at all" {
	# The property is that --stdout does not write, so it is unaffected by
	# anything that would stop a write. Deliberately NOT tested through a branch
	# called "nul": a reserved device name is illegal as a file name on Windows
	# and nowhere else, and on Windows git cannot create that branch either --
	# a loose ref IS a file, so "git switch -c nul" dies with "Unable to create
	# refs/heads/nul.lock: Invalid argument" and the test aborts on its second
	# line. The case is unreachable on the only platform that has it, and on
	# Linux and macOS "nul" is an ordinary name that proves nothing.
	#
	# What is reachable on all three is a namespace that cannot hold this
	# branch's path, with a plain file sitting where the subdirectory has to go.
	mkdir -p "$NS"
	printf 'in the way\n' >"$NS/feature"

	# The written form needs that directory and cannot have it.
	run git review walkthrough draft feature/plain
	[ "$status" -ne 0 ]
	[ ! -e "$DRAFT" ]

	# Printing the same skeleton does not care.
	run git review walkthrough draft --stdout feature/plain
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -q '^## ?\. a.txt$'
	printf '%s\n' "$output" | grep -q '^## ?\. src/cafe con espacio.js$'

	# And it wrote nothing on the way past: the blocker is untouched, no draft
	# appeared, and no temp file was left anywhere in the gitdir.
	[ -f "$NS/feature" ]
	[ "$(cat "$NS/feature")" = "in the way" ]
	[ ! -e "$DRAFT" ]
	run gitdir_temps
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "--stdout keeps stdout empty on every refusal" {
	# An empty skeleton is never printed: each of these dies before the skeleton
	# exists, and a caller redirecting stdout must not end up with a valid-looking
	# empty file.
	# stderr is discarded rather than captured: bats folds the two streams into
	# $output, and what is being asserted here is that STDOUT is empty.
	run bash -c 'git review walkthrough draft --stdout feature/nope 2>/dev/null'
	[ "$status" -eq 1 ]
	[ -z "$output" ]

	run bash -c 'git review walkthrough draft --stdout feature/empty 2>/dev/null'
	[ "$status" -eq 1 ]
	[ -z "$output" ]

	run bash -c 'git review walkthrough draft --stdout --delta feature/plain 2>/dev/null'
	[ "$status" -eq 1 ]
	[ -z "$output" ]

	git config --unset reviewworkflow.base
	run bash -c 'git review walkthrough draft --stdout feature/plain 2>/dev/null'
	[ "$status" -eq 1 ]
	[ -z "$output" ]
}

@test "--stdout refusals still explain themselves on stderr" {
	# The counterpart of the test above: stdout is empty, but the reason is not
	# lost -- it moved, it did not disappear.
	run bash -c 'git review walkthrough draft --stdout feature/nope 2>&1 >/dev/null'
	[ "$status" -eq 1 ]
	[[ "$output" == *"origin/feature/nope not found"* ]]

	run bash -c 'git review walkthrough draft --stdout feature/empty 2>&1 >/dev/null'
	[ "$status" -eq 1 ]
	[[ "$output" == *"no changes vs develop"* ]]

	run bash -c 'git review walkthrough draft --stdout --delta feature/plain 2>&1 >/dev/null'
	[ "$status" -eq 1 ]
	[[ "$output" == *"no previous review of feature/plain recorded"* ]]
}

# ── --build --from installs ───────────────────────────────────────────────────

@test "--build --from installs a draft from a file and start reads it" {
	[ ! -e "$DRAFT" ]
	write_order "$TMP/filled.md"
	run git review walkthrough draft --build --from "$TMP/filled.md" feature/plain
	[ "$status" -eq 0 ]
	[[ "$output" == *"3 entries"* ]]
	[ -f "$DRAFT" ]
	grep -q '^## 1\. src/c.txt$' "$DRAFT"

	run git review start feature/plain
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | awk -F'\t' '$1 == "state" { print $5 }')" = "walk" ]
}

@test "--build --from - installs the same bytes as --build --from <file>" {
	write_order "$TMP/filled.md"
	run git review walkthrough draft --build --from "$TMP/filled.md" feature/plain
	[ "$status" -eq 0 ]
	cp "$DRAFT" "$TMP/from-file.md"

	rm -rf "$NS"
	run bash -c "git review walkthrough draft --build --from - feature/plain < '$TMP/filled.md'"
	[ "$status" -eq 0 ]
	run cmp -s "$TMP/from-file.md" "$DRAFT"
	[ "$status" -eq 0 ]
}

@test "a draft installed from outside has exactly the custody of one written in place" {
	write_order "$TMP/filled.md"
	run git review walkthrough draft --build --from "$TMP/filled.md" feature/plain
	[ "$status" -eq 0 ]

	run git review start feature/plain
	[ "$status" -eq 0 ]
	run git review status
	[ "$status" -eq 0 ]
	[[ "$output" == *"walk (draft)"* ]]

	run git review list
	[ "$status" -eq 0 ]
	[[ "$output" == *"(draft)"* ]]

	run git review save
	[ "$status" -eq 0 ]
	[ ! -e "$DRAFT" ]
	[ -f "$GITDIR/review-saved-walkthrough/feature/plain.md" ]

	run git review continue feature/plain
	[ "$status" -eq 0 ]
	[ -f "$DRAFT" ]
	[ ! -e "$GITDIR/review-saved-walkthrough/feature/plain.md" ]

	run git review abort
	[ "$status" -eq 0 ]
	run git review forget --draft feature/plain
	[ "$status" -eq 0 ]
	[ ! -e "$DRAFT" ]
}

@test "--from creates the namespace, subdirectory and all" {
	[ ! -d "$NS" ]
	write_order "$TMP/filled.md"
	run git review walkthrough draft --build --from "$TMP/filled.md" feature/plain
	[ "$status" -eq 0 ]
	# The branch name holds a '/', so the namespace is a directory tree here, the
	# same way refs/ is.
	[ -d "$NS/feature" ]
	[ -f "$NS/feature/plain.md" ]
}

@test "--from normalises CRLF and a BOM instead of drifting on them" {
	# What an agent writing from PowerShell produces. Without normalisation every
	# path would carry a trailing CR and the drift check would name the same file
	# on both sides of its own error message.
	write_order "$TMP/plain.md"
	printf '\357\273\277' >"$TMP/crlf.md"
	sed 's/$/\r/' "$TMP/plain.md" >>"$TMP/crlf.md"

	run git review walkthrough draft --build --from "$TMP/crlf.md" feature/plain
	[ "$status" -eq 0 ]
	[ -f "$DRAFT" ]
	! grep -q $'\r' "$DRAFT"
	# The BOM is asserted by the equality below and not by a grep of its own: a
	# leading BOM would leave the first line as "\357\273\277# Walkthrough", which
	# is not "# Walkthrough".
	run head -n1 "$DRAFT"
	[ "$status" -eq 0 ]
	[ "$output" = "# Walkthrough" ]

	# And the result is the same file the LF source produces.
	cp "$DRAFT" "$TMP/from-crlf.md"
	run git review walkthrough draft --build --force --from "$TMP/plain.md" feature/plain
	[ "$status" -eq 0 ]
	run cmp -s "$TMP/from-crlf.md" "$DRAFT"
	[ "$status" -eq 0 ]
}

# ── nothing is written unless everything passed ───────────────────────────────

@test "every refusal leaves the previous draft byte for byte as it was" {
	write_order "$TMP/filled.md"
	run git review walkthrough draft --build --from "$TMP/filled.md" feature/plain
	[ "$status" -eq 0 ]
	cp "$DRAFT" "$TMP/before.md"

	# Each case: exit 1, a message on stderr, and the stored draft untouched.
	assert_refused() {
		run cmp -s "$TMP/before.md" "$DRAFT"
		[ "$status" -eq 0 ]
	}

	# No --force over an existing draft. Checked BEFORE the source is read, so a
	# caller piping into --from - can still retry with what it has.
	run git review walkthrough draft --build --from "$TMP/filled.md" feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"already exists; pass --force to overwrite"* ]]
	assert_refused

	: >"$TMP/empty.md"
	run git review walkthrough draft --build --force --from "$TMP/empty.md" feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"is empty; a reading order needs at least one entry"* ]]
	assert_refused

	printf '   \n\t\n\n' >"$TMP/blank.md"
	run git review walkthrough draft --build --force --from "$TMP/blank.md" feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"is empty; a reading order needs at least one entry"* ]]
	assert_refused

	run review_verbatim_paths walkthrough draft --build --force --from "$TMP/nothing-here.md" feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"could not read $TMP/nothing-here.md"* ]]
	assert_refused

	# Each validation rule, over content that is otherwise fine.
	sed 's/^## 2\. a.txt$/## ?. a.txt/' "$TMP/filled.md" >"$TMP/bad.md"
	run git review walkthrough draft --build --force --from "$TMP/bad.md" feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"unfilled entries remain"* ]]
	assert_refused

	sed 's/^why a$/<!-- why: -->/' "$TMP/filled.md" >"$TMP/bad.md"
	run git review walkthrough draft --build --force --from "$TMP/bad.md" feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"unfilled why-comments remain"* ]]
	assert_refused

	sed 's|^## 1\. src/c.txt$|## 1. a.txt|' "$TMP/filled.md" >"$TMP/bad.md"
	run git review walkthrough draft --build --force --from "$TMP/bad.md" feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"duplicate paths in walkthrough"* ]]
	assert_refused

	sed 's/^why a$/> key: because/' "$TMP/filled.md" >"$TMP/bad.md"
	run git review walkthrough draft --build --force --from "$TMP/bad.md" feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"the > key marker takes no value"* ]]
	assert_refused

	sed 's/^## 2\. a.txt$/## 2. gone.txt/' "$TMP/filled.md" >"$TMP/bad.md"
	run git review walkthrough draft --build --force --from "$TMP/bad.md" feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"in the walkthrough but not changed in the PR: gone.txt"* ]]
	assert_refused

	# Content with no entry heading at all. It is not the empty case above (there
	# is prose here), and it is the one rule with a file to name: it has to name
	# the SOURCE. Naming the stored draft accused a file this refusal never
	# touched, and the way out it offered -- rewrite that skeleton with --force --
	# would have destroyed it.
	printf 'just some prose, no order\n' >"$TMP/prose.md"
	run review_verbatim_paths walkthrough draft --build --force --from "$TMP/prose.md" feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"no entries found in $TMP/prose.md"* ]]
	[[ "$output" != *"review-walkthrough"* ]]
	[[ "$output" != *"--force"* ]]
	assert_refused

	# Same content down the pipe: the origin it names is standard input.
	run bash -c "git review walkthrough draft --build --force --from - feature/plain < '$TMP/prose.md'"
	[ "$status" -eq 1 ]
	[[ "$output" == *"no entries found in standard input"* ]]
	assert_refused
}

@test "a source that cannot be read as a file is refused by name" {
	write_order "$TMP/filled.md"
	run git review walkthrough draft --build --from "$TMP/filled.md" feature/plain
	[ "$status" -eq 0 ]
	cp "$DRAFT" "$TMP/before.md"

	# A directory, which is the half of the guard that behaves the same on every
	# runner: it exists, it is readable, and it is still not a reading order.
	mkdir "$TMP/adir"
	run review_verbatim_paths walkthrough draft --build --force --from "$TMP/adir" feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"could not read $TMP/adir"* ]]
	run cmp -s "$TMP/before.md" "$DRAFT"
	[ "$status" -eq 0 ]

	# The other half, permissions, only exists where the filesystem enforces
	# them. Under Git Bash on Windows "chmod 000" leaves the file at -r--r--r--
	# and readable, and root reads anything anywhere; either way the guard the
	# assertion is about would not fire, so there is nothing here to test. The
	# probe is the CLI's own condition, [ -r ], rather than a guess at which
	# runner this is.
	printf 'x\n' >"$TMP/locked.md"
	chmod 000 "$TMP/locked.md"
	if [ -r "$TMP/locked.md" ]; then
		chmod 644 "$TMP/locked.md"
		skip "chmod 000 leaves this file readable here; the guard cannot fire"
	fi
	run review_verbatim_paths walkthrough draft --build --force --from "$TMP/locked.md" feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"could not read $TMP/locked.md"* ]]
	run cmp -s "$TMP/before.md" "$DRAFT"
	[ "$status" -eq 0 ]
	chmod 644 "$TMP/locked.md"
}

@test "--from - with a terminal on standard input explains instead of hanging" {
	# Needs a pty, and there is no portable way to get one: the test container has
	# no script(1), and the two that ship with Linux and BSD take their arguments
	# in incompatible orders. Where neither is available this skips rather than
	# pretending -- the guard is [ -t 0 ], one builtin, and faking it would be
	# testing the fake.
	cmd="git review walkthrough draft --build --from - feature/plain"
	if script -qec true /dev/null >/dev/null 2>&1; then
		run script -qec "$cmd" /dev/null
	elif script -q /dev/null true >/dev/null 2>&1; then
		run script -q /dev/null "$cmd"
	else
		skip "no script(1) to allocate a pty on this runner"
	fi
	[ "$status" -ne 0 ]
	[[ "$output" == *"--from - reads the draft from standard input"* ]]
	[ ! -e "$DRAFT" ]
}

# ── the flag matrix ───────────────────────────────────────────────────────────

@test "every illegal combination of the new flags is refused with its own message" {
	assert_nothing_happened() {
		[ ! -d "$NS" ]
		[ -z "$(git status --porcelain)" ]
	}

	run git review walkthrough draft --stdout --build feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"--stdout writes the skeleton; --build validates one. Use one or the other"* ]]
	assert_nothing_happened

	run git review walkthrough draft --stdout --force feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"--stdout writes no file, so there is nothing to force"* ]]
	assert_nothing_happened

	run git review walkthrough draft --stdout --from "$TMP/x.md" feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"--from applies only to git review walkthrough draft --build"* ]]
	assert_nothing_happened

	run git review walkthrough draft --from "$TMP/x.md" feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"--from applies only to git review walkthrough draft --build"* ]]
	assert_nothing_happened

	run git review walkthrough draft --build --from a.md --from b.md feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"--from given more than once"* ]]
	assert_nothing_happened

	# --from with nothing after it. Note that "--from feature/plain" is NOT this
	# case: there the branch name is consumed as the file, which is a legal (if
	# mistaken) invocation and fails later, on the file it cannot read.
	run git review walkthrough draft --build --from
	[ "$status" -eq 1 ]
	[[ "$output" == *"--from requires a file (or - for standard input)"* ]]
	assert_nothing_happened

	run git review walkthrough draft --build --from= feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"--from requires a file (or - for standard input)"* ]]
	assert_nothing_happened

	# The author's side has the same circuit now (init --stdout / build --from),
	# so what is illegal there is each flag on the verb at the wrong end of it.
	git switch --quiet feature/plain
	run git review walkthrough build --stdout
	[ "$status" -eq 1 ]
	[[ "$output" == *"init --stdout"* ]]
	run git review walkthrough init --from x.md
	[ "$status" -eq 1 ]
	[[ "$output" == *"build --from"* ]]
	run git review walkthrough guide --stdout
	[ "$status" -eq 1 ]
	[[ "$output" == *"a guide has no skeleton"* ]]
	[ ! -e .review/walkthrough.md ]
}

@test "--build --force keeps its old refusal when no --from is given" {
	# --force is about replacing prose. Without --from there is no other prose to
	# put in its place, so the flag still means nothing there -- byte for byte the
	# message it has always had.
	run git review walkthrough draft feature/plain
	[ "$status" -eq 0 ]
	run git review walkthrough draft --build --force feature/plain
	[ "$status" -eq 1 ]
	[[ "$output" == *"--force applies only when creating a draft, not to --build"* ]]
}

@test "--from replaces a stored draft only with --force" {
	write_order "$TMP/filled.md"
	run git review walkthrough draft --build --from "$TMP/filled.md" feature/plain
	[ "$status" -eq 0 ]
	first="$(cat "$DRAFT")"

	sed 's/^why a$/a different why/' "$TMP/filled.md" >"$TMP/second.md"
	run git review walkthrough draft --build --from "$TMP/second.md" feature/plain
	[ "$status" -eq 1 ]
	[ "$(cat "$DRAFT")" = "$first" ]

	run git review walkthrough draft --build --force --from "$TMP/second.md" feature/plain
	[ "$status" -eq 0 ]
	grep -q 'a different why' "$DRAFT"
}
