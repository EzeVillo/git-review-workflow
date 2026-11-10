#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	comments_start walk >/dev/null
	git review comments add --document local --text 'Preserve private transfer prose.' >/dev/null
	comments_refresh_paths
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/local-before"
	TRANSFER_MANIFEST=${COMMENTS_LOCAL%/*}/manifest
	export TRANSFER_MANIFEST TRANSFER_SOURCE=review/feature/comments TRANSFER_TARGET=review-saved/feature/comments
}
teardown() { comments_teardown; }

@test "save leaves the review intact when the return branch is in another worktree" {
	local linked="$COMMENTS_TMP/return worktree"
	local draft=.git/review-walkthrough/feature/comments.md
	local archived=.git/review-saved-walkthrough/feature/comments.md
	mkdir -p "$(dirname "$draft")"
	sed 's/Read the changed line\./Keep this draft./' .review/walkthrough.md >"$COMMENTS_TMP/draft-before"
	cp "$COMMENTS_TMP/draft-before" "$draft"
	printf 'unstaged edit\n' >>sample.txt
	git worktree add -q "$linked" main
	comments_snapshot "$COMMENTS_TMP/before"

	run --separate-stderr git review save --porcelain
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = "error: cannot save: return branch 'main' is checked out in another worktree; switch that worktree to a different branch and retry" ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	cmp "$COMMENTS_TMP/draft-before" "$draft"
	[ ! -e "$archived" ]
	[ "$(git -C "$linked" symbolic-ref --short HEAD)" = main ]

	git -C "$linked" switch -qc main-other
	run --separate-stderr git review save --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	cmp "$COMMENTS_TMP/draft-before" "$archived"
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_snapshot "$COMMENTS_TMP/resumed"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/resumed" branch head index staged unstaged worktree
	cmp "$COMMENTS_TMP/draft-before" "$draft"
	cmp "$COMMENTS_TMP/local-before" "$COMMENTS_LOCAL"
	[ ! -e "$archived" ]
}

intercept_transfer() {
	export TRANSFER_REAL_AWK="$(command -v awk)" TRANSFER_REAL_GIT="$(command -v git)" TRANSFER_REAL_MV="$(command -v mv)" TRANSFER_FAULT="$1"
	mkdir "$COMMENTS_TMP/transfer-bin"
	cat >"$COMMENTS_TMP/transfer-bin/awk" <<'EOF'
#!/bin/sh
set -eu
"$TRANSFER_REAL_AWK" "$@"
case "$*" in
*'ENVIRON["COMMENTS_CUSTODIAN"]'*)
	case "$TRANSFER_FAULT" in
	owner) "$TRANSFER_REAL_GIT" config "branch.$TRANSFER_SOURCE.reviewcommentsowner" /different/gitdir ;;
	destination) "$TRANSFER_REAL_GIT" config "branch.$TRANSFER_TARGET.reviewcommentssession" bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ;;
	session) "$TRANSFER_REAL_GIT" config branch.review/feature/comments.reviewcommentssession bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ;;
	bytes) printf 'external_change\tpreserved\n' >>"$TRANSFER_MANIFEST" ;;
	esac
	printf 'hit\n' >"$COMMENTS_TMP/transfer.hit"
	;;
esac
EOF
	cat >"$COMMENTS_TMP/transfer-bin/mv" <<'EOF'
#!/bin/sh
set -eu
if [ "$TRANSFER_FAULT" = rename ] && [ "$#" -eq 2 ] && [ "$2" = "$TRANSFER_MANIFEST" ]; then exit 71; fi
exec "$TRANSFER_REAL_MV" "$@"
EOF
	cat >"$COMMENTS_TMP/transfer-bin/git" <<'EOF'
#!/bin/sh
set -eu
if [ "$TRANSFER_FAULT" = config ] && [ "${1:-}" = config ] &&
	[ "${2:-}" = --local ] && [ "${3:-}" = "branch.$TRANSFER_TARGET.reviewcommentsowner" ] &&
	[ "$#" -eq 4 ]; then
	printf 'error: injected destination owner write failure\n' >&2
	exit 71
fi
exec "$TRANSFER_REAL_GIT" "$@"
EOF
	chmod +x "$COMMENTS_TMP/transfer-bin/awk" "$COMMENTS_TMP/transfer-bin/mv" "$COMMENTS_TMP/transfer-bin/git"
	export PATH="$COMMENTS_TMP/transfer-bin:$PATH"
}

assert_transfer_preserved() {
	[ "$(cat "$COMMENTS_TMP/transfer.hit")" = hit ]
	[ "$(git branch --show-current)" = review/feature/comments ]
	! git show-ref --verify --quiet refs/heads/review-saved/feature/comments
	cmp "$COMMENTS_TMP/local-before" "$COMMENTS_LOCAL"
	[ "$(awk -F '\t' '$1=="custodian" {print $2}' "$TRANSFER_MANIFEST")" = review/feature/comments ]
	set -- "${TRANSFER_MANIFEST}.candidate."*
	[ "$#" -eq 1 ]
	[ -f "$1" ]
	[ "$(awk -F '\t' '$1=="custodian" {print $2}' "$1")" = review-saved/feature/comments ]
}

@test "save rechecks source custody after preparing its transfer manifest" {
	intercept_transfer owner
	run --separate-stderr git review save
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments session belongs to another gitdir' ]
	assert_transfer_preserved
}

@test "save rechecks destination custody after preparing its transfer manifest" {
	intercept_transfer destination
	run --separate-stderr git review save
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: another comments session owns the destination' ]
	assert_transfer_preserved
	[ "$(git config branch.review-saved/feature/comments.reviewcommentssession)" = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ]
}

@test "save retains a changed manifest and its candidate before transferring custody" {
	intercept_transfer bytes
	run --separate-stderr git review save
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	case "$stderr" in 'error: comments document is stale; candidate preserved at '*) ;; *) false ;; esac
	assert_transfer_preserved
	[ "$(awk -F '\t' '$1=="external_change" {print $2}' "$TRANSFER_MANIFEST")" = preserved ]
}

@test "save never adopts another valid session while publishing its custody transfer" {
	other_dir=${TRANSFER_MANIFEST%/*}/../bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
	mkdir "$other_dir"
	awk -F '\t' 'BEGIN {OFS="\t"} $1=="session" {$2="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"} {print}' "$TRANSFER_MANIFEST" >"$other_dir/manifest"
	cp "$COMMENTS_LOCAL" "$other_dir/local.md"
	intercept_transfer session
	run --separate-stderr git review save
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	case "$stderr" in 'error: comments session changed; candidate preserved at '*) ;; *) false ;; esac
	assert_transfer_preserved
	[ "$(git config branch.review/feature/comments.reviewcommentssession)" = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ]
	[ "$(awk -F '\t' '$1=="custodian" {print $2}' "$other_dir/manifest")" = review/feature/comments ]
	cmp "$COMMENTS_TMP/local-before" "$other_dir/local.md"
}

@test "save preserves its original manifest and sibling candidate when transfer rename fails" {
	printf 'unstaged edit\n' >>sample.txt
	comments_snapshot "$COMMENTS_TMP/before"
	local original_path="$PATH"
	intercept_transfer rename
	run --separate-stderr git review save
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	case "$stderr" in 'error: could not replace comments document; candidate preserved at '*) ;; *) false ;; esac
	assert_transfer_preserved
	export PATH="$original_path"
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" branch head refs config index raw-index.bytes staged unstaged worktree
	run --separate-stderr git review save
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_snapshot "$COMMENTS_TMP/resumed"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/resumed" branch head refs index staged unstaged worktree
	cmp "$COMMENTS_TMP/local-before" "$COMMENTS_LOCAL"
}

@test "continue rechecks saved custody after preparing its transfer manifest" {
	run --separate-stderr git review save
	[ "$status" -eq 0 ]
	export TRANSFER_SOURCE=review-saved/feature/comments TRANSFER_TARGET=review/feature/comments
	intercept_transfer owner
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments session belongs to another gitdir' ]
	[ "$(cat "$COMMENTS_TMP/transfer.hit")" = hit ]
	[ "$(git branch --show-current)" = main ]
	! git show-ref --verify --quiet refs/heads/review/feature/comments
	git show-ref --verify --quiet refs/heads/review-saved/feature/comments
	[ "$(awk -F '\t' '$1=="custodian" {print $2}' "$TRANSFER_MANIFEST")" = review-saved/feature/comments ]
	cmp "$COMMENTS_TMP/local-before" "$COMMENTS_LOCAL"
	set -- "${TRANSFER_MANIFEST}.candidate."*
	[ "$#" -eq 1 ]
	[ -f "$1" ]
	[ "$(awk -F '\t' '$1=="custodian" {print $2}' "$1")" = review/feature/comments ]
}

@test "save removes only its partial custody keys after a config write fails" {
	git config "branch.$TRANSFER_TARGET.description" 'User metadata to preserve'
	comments_snapshot "$COMMENTS_TMP/before"
	local original_path="$PATH"
	intercept_transfer config
	run --separate-stderr sh "$BATS_TEST_DIRNAME/../bin/git-review" save
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: injected destination owner write failure' ]
	assert_transfer_preserved
	export PATH="$original_path"
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" branch head refs config index raw-index.bytes staged unstaged worktree
	run --separate-stderr git review save
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(git config "branch.$TRANSFER_TARGET.description")" = 'User metadata to preserve' ]
}

@test "continue rolls comments custody back when restoring a draft fails" {
	mkdir -p .git/review-walkthrough/feature
	cp .review/walkthrough.md "$COMMENTS_TMP/original-draft"
	cp "$COMMENTS_TMP/original-draft" .git/review-walkthrough/feature/comments.md
	run --separate-stderr git review save
	[ "$status" -eq 0 ]
	printf 'New draft while paused.\n' >.git/review-walkthrough/feature/comments.md
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	case "$stderr" in 'error: a walkthrough draft for feature/comments already exists,'*) ;; *) false ;; esac
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	[ "$(cat .git/review-walkthrough/feature/comments.md)" = 'New draft while paused.' ]
	cmp "$COMMENTS_TMP/original-draft" .git/review-saved-walkthrough/feature/comments.md
	mv .git/review-walkthrough/feature/comments.md "$COMMENTS_TMP/new-draft"
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 0 ]
	cmp "$COMMENTS_TMP/original-draft" .git/review-walkthrough/feature/comments.md
	cmp "$COMMENTS_TMP/local-before" "$COMMENTS_LOCAL"
}

@test "continue leaves a failed transfer retryable with banked edits and private prose" {
	git review abort >/dev/null
	comments_start step >/dev/null
	printf 'edit on step one\n' >>sample.txt
	git review next >/dev/null
	git review comments add --document local --text 'Preserve this step comment.' >/dev/null
	comments_refresh_paths
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/local-before"
	export TRANSFER_MANIFEST=${COMMENTS_LOCAL%/*}/manifest
	printf 'unstaged edit\n' >>sample.txt
	comments_snapshot "$COMMENTS_TMP/review-before"
	run --separate-stderr git review save
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/saved-before"
	local original_path="$PATH"
	export TRANSFER_SOURCE=review-saved/feature/comments TRANSFER_TARGET=review/feature/comments
	intercept_transfer rename
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	case "$stderr" in 'error: could not replace comments document; candidate preserved at '*) ;; *) false ;; esac
	export PATH="$original_path"
	comments_snapshot "$COMMENTS_TMP/saved-after"
	comments_assert_snapshot "$COMMENTS_TMP/saved-before" "$COMMENTS_TMP/saved-after" branch head refs config index raw-index.bytes staged unstaged worktree
	[ "$(awk -F '\t' '$1=="custodian" {print $2}' "$TRANSFER_MANIFEST")" = review-saved/feature/comments ]
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_snapshot "$COMMENTS_TMP/review-after"
	comments_assert_snapshot "$COMMENTS_TMP/review-before" "$COMMENTS_TMP/review-after" branch head index staged unstaged worktree
	git show-ref --verify --quiet refs/review-edits/feature/comments/1
	cmp "$COMMENTS_TMP/local-before" "$COMMENTS_LOCAL"
}
