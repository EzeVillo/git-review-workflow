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
	chmod +x "$COMMENTS_TMP/transfer-bin/awk" "$COMMENTS_TMP/transfer-bin/mv"
	export PATH="$COMMENTS_TMP/transfer-bin:$PATH"
}

assert_transfer_preserved() {
	[ "$(cat "$COMMENTS_TMP/transfer.hit")" = hit ]
	[ "$(git branch --show-current)" = review/feature/comments ]
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
	intercept_transfer rename
	run --separate-stderr git review save
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	case "$stderr" in 'error: could not replace comments document; candidate preserved at '*) ;; *) false ;; esac
	assert_transfer_preserved
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
	git show-ref --verify --quiet refs/heads/review-saved/feature/comments
	[ "$(awk -F '\t' '$1=="custodian" {print $2}' "$TRANSFER_MANIFEST")" = review-saved/feature/comments ]
	cmp "$COMMENTS_TMP/local-before" "$COMMENTS_LOCAL"
	set -- "${TRANSFER_MANIFEST}.candidate."*
	[ "$#" -eq 1 ]
	[ -f "$1" ]
	[ "$(awk -F '\t' '$1=="custodian" {print $2}' "$1")" = review/feature/comments ]
}
