#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

start_crlf() {
	git config core.autocrlf true
	comments_start whole
	git diff --quiet
}

@test "comments clean CRLF checkout keeps reproducible locations and validates ranges" {
	run --separate-stderr start_crlf
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --path sample.txt --side head --start-line 2 --end-line 2 --text 'Clean selection'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	[ "$(sed -n '/^unversioned /p' "$COMMENTS_LOCAL")" = '' ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments add --document local --path sample.txt --side head --start-line 99 --end-line 99 --text 'Invalid selection'
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: comment line range exceeds the captured blob' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments CRLF conversion does not conceal real edits or execute custom filters" {
	run --separate-stderr start_crlf
	[ "$status" -eq 0 ]
	printf 'extra\r\n' >>sample.txt
	run --separate-stderr git review comments add --document local --path sample.txt --side head --start-line 4 --end-line 4 --text 'Actual edit'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ "$(sed -n '/^unversioned /p' "$COMMENTS_LOCAL")" = 'unversioned 1' ]
	printf 'sample.txt filter=audit\n' >.gitattributes
	git config filter.audit.clean 'touch filter-was-run; cat'
	run --separate-stderr git review comments add --document shared --path sample.txt --side head --start-line 4 --end-line 4 --text 'Filtered file'
	[ "$status" -eq 0 ]
	[ ! -e filter-was-run ]
	comments_refresh_paths
	[ "$(sed -n '/^unversioned /p' "$COMMENTS_SHARED")" = 'unversioned 1' ]
}

@test "comments text attributes recognize CRLF independently of autocrlf" {
	git config core.autocrlf false
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	printf 'sample.txt text eol=crlf\n' >.gitattributes
	printf 'first\r\nchanged\r\nthird\r\n' >sample.txt
	run --separate-stderr git review comments add --document local --path sample.txt --side head --start-line 2 --end-line 2 --text 'Attribute conversion'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	[ "$(sed -n '/^unversioned /p' "$COMMENTS_LOCAL")" = '' ]
}

@test "comments Shared index lock failure keeps prose pending and retries only its staging" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Recoverable staged delivery'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/expected"
	comments_inject_operation mv "$COMMENTS_WORK/.review/comments.md" barrier
	git-review finish >"$COMMENTS_TMP/finish.out" 2>"$COMMENTS_TMP/finish.err" &
	local writer=$! finish_status=0 lock
	comments_barrier_arrived "$COMMENTS_TMP/inject"
	lock=$(git rev-parse --git-path index.lock)
	printf 'Another Git writer\n' >"$lock"
	comments_barrier_resume "$COMMENTS_TMP/inject"
	wait "$writer" || finish_status=$?
	[ "$finish_status" -eq 1 ]
	[[ "$(cat "$COMMENTS_TMP/finish.err")" == *'could not stage Shared comments; the Git index is locked'* ]]
	[ "$(cat "$lock")" = 'Another Git writer' ]
	cmp "$COMMENTS_TMP/expected" .review/comments.md
	[ "$(git diff --cached --name-only)" = '' ]
	rm "$lock"
	run --separate-stderr git-review comments prepare --context "$COMMENTS_CONTEXT"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(git diff --cached --name-only)" = .review/comments.md ]
	git show :.review/comments.md >"$COMMENTS_TMP/staged"
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_TMP/staged"
}

@test "comments finish stages only its Shared delivery and undo restores the original index" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	git ls-files --stage -z >"$COMMENTS_TMP/original-index"
	run --separate-stderr git review comments add --document local --text 'Private sentinel'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Public question'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/shared"
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	[ "$(git diff --cached --name-only)" = .review/comments.md ]
	git show :.review/comments.md >"$COMMENTS_TMP/staged"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_TMP/staged"
	[ "$(git rev-parse HEAD)" = "$COMMENTS_TIP" ]
	run --separate-stderr git review finish --abort
	[ "$status" -eq 0 ]
	[ ! -e .review/comments.md ]
	git ls-files --stage -z >"$COMMENTS_TMP/restored-index"
	cmp "$COMMENTS_TMP/original-index" "$COMMENTS_TMP/restored-index"
}

