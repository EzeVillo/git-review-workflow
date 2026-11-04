#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

source_comments() {
	git switch --quiet feature/comments
	mkdir -p .review
	printf '# Comments\n\n## 1. First\n\nKeep or delete A.\n\n## 2. Second\n\nKeep B.\n' >.review/comments.md
	git add .review/comments.md
	git commit --quiet -m 'Shared on the PR branch'
	cp .review/comments.md "$COMMENTS_TMP/original-shared"
}

@test "comments checkout reads repository Shared without creating private state" {
	source_comments
	local gitdir
	gitdir=$(git rev-parse --absolute-git-dir)
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-document" && $4=="shared" {print $2}')" = "$COMMENTS_WORK/.review/comments.md" ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-count" {print $3}')" = 2 ]
	[ ! -e "$gitdir/review-comments" ]
	local context
	context=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-context" {print $2}')
	run --separate-stderr git review comments entries --document shared --context "$context" --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *$'comment-body\t1\tKeep or delete A.'* ]]
	run --separate-stderr git review comments add --document shared --text 'Cannot add here.'
	[ "$status" -eq 2 ]
	[ "$stderr" = 'error: comments capture requires an active review or compare' ]
	cmp "$COMMENTS_TMP/original-shared" .review/comments.md
	[ ! -e "$gitdir/review-comments" ]
}

check_saved_shared_priority() {
	source_comments
	if [ "${1:-manual}" = portable ]; then
		printf '# Comments\n\n<!-- git-review-comments v1\ncontext 1111111111111111111111111111111111111111\n-->\n\n## 1. First\n\nKeep or delete A.\n\n## 2. Second\n\nKeep B.\n' >.review/comments.md
		git commit --quiet -am 'Portable comment identity'
		cp .review/comments.md "$COMMENTS_TMP/original-shared"
	fi
	git switch --quiet main
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local prepared=$COMMENTS_SHARED
	run --separate-stderr git review comments delete --document shared --entry 1
	[ "$status" -eq 0 ]
	cp "$prepared" "$COMMENTS_TMP/saved-shared"
	run --separate-stderr git review save
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-document" && $4=="shared" {print $2}')" = "$prepared" ]
	git switch --quiet feature/comments
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-document" && $4=="shared" {print $2}')" = "$COMMENTS_WORK/.review/comments.md" ]
	cmp "$COMMENTS_TMP/original-shared" .review/comments.md
	cmp "$COMMENTS_TMP/saved-shared" "$prepared"
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ "$COMMENTS_SHARED" = "$prepared" ]
	cmp "$COMMENTS_TMP/saved-shared" "$COMMENTS_SHARED"
}

@test "comments repository Shared wins over saved preparation until continue" { check_saved_shared_priority manual; }
@test "comments portable repository Shared wins over a saved preparation with the same context" { check_saved_shared_priority portable; }

@test "comments delivered Shared check reports released preparation without private writes" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Delivered observation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/before-check"
	run --separate-stderr git review comments prepare --context "$context" --check --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery-file" && $3=="prepared" {print $4 "\t" $5}')" = $'absent\tabsent' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery-file" && $3=="destination" {print $2}')" = "$COMMENTS_WORK/.review/comments.md" ]
	comments_snapshot "$COMMENTS_TMP/after-check"
	comments_assert_snapshot "$COMMENTS_TMP/before-check" "$COMMENTS_TMP/after-check"
}

check_deleted_shared_cycle() {
	local mode=$1 ending=$2 last=${3:-0}
	source_comments
	git switch --quiet main
	run --separate-stderr comments_start "$mode"
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local prepared=$COMMENTS_SHARED context=$COMMENTS_CONTEXT
	cmp "$COMMENTS_TMP/original-shared" "$prepared"
	run --separate-stderr git review comments delete --document shared --entry 1
	[ "$status" -eq 0 ]
	if [ "$last" -eq 1 ]; then
		run --separate-stderr git review comments delete --document shared --entry 1
		[ "$status" -eq 0 ]
	fi
	cp "$prepared" "$COMMENTS_TMP/edited-shared"
	run --separate-stderr git review save
	[ "$status" -eq 0 ]
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 0 ]
	cmp "$COMMENTS_TMP/edited-shared" "$prepared"
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	cmp "$COMMENTS_TMP/edited-shared" .review/comments.md
	git show :.review/comments.md >"$COMMENTS_TMP/staged-shared"
	cmp "$COMMENTS_TMP/edited-shared" "$COMMENTS_TMP/staged-shared"
	[ ! -e "$prepared" ]
	local result
	result="$(git rev-parse --absolute-git-dir)/review-comments/results/$context"
	[ -z "$(find "$result" -name shared.md -type f -print)" ]
	run --separate-stderr git review finish --abort
	[ "$status" -eq 0 ]
	cmp "$COMMENTS_TMP/edited-shared" "$prepared"
	run --separate-stderr git review save
	[ "$status" -eq 0 ]
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 0 ]
	cmp "$COMMENTS_TMP/edited-shared" "$prepared"
	if [ "$ending" = cancel ]; then
		run --separate-stderr git review abort
		[ "$status" -eq 0 ]
		[ ! -e "$prepared" ]
		MSYS_NO_PATHCONV=1 git show feature/comments:.review/comments.md >"$COMMENTS_TMP/source-after"
		cmp "$COMMENTS_TMP/original-shared" "$COMMENTS_TMP/source-after"
	else
		run --separate-stderr git review finish
		[ "$status" -eq 0 ]
		cmp "$COMMENTS_TMP/edited-shared" .review/comments.md
		[ ! -e "$prepared" ]
	fi
}

@test "comments whole deleted entry survives saves finish undo and finish" { check_deleted_shared_cycle whole finish; }
@test "comments step deleted entry survives saves finish undo and cancel" { check_deleted_shared_cycle step cancel; }
@test "comments walk last entry deletion survives saves finish undo and finish" { check_deleted_shared_cycle walk finish 1; }
