#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

assert_identity() {
	local expected="$1"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1 == "comments-identity" {print $2}')" = "$expected" ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

source_document() {
	git switch --quiet feature/comments
	mkdir -p .review
	printf '%s\n' "$1" >.review/comments.md
	git add .review/comments.md
	git commit --quiet -m comments
	COMMENTS_TIP=$(git rev-parse HEAD)
	git switch --quiet main
}

@test "comments identity accepts a portable marker owned by the full range" {
	source_document '<!-- git-review-comments v1
context 1111111111111111111111111111111111111111
-->'
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	assert_identity resolved
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1 == "comments-candidate" {print $2}')" = '' ]
}

@test "comments identity manual changed document proposes fresh without losing source" {
	source_document '## 9. Manual question'
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	assert_identity fresh
	[ "$(git show "$COMMENTS_TIP:.review/comments.md")" = '## 9. Manual question' ]
}

@test "comments identity inherited marker does not continue a completed context" {
	source_document '<!-- git-review-comments v1
context 1111111111111111111111111111111111111111
-->'
	comments_fixture_context 1111111111111111111111111111111111111111
	git merge --quiet --ff-only feature/comments
	git switch --quiet feature/comments
	printf 'third change\n' >>sample.txt
	git commit --quiet -am another-pr
	git switch --quiet main
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	assert_identity fresh
}

@test "comments identity continues a unique ancestor from the same source and target" {
	comments_fixture_context 1111111111111111111111111111111111111111
	git switch --quiet feature/comments
	printf 'third change\n' >>sample.txt
	git commit --quiet -am update
	git switch --quiet main
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	assert_identity resolved
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1 == "comments-context" {print $2}')" = "$COMMENTS_CONTEXT" ]
}

@test "comments identity incompatible lineage requires explicit selection with candidates" {
	comments_fixture_context 1111111111111111111111111111111111111111
	git switch --quiet feature/comments
	git reset --hard --quiet "$COMMENTS_BASE"
	printf 'rewritten\n' >sample.txt
	git commit --quiet -am rewritten
	git switch --quiet main
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	assert_identity ambiguous
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1 == "comments-candidate" {print $2}')" = "$COMMENTS_CONTEXT" ]
}

@test "comments identity missing full base is ambiguous even with a valid delta lower" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	git config branch.review/feature/comments.reviewbase missing-base
	assert_identity ambiguous
}

@test "comments identity uses full range rather than from or delta lower" {
	source_document '<!-- git-review-comments v1
context 1111111111111111111111111111111111111111
-->'
	git switch --quiet feature/comments
	local incremental_lower
	incremental_lower=$(git rev-parse HEAD)
	printf 'after document\n' >>sample.txt
	git commit --quiet -am more
	git switch --quiet main
	run --separate-stderr git review start --offline --no-walk --from "$incremental_lower" feature/comments
	[ "$status" -eq 0 ]
	assert_identity resolved
}

@test "comments identity uses the full range when document predates the delta lower" {
	source_document '<!-- git-review-comments v1
context 1111111111111111111111111111111111111111
-->'
	git config reviewworkflowlocal.feature/comments.reviewed "$COMMENTS_TIP"
	git switch --quiet feature/comments
	printf 'after the reviewed document\n' >>sample.txt
	git commit --quiet -am delta-update
	git switch --quiet main
	run --separate-stderr git review start --offline --no-walk --delta feature/comments
	[ "$status" -eq 0 ]
	assert_identity resolved
}

@test "comments identity portable marker conflicting with local continuity is ambiguous" {
	comments_fixture_context 2222222222222222222222222222222222222222
	source_document '<!-- git-review-comments v1
context 1111111111111111111111111111111111111111
-->'
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	assert_identity ambiguous
}

@test "comments identity compare matches exact resolved endpoints only" {
	comments_fixture_context 1111111111111111111111111111111111111111 compare
	comments_fixture_result
	run --separate-stderr comments_start compare
	[ "$status" -eq 0 ]
	assert_identity resolved
}

@test "comments identity compare never joins a different pair by source name" {
	comments_fixture_context 1111111111111111111111111111111111111111 compare
	comments_fixture_result
	git switch --quiet feature/comments
	printf 'third\n' >>sample.txt
	git commit --quiet -am update
	git switch --quiet main
	run --separate-stderr comments_start compare
	[ "$status" -eq 0 ]
	assert_identity fresh
}

@test "comments identity multiple compatible contexts require a choice" {
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_context 2222222222222222222222222222222222222222
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	assert_identity ambiguous
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1 == "comments-candidate" {print $2}')" = "$(printf '1111111111111111111111111111111111111111\n2222222222222222222222222222222222222222')" ]
}

@test "comments identity ignores example document markers inside fenced preamble" {
	source_document '~~~md
<!-- git-review-comments v1
context 1111111111111111111111111111111111111111
-->
~~~
## 1. Manual'
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	assert_identity fresh
}

@test "comments identity does not interpret an unknown portable document version" {
	source_document '<!-- git-review-comments v2
context 1111111111111111111111111111111111111111
-->'
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	assert_identity ambiguous
}

@test "comments identity uses the last retained tip when base integrates only an earlier pass" {
	local earlier_tip="$COMMENTS_TIP"
	comments_fixture_context 1111111111111111111111111111111111111111
	git switch --quiet feature/comments
	printf 'new PR commit\n' >>sample.txt
	git commit --quiet -am newer-tip
	git switch --quiet main
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Review the newer tip.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	run --separate-stderr git review clean --keep-fixes feature/comments
	[ "$status" -eq 0 ]
	git switch --quiet main
	git merge --quiet --ff-only "$earlier_tip"
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	assert_identity resolved
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-context" {print $2}')" = 1111111111111111111111111111111111111111 ]
}
