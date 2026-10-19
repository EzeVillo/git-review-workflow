#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

check_finish_delivery() {
	run --separate-stderr comments_start "$1"
	[ "$status" -eq 0 ]
	local tip
	tip=$(git config branch.review/feature/comments.reviewtip)
	run --separate-stderr git review comments add --document local --text 'Private observation stays private.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Shared question goes to the output.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/local"
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/shared"
	if [ "$2" = code ]; then printf 'reviewer correction\n' >>sample.txt; fi
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = review-fixes/feature/comments ]
	[ "$(git rev-parse HEAD)" = "$tip" ]
	cmp "$COMMENTS_TMP/shared" .review/comments.md
	[ "$(git ls-files -- .review/comments.md)" = '' ]
	if [ "$2" = code ]; then
		[ "$(git diff --cached --name-only)" = sample.txt ]
		[ "$(tail -n 1 sample.txt)" = 'reviewer correction' ]
	else
		[ "$(git diff --cached --name-only)" = '' ]
	fi
	comments_refresh_paths
	cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
	run --separate-stderr git review clean --keep-fixes feature/comments
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
}

@test "comments whole finish delivers Shared with no code correction commit" { check_finish_delivery whole prose; }
@test "comments whole finish delivers Shared separately from staged code corrections" { check_finish_delivery whole code; }
@test "comments walk finish delivers Shared with no code correction commit" { check_finish_delivery walk prose; }
@test "comments walk finish delivers Shared separately from staged code corrections" { check_finish_delivery walk code; }
@test "comments step finish delivers Shared with no code correction commit" { check_finish_delivery step prose; }
@test "comments step finish delivers Shared separately from staged code corrections" { check_finish_delivery step code; }

@test "comments newly chosen empty Shared is delivered as an existing zero byte file" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments init --document shared
	[ "$status" -eq 0 ]
	comments_refresh_paths
	: >"$COMMENTS_SHARED"
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	[ -f .review/comments.md ]
	[ ! -s .review/comments.md ]
	[ "$(git diff --cached --name-only)" = '' ]
	comments_refresh_paths
	[ -f "$COMMENTS_SHARED" ]
	[ ! -s "$COMMENTS_SHARED" ]
}

@test "comments successive passes continue the portable Shared while preserving old references and Local" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'First private observation.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'First Shared observation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/first-shared"
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/first-local"
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	git switch --quiet feature/comments
	git add .review/comments.md
	git commit --quiet -m 'author includes portable Shared'
	local next_tip
	next_tip=$(git rev-parse HEAD)
	run --separate-stderr git review clean feature/comments
	[ "$status" -eq 0 ]
	git switch --quiet main
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ "$COMMENTS_CONTEXT" = "$context" ]
	cmp "$COMMENTS_TMP/first-shared" "$COMMENTS_SHARED"
	cmp "$COMMENTS_TMP/first-local" "$COMMENTS_LOCAL"
	run --separate-stderr git review comments add --document shared --text 'Second Shared observation.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	local size
	size=$(wc -c <"$COMMENTS_TMP/first-shared")
	dd if="$COMMENTS_SHARED" of="$COMMENTS_TMP/preserved-prefix" bs=1 count="$size" 2>/dev/null
	cmp "$COMMENTS_TMP/first-shared" "$COMMENTS_TMP/preserved-prefix"
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/second-shared"
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$next_tip" ]
	[ "$(git diff --cached --name-only)" = '' ]
	cmp "$COMMENTS_TMP/second-shared" .review/comments.md
	comments_refresh_paths
	cmp "$COMMENTS_TMP/first-local" "$COMMENTS_LOCAL"
}