pending_delivery() {
	comments_start whole
	git review comments add --document shared --text 'Pending public question'
	comments_inject_operation mv "$COMMENTS_WORK/.review/comments.md" fail
	run --separate-stderr git-review finish
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'injected operation failure'* ]]
	comments_refresh_paths
}

@test "comments prepare stages Shared while preserving unrelated staged and unstaged edits" {
	pending_delivery
	printf 'later code\n' >>sample.txt
	git add sample.txt
	git ls-files --stage -- sample.txt >"$COMMENTS_TMP/code-index"
	printf 'later unstaged code\n' >>'other file.txt'
	cp 'other file.txt' "$COMMENTS_TMP/unstaged"
	rm -f .review/comments.md
	run --separate-stderr git review comments prepare --context "$COMMENTS_CONTEXT"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(git diff --cached --name-only)" = $'.review/comments.md\nsample.txt' ]
	git ls-files --stage -- sample.txt >"$COMMENTS_TMP/after-index"
	cmp "$COMMENTS_TMP/code-index" "$COMMENTS_TMP/after-index"
	cmp "$COMMENTS_TMP/unstaged" 'other file.txt'
}

@test "comments prepare preserves a concurrently staged Shared document and remains retryable" {
	pending_delivery
	printf 'Concurrent index edit after Finish\n' >.review/comments.md
	git add .review/comments.md
	git ls-files --stage -z >"$COMMENTS_TMP/index-before"
	rm .review/comments.md
	run --separate-stderr git review comments prepare --context "$COMMENTS_CONTEXT"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'Shared index entry changed'* ]]
	git ls-files --stage -z >"$COMMENTS_TMP/index-after"
	cmp "$COMMENTS_TMP/index-before" "$COMMENTS_TMP/index-after"
	git reset --quiet -- .review/comments.md
	run --separate-stderr git review comments prepare --context "$COMMENTS_CONTEXT"
	[ "$status" -eq 0 ]
	[ "$(git diff --cached --name-only)" = .review/comments.md ]
}

@test "comments ambiguous candidates expose distinct readable review descriptions without bodies" {
	local pass
	for pass in 1 2; do
		run --separate-stderr comments_start whole
		[ "$status" -eq 0 ]
		run --separate-stderr git review comments add --document shared --new-context --text "Private body $pass"
		[ "$status" -eq 0 ]
		run --separate-stderr git review finish
		[ "$status" -eq 0 ]
		git add .review/comments.md
		git commit --quiet -m "Feedback $pass" -- .review/comments.md
		git switch --quiet main
		run --separate-stderr git review clean feature/comments
		[ "$status" -eq 0 ]
	done
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-candidate" && $3=="feature/comments" && $4!="" {n++} END{print n+0}')" = 2 ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-candidate" {print $4}' | sort -u | wc -l | tr -d ' ')" = 2 ]
	[[ "$output" != *'Private body'* ]]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments delivered Shared uses repository prose and prepare does not restage manual edits" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'First delivery'
	[ "$status" -eq 0 ]
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ "$COMMENTS_SHARED" = "$COMMENTS_WORK/.review/comments.md" ]
	git show :.review/comments.md >"$COMMENTS_TMP/original-staged"
	printf '\nExplicitly reconciled prose.\n' >>"$COMMENTS_SHARED"
	run --separate-stderr git review comments prepare --context "$COMMENTS_CONTEXT"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	git show :.review/comments.md >"$COMMENTS_TMP/staged"
	cmp "$COMMENTS_TMP/original-staged" "$COMMENTS_TMP/staged"
	[ "$(tail -n 1 "$COMMENTS_SHARED")" = 'Explicitly reconciled prose.' ]
	comments_snapshot "$COMMENTS_TMP/before-repeat"
	run --separate-stderr git review comments prepare --context "$COMMENTS_CONTEXT"
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/after-repeat"
	comments_assert_snapshot "$COMMENTS_TMP/before-repeat" "$COMMENTS_TMP/after-repeat"
}
