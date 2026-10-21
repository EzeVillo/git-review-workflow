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
}
teardown() { comments_teardown; }

@test "comments historical general human diff maps a missing required blob to five with no partial output" {
	local blob
	blob=$(git rev-parse "$COMMENTS_TIP:sample.txt")
	printf '## 1. General\n<!-- git-review-comment v1\nbase %s\nhead %s\n-->\n' "$COMMENTS_BASE" "$COMMENTS_TIP" >"$COMMENTS_LOCAL"
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/original"
	rm ".git/objects/${blob:0:2}/${blob:2}"
	run --separate-stderr git review comments diff --document local --entry 1
	[ "$status" -eq 5 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: historical revision or content not found' ]
	cmp "$COMMENTS_TMP/original" "$COMMENTS_LOCAL"
}

@test "comments historical general recipe validates required blobs before emitting trees" {
	local blob
	blob=$(git rev-parse "$COMMENTS_TIP:sample.txt")
	printf '## 1. General\n<!-- git-review-comment v1\nbase %s\nhead %s\n-->\n' "$COMMENTS_BASE" "$COMMENTS_TIP" >"$COMMENTS_LOCAL"
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/original"
	rm ".git/objects/${blob:0:2}/${blob:2}"
	run --separate-stderr git review comments diff --document local --entry 1 --porcelain
	[ "$status" -eq 5 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: historical revision or content not found' ]
	cmp "$COMMENTS_TMP/original" "$COMMENTS_LOCAL"
}

@test "comments historical file recipe does not turn a missing blob into an empty side" {
	local blob
	blob=$(git rev-parse "$COMMENTS_TIP:sample.txt")
	printf '## 1. File\n<!-- git-review-comment v1\nbase %s\nhead %s\nbase-path sample.txt\nhead-path sample.txt\n-->\n' "$COMMENTS_BASE" "$COMMENTS_TIP" >"$COMMENTS_LOCAL"
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/original"
	rm ".git/objects/${blob:0:2}/${blob:2}"
	run --separate-stderr git review comments diff --document local --entry 1 --porcelain
	[ "$status" -eq 5 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: historical revision or content not found' ]
	cmp "$COMMENTS_TMP/original" "$COMMENTS_LOCAL"
}

@test "comments real shallow clone does not fetch the missing historical parent" {
	git clone --quiet --depth 1 --branch feature/comments "file://$COMMENTS_WORK" "$COMMENTS_TMP/shallow"
	cd "$COMMENTS_TMP/shallow"
	[ "$(git rev-parse --is-shallow-repository)" = true ]
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_result
	printf '## 1. General\n<!-- git-review-comment v1\nbase %s\nhead %s\n-->\n' "$COMMENTS_BASE" "$COMMENTS_TIP" >"$COMMENTS_RESULT_DIR/local.md"
	comments_snapshot "$COMMENTS_TMP/before-shallow"
	comments_inject_operation git fetch fail
	run --separate-stderr git-review comments diff --context "$COMMENTS_CONTEXT" --document local --entry 1 --porcelain
	[ "$status" -eq 5 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: historical revision or content not found' ]
	[ ! -e "$COMMENTS_TMP/inject/hit" ]
	comments_snapshot "$COMMENTS_TMP/after-shallow"
	comments_assert_snapshot "$COMMENTS_TMP/before-shallow" "$COMMENTS_TMP/after-shallow"
}
