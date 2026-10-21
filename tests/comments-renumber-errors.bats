#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments init --document local
	[ "$status" -eq 0 ]
	comments_refresh_paths
	printf '## 9. Question\nBody unchanged.\n' >"$COMMENTS_LOCAL"
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/original"
}
teardown() { comments_teardown; }

@test "comments renumber failed candidate copy retains original and recoverable candidate" {
	comments_inject_operation cp "$COMMENTS_LOCAL.candidate.*" fail
	run --separate-stderr git-review comments renumber --document local
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[[ "$stderr" == *'could not write comments candidate:'* ]]
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
	cmp "$COMMENTS_TMP/original" "$COMMENTS_LOCAL"
	[ -f "$(cat "$COMMENTS_TMP/inject/hit/argument")" ]
	[ ! -e "$COMMENTS_SHARED" ]
}

@test "comments renumber failed replacement retains original and complete candidate" {
	comments_inject_operation mv "$COMMENTS_LOCAL" fail
	run --separate-stderr git-review comments renumber --document local
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[[ "$stderr" == *'could not replace comments document; candidate preserved at '* ]]
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
	cmp "$COMMENTS_TMP/original" "$COMMENTS_LOCAL"
	local candidate
	candidate=${stderr##*candidate preserved at }
	printf '## 1. Question\nBody unchanged.\n' >"$COMMENTS_TMP/expected"
	cmp "$COMMENTS_TMP/expected" "$candidate"
	[ ! -e "$COMMENTS_SHARED" ]
}

@test "comments renumber unreadable bytes fail before any replacement and keep the other destination absent" {
	comments_inject_operation git "$COMMENTS_LOCAL" fail
	run --separate-stderr git-review comments renumber --document local
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'injected operation failure' ]
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
	cmp "$COMMENTS_TMP/original" "$COMMENTS_LOCAL"
	[ ! -e "$COMMENTS_SHARED" ]
}

@test "comments renumber preserves duplicate incomplete and missing historical metadata as raw bytes" {
	local metadata
	for metadata in "base $COMMENTS_BASE" $'head-path sample.txt\nside head\nstart 2' 'head-path future%2Ffile.txt'; do
		printf '## 9. Question\n<!-- git-review-comment v1\nbase 1111111111111111111111111111111111111111\nhead %s\n%s\n-->\nBody unchanged.\n' "$COMMENTS_TIP" "$metadata" >"$COMMENTS_LOCAL"
		printf '## 1. Question\n<!-- git-review-comment v1\nbase 1111111111111111111111111111111111111111\nhead %s\n%s\n-->\nBody unchanged.\n' "$COMMENTS_TIP" "$metadata" >"$COMMENTS_TMP/expected"
		run --separate-stderr git review comments renumber --document local
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		cmp "$COMMENTS_TMP/expected" "$COMMENTS_LOCAL"
		run --separate-stderr git review comments entries --document local --porcelain
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-diagnostic" {print $3}')" = metadata ]
	done
}

@test "comments renumber detects an external edit before replacement and preserves its complete candidate" {
	comments_inject_operation cp "$COMMENTS_LOCAL.candidate.*" barrier
	git-review comments renumber --document local >"$COMMENTS_TMP/writer.out" 2>"$COMMENTS_TMP/writer.err" &
	local writer=$!
	comments_barrier_arrived "$COMMENTS_TMP/inject"
	printf 'External editor owns these bytes now.\n' >"$COMMENTS_LOCAL"
	comments_barrier_resume "$COMMENTS_TMP/inject"
	local writer_status=0
	wait "$writer" || writer_status=$?
	[ "$writer_status" -eq 4 ]
	[ ! -s "$COMMENTS_TMP/writer.out" ]
	[[ "$(cat "$COMMENTS_TMP/writer.err")" == 'error: comments document is stale; candidate preserved at '* ]]
	printf 'External editor owns these bytes now.\n' >"$COMMENTS_TMP/external"
	cmp "$COMMENTS_TMP/external" "$COMMENTS_LOCAL"
	printf '## 1. Question\nBody unchanged.\n' >"$COMMENTS_TMP/expected"
	cmp "$COMMENTS_TMP/expected" "$(cat "$COMMENTS_TMP/inject/hit/argument")"
	[ ! -e "$COMMENTS_SHARED" ]
}
