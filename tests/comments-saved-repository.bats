#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

saved_portable_pair() {
	git switch --quiet feature/comments
	mkdir .review
	printf '# Comments\n\n<!-- git-review-comments v1\ncontext 1111111111111111111111111111111111111111\n-->\n\n## 1. Received\n\nOriginal Shared.\n' >.review/comments.md
	git add .review/comments.md
	git commit --quiet -m 'Portable incoming comments'
	cp .review/comments.md "$COMMENTS_TMP/repository"
	git switch --quiet main
	if [ "${1:-fresh}" = retained ]; then comments_fixture_baseline present; fi
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --path sample.txt --side head --start-line 2 --end-line 2 --text 'Saved Local sentinel'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Saved Shared sentinel'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	SAVED_LOCAL=$COMMENTS_LOCAL SAVED_SHARED=$COMMENTS_SHARED SAVED_CONTEXT=$COMMENTS_CONTEXT
	cp "$SAVED_LOCAL" "$COMMENTS_TMP/local"
	cp "$SAVED_SHARED" "$COMMENTS_TMP/shared"
	run --separate-stderr git review save
	[ "$status" -eq 0 ]
	git switch --quiet feature/comments
}

check_saved_local_projection() {
	saved_portable_pair "$1"
	comments_snapshot "$COMMENTS_TMP/before"
	comments_refresh_paths
	[ "$COMMENTS_LOCAL" = "$SAVED_LOCAL" ]
	[ "$COMMENTS_SHARED" = "$COMMENTS_WORK/.review/comments.md" ]
	cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/repository" "$COMMENTS_SHARED"
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-context" {n++} END {print n+0}')" = 1 ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-context" {print $4}')" = saved ]
	run --separate-stderr git review comments entries --context "$SAVED_CONTEXT" --document local --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[[ "$output" == *$'comment-body\t1\tSaved Local sentinel'* ]]
	run --separate-stderr git review comments diff --context "$SAVED_CONTEXT" --document local --entry 1 --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[[ "$output" == *$'comment-location\t1\thead\t2\t2'* ]]
	run --separate-stderr git review comments entries --context "$SAVED_CONTEXT" --document shared --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[[ "$output" == *$'comment-body\t1\tOriginal Shared.'* ]]
	[[ "$output" != *'Saved Shared sentinel'* ]]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	run --separate-stderr git review comments status --all --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-document" && $4=="shared" {print $2}' | sort -u)" = "$(printf '%s\n%s\n' "$SAVED_SHARED" "$COMMENTS_WORK/.review/comments.md" | sort)" ]
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ "$COMMENTS_LOCAL" = "$SAVED_LOCAL" ]
	[ "$COMMENTS_SHARED" = "$SAVED_SHARED" ]
	cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
}

@test "comments repository Shared leaves saved Local visible and queryable with the same context" { check_saved_local_projection fresh; }
@test "comments repository Shared uses saved Local instead of an older retained result" { check_saved_local_projection retained; }

@test "comments saved empty or absent Local does not resurrect the older retained result" {
	saved_portable_pair retained
	local presence
	for presence in present absent; do
		if [ "$presence" = present ]; then : >"$SAVED_LOCAL"; else rm "$SAVED_LOCAL"; fi
		comments_refresh_paths
		[ "$COMMENTS_LOCAL" = "$SAVED_LOCAL" ]
		[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-document" && $4=="local" {print $5}')" = "$presence" ]
		[ "$COMMENTS_SHARED" = "$COMMENTS_WORK/.review/comments.md" ]
		cmp "$COMMENTS_TMP/repository" "$COMMENTS_SHARED"
	done
}

@test "comments saved incoming Shared survives onto source finish undo and cancel" {
	saved_portable_pair
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 0 ]
	run --separate-stderr git review finish --onto-source
	[ "$status" -eq 0 ]
	cmp "$COMMENTS_TMP/shared" .review/comments.md
	[ ! -e "$SAVED_SHARED" ]
	run --separate-stderr git review finish --abort
	[ "$status" -eq 0 ]
	cmp "$COMMENTS_TMP/shared" "$SAVED_SHARED"
	run --separate-stderr git review abort
	[ "$status" -eq 0 ]
	[ ! -e "$SAVED_LOCAL" ]
	[ ! -e "$SAVED_SHARED" ]
	git show feature/comments:.review/comments.md >"$COMMENTS_TMP/after-cancel"
	cmp "$COMMENTS_TMP/repository" "$COMMENTS_TMP/after-cancel"
	[ "$(git status --porcelain)" = '' ]
}

@test "comments repository projection refuses saved Local deletion and repository Shared writes" {
	saved_portable_pair
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments delete --document local --context "$SAVED_CONTEXT"
	[ "$status" -eq 2 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: deleting comments requires an active preparation or retained result' ]
	run --separate-stderr git review comments delete --document shared --context "$SAVED_CONTEXT"
	[ "$status" -eq 2 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: repository Shared can only be changed inside a review' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	# Renumber remains a supported explicit CLI operation on saved prose.
	printf '## 9. Saved manual entry\nKeep this text.\n' >"$SAVED_LOCAL"
	run --separate-stderr git review comments renumber --document local --context "$SAVED_CONTEXT"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(head -n 1 "$SAVED_LOCAL")" = '## 1. Saved manual entry' ]
	cmp "$COMMENTS_TMP/repository" .review/comments.md
}
