#!/usr/bin/env bats
#
# Tests for the draft records of git review config --porcelain: the one surface
# a client can ask "what reading orders has this reviewer started?" without an
# active review and without naming a branch.
#
# status --porcelain cannot answer it: outside a review/* branch it exits 2 with
# an empty stdout, which is exactly how the three clients derive the no-review
# situation. config --porcelain is already consulted in the same refresh, so the
# records cost no extra invocation.

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

	# Two PRs, one of them under a namespaced branch name so the '/' shows up in
	# both the record and the path.
	git switch --quiet -c feature/checkout
	printf 'a1\na2\n' >a.txt
	mkdir -p src
	printf 'hello\n' >src/c.txt
	git add -A
	git commit --quiet -m checkout
	PREV="$(git rev-parse HEAD)"
	printf 'a1\na2\na3\n' >a.txt
	git add -A
	git commit --quiet -m more
	git push --quiet -u origin feature/checkout

	git switch --quiet develop
	git switch --quiet -c telemetry
	printf 't\n' >t.txt
	git add -A
	git commit --quiet -m telemetry
	git push --quiet -u origin telemetry

	git switch --quiet develop
	git config "reviewworkflow.feature/checkout.reviewed" "$PREV"
	git config "reviewworkflowlocal.feature/checkout.reviewed" "$PREV"

	GITDIR="$(git rev-parse --git-dir)"
	NS="$GITDIR/review-walkthrough"
}

teardown() {
	rm -rf "$TMP"
}

draft_records() {
	git review config --porcelain "$@" | awk -F'\t' '$1 == "draft"'
}

field_of() {
	draft_records | awk -F'\t' -v want="$1" -v col="$2" '$2 == want { print $col; exit }'
}

# ── nothing to report ─────────────────────────────────────────────────────────

@test "with no drafts the output is exactly what it was, and the command returns" {
	# The "returns" half is not padding. awk with no file arguments reads standard
	# input and blocks forever, and this verb runs on every panel refresh in a
	# repository that usually has no drafts at all -- the failure would be a hung
	# panel, not a red test, so it is pinned with a timeout.
	before="$(git review config --porcelain)"

	run timeout 20 git review config --porcelain
	[ "$status" -eq 0 ]
	[ -z "$(printf '%s\n' "$output" | awk -F'\t' '$1 == "draft"')" ]

	run timeout 20 git review config --porcelain feature/checkout
	[ "$status" -eq 0 ]
	[ -z "$(printf '%s\n' "$output" | awk -F'\t' '$1 == "draft"')" ]

	# And byte for byte the same output as before the records existed, which for a
	# repository with no drafts is the whole compatibility promise.
	[ "$(git review config --porcelain)" = "$before" ]
}

# ── one draft ─────────────────────────────────────────────────────────────────

@test "a freshly generated draft is reported with an absolute path and zero of N" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]

	run draft_records
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | grep -c .)" = "1" ]

	[ "$(field_of feature/checkout 2)" = "feature/checkout" ]
	dpath="$(field_of feature/checkout 3)"
	case "$dpath" in
	/* | [A-Za-z]:[/\\]*) ;;
	*)
		echo "not an absolute path: $dpath"
		false
		;;
	esac
	[ -f "$dpath" ]
	# The '/' in the branch name is a subdirectory here, exactly as it is under
	# refs/, and the record spells the name with the slash.
	case "$dpath" in
	*/review-walkthrough/feature/checkout.md) ;;
	*)
		echo "path does not point into the namespace: $dpath"
		false
		;;
	esac
	[ "$(field_of feature/checkout 4)" = "0" ]
	[ "$(field_of feature/checkout 5)" = "2" ]
}

@test "the same records come out with and without a branch argument" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]
	# Not because the verb's output is symmetric -- delta and offer exist only
	# with a branch -- but because a draft is a fact about the working tree.
	[ "$(draft_records)" = "$(draft_records feature/checkout)" ]
	[ "$(draft_records)" = "$(draft_records telemetry)" ]
}

