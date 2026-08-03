#!/usr/bin/env bats
#
# Hostile bytes in the free-text porcelain records (`subject`, `author`).
#
# These live in their own file rather than in tests/status-porcelain.bats
# because they are the new risk surface of the subject/author records and the
# only one whose failure mode is invisible: a stray tab breaks nothing you can
# see, it shifts the NEXT field over, silently (research.md Decisión 6).
#
# The guarantee this project has for paths — git quotes any control byte
# unconditionally — does NOT carry over here: a commit subject and an author
# name are written by a person, not by git, and git does not quote them. That is
# the whole reason the contract puts the free text last in its own record.
#
# So the assertion that matters in every test below is NOT "the text looks
# right". It is "no other record moved".

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

	printf 'base\n' >base.txt
	git add base.txt
	git commit --quiet -m base
	git branch -M develop

	# Every test builds its commits on feature and then switches back to develop
	# to start the review, so the range under review is always develop..feature.
	git switch --quiet -c feature
}

teardown() {
	rm -rf "$TMP"
}

# Commit <file> with subject <subject>, optionally under author name <name>.
commit_as() {
	_file="$1"
	_subject="$2"
	_name="${3:-tester}"
	printf 'x\n' >"$_file"
	git add "$_file"
	git -c "user.name=$_name" commit --quiet --allow-empty-message -m "$_subject"
}

# The porcelain line tagged <tag> at position <pos>, from the last `run` output.
# Selecting on $1 and $2 is itself the point: if a tab inside a free-text field
# had shifted anything, the label or the position of the NEXT line would no
# longer be where the contract says they are, and this would come back empty.
row() {
	printf '%s\n' "$output" | awk -F'\t' -v t="$1" -v p="$2" '$1 == t && $2 == p'
}

# Every entry/subject/author record carries its own label in field 1 and the
# positions 1..<total> in field 2, in order, with nothing missing and nothing
# extra. This is the real FR-011 assertion: it fails if any free-text byte
# displaced a field anywhere in the output, not just on the line under test.
assert_records_intact() {
	_total="$1"
	_want="$(seq 1 "$_total")"
	for _tag in entry subject author; do
		_got="$(printf '%s\n' "$output" | awk -F'\t' -v t="$_tag" '$1 == t { print $2 }')"
		[ "$_got" = "$_want" ] || {
			echo "record type $_tag: positions '$_got', expected '$_want'" >&2
			return 1
		}
	done
}

@test "a tab in the subject stays literal and shifts nothing after it" {
	commit_as one.txt "$(printf 'con\ttab')"
	commit_as two.txt plain-second
	git switch --quiet develop

	run git review start feature --offline --step
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]

	# The tab survives byte for byte: no escaping, no quoting, no substitution.
	[ "$(row subject 1)" = "$(printf 'subject\t1\tcon\ttab')" ]
	# And the record after it is untouched — label and position still in place.
	[ "$(row subject 2)" = "$(printf 'subject\t2\tplain-second')" ]
	assert_records_intact 2
}

@test "a tab in the author name stays literal and shifts nothing after it" {
	commit_as one.txt first-subject "$(printf 'no\tmbre')"
	commit_as two.txt second-subject
	git switch --quiet develop

	run git review start feature --offline --step
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]

	[ "$(row author 1)" = "$(printf 'author\t1\tno\tmbre <t@example.com>')" ]
	[ "$(row author 2)" = "$(printf 'author\t2\ttester <t@example.com>')" ]
	# The subject records sit after the author ones in the stream; a shifted
	# author field would land in them.
	[ "$(row subject 1)" = "$(printf 'subject\t1\tfirst-subject')" ]
	assert_records_intact 2
}

@test "a non-ASCII subject and author come out byte for byte" {
	# Octal escapes rather than literal UTF-8: an unambiguous byte sequence that
	# no filesystem or locale normalisation can rewrite under us.
	ACCENTED="$(printf 'a\303\261adir caf\303\251')"
	EMOJI="$(printf 'ship it \360\237\232\200')"
	AUTHOR="$(printf 'Eze Villal\303\263n')"

	commit_as one.txt "$ACCENTED" "$AUTHOR"
	commit_as two.txt "$EMOJI"
	git switch --quiet develop

	run git review start feature --offline --step
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]

	[ "$(row subject 1)" = "$(printf 'subject\t1\t%s' "$ACCENTED")" ]
	[ "$(row subject 2)" = "$(printf 'subject\t2\t%s' "$EMOJI")" ]
	[ "$(row author 1)" = "$(printf 'author\t1\t%s <t@example.com>' "$AUTHOR")" ]
	assert_records_intact 2
}

@test "an empty subject is an empty field, never a missing record" {
	# The distinction FR-004 rests on: a consumer must be able to tell "this
	# commit has no subject" from "this CLI does not report subjects". Dropping
	# the line would make the two indistinguishable.
	commit_as one.txt ""
	commit_as two.txt after-the-empty-one
	git switch --quiet develop

	run git review start feature --offline --step
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]

	[ "$(row subject 1)" = "$(printf 'subject\t1\t')" ]
	# The author of a subject-less commit is still reported.
	[ "$(row author 1)" = "$(printf 'author\t1\ttester <t@example.com>')" ]
	[ "$(row subject 2)" = "$(printf 'subject\t2\tafter-the-empty-one')" ]
	assert_records_intact 2
}

@test "an empty subject on the LAST commit still emits its record" {
	# The degenerate case of deriving the list with git log: command substitution
	# strips trailing newlines, so a trailing empty subject shortens the list
	# below <total>. Walking to <total> rather than over the list is what keeps
	# the record present with an empty field instead of silently dropping it.
	commit_as one.txt first-subject
	commit_as two.txt ""
	git switch --quiet develop

	run git review start feature --offline --step
	[ "$status" -eq 0 ]
	run git review status --porcelain
	[ "$status" -eq 0 ]

	[ "$(row subject 1)" = "$(printf 'subject\t1\tfirst-subject')" ]
	[ "$(row subject 2)" = "$(printf 'subject\t2\t')" ]
	assert_records_intact 2
}

@test "hostile bytes in one commit do not disturb the state or entry records" {
	commit_as one.txt "$(printf 'con\ttab')" "$(printf 'no\tmbre')"
	commit_as two.txt plain-second
	git switch --quiet develop

	run git review start feature --offline --step
	[ "$status" -eq 0 ]
	tip="$(git rev-parse feature)"
	c1short="$(git rev-parse --short "$(git rev-list --reverse develop..feature | sed -n 1p)")"

	run git review status --porcelain
	[ "$status" -eq 0 ]
	# The state line is still exactly the 10-field step record of the contract,
	# unaffected by anything the commits carry.
	expected="$(printf 'state\treview/feature\tfeature\t%s\tstep\tnone\t1\t2\t2\t%s' "$tip" "$c1short")"
	[ "$(printf '%s\n' "$output" | sed -n '1p')" = "$expected" ]
	[ "$(row entry 1)" = "$(printf 'entry\t1\t%s\t0' "$c1short")" ]
	assert_records_intact 2
}