@test "a draft of zero bytes is still reported, as zero of zero" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]
	: >"$NS/feature/checkout.md"

	# awk runs no rule for an empty file and never assigns it a FILENAME, so this
	# is the record that disappears if the enumeration stops being what decides.
	# It is also the state a draft created and not yet written is in -- the one
	# that most needs listing, so it can be opened or discarded.
	[ "$(printf '%s\n' "$(draft_records)" | grep -c .)" = "1" ]
	[ "$(field_of feature/checkout 4)" = "0" ]
	[ "$(field_of feature/checkout 5)" = "0" ]
	[ -f "$(field_of feature/checkout 3)" ]
}

@test "two drafts are two records, in a stable order, neither hiding the other" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]
	run git review walkthrough draft telemetry
	[ "$status" -eq 0 ]

	run draft_records
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | grep -c .)" = "2" ]
	[ -n "$(field_of feature/checkout 3)" ]
	[ -n "$(field_of telemetry 3)" ]
	# Stable, and never reordered by locale.
	first="$(draft_records)"
	[ "$(draft_records)" = "$first" ]
	[ "$(LC_ALL=C draft_records)" = "$first" ]
}

# ── the flags the draft was generated with ────────────────────────────────────

@test "source and range come back out of the instruction block, in all five origins" {
	assert_flags() {
		rm -rf "$NS"
		# shellcheck disable=SC2086
		run git review walkthrough draft $1 feature/checkout
		[ "$status" -eq 0 ]
		[ "$(field_of feature/checkout 6)" = "$2" ]
		[ "$(field_of feature/checkout 7)" = "$3" ]
	}

	assert_flags "" remote full
	assert_flags "--local" local full
	assert_flags "--offline" offline full
	assert_flags "--delta" remote delta
	assert_flags "--local --delta" local delta
}

@test "a draft whose block was deleted by hand reports unknown, and nothing else changes" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]
	total_before="$(field_of feature/checkout 5)"

	# Deleting the block is legal: what is lost is the ability to re-annotate
	# without asking for the skeleton again, not the draft itself.
	awk '
		index($0, "<!-- git-review-range:") == 1 { skip = 1; next }
		skip { if (index($0, "-->")) skip = 0; next }
		{ print }
	' "$NS/feature/checkout.md" >"$TMP/x.md"
	mv "$TMP/x.md" "$NS/feature/checkout.md"
	! grep -q 'git-review-range' "$NS/feature/checkout.md"

	[ "$(field_of feature/checkout 6)" = "unknown" ]
	[ "$(field_of feature/checkout 7)" = "unknown" ]
	[ "$(field_of feature/checkout 5)" = "$total_before" ]
	[ -f "$(field_of feature/checkout 3)" ]
}

# ── paused reviews ────────────────────────────────────────────────────────────

@test "a paused review takes its draft out of the report and continue brings it back" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]
	cat >"$NS/feature/checkout.md" <<'EOF'
# Walkthrough

## 1. a.txt
why a

## 2. src/c.txt
why c
EOF
	run git review walkthrough draft --build feature/checkout
	[ "$status" -eq 0 ]
	run git review start feature/checkout
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$(draft_records)" | grep -c .)" = "1" ]

	run git review save
	[ "$status" -eq 0 ]
	# Not filtered anywhere: save moved the file to the archived namespace, which
	# walk_draft_list does not walk. The separation does the work.
	[ -z "$(draft_records)" ]
	[ ! -e "$NS/feature/checkout.md" ]

	run git review continue feature/checkout
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$(draft_records)" | grep -c .)" = "1" ]
	[ "$(field_of feature/checkout 2)" = "feature/checkout" ]
}

@test "the draft of an active review is reported like any other" {
	run git review walkthrough draft feature/checkout
	[ "$status" -eq 0 ]
	cat >"$NS/feature/checkout.md" <<'EOF'
# Walkthrough

## 1. a.txt
why a

## 2. src/c.txt
why c
EOF
	run git review walkthrough draft --build feature/checkout
	[ "$status" -eq 0 ]
	run git review start feature/checkout
	[ "$status" -eq 0 ]

	# The record does not say whether a live review is reading it. Answering that
	# costs a for-each-ref plus a git config per review on a path that runs in
	# every refresh, and nothing needs the answer: the panel draws the block only
	# when there is no review at all.
	[ "$(field_of feature/checkout 2)" = "feature/checkout" ]
	[ "$(field_of feature/checkout 4)" = "2" ]
	[ "$(field_of feature/checkout 5)" = "2" ]
}
