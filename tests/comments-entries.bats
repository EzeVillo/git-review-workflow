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

@test "comments entries reports general metadata without inventing optional location fields" {
	printf '## 12. General\n<!-- git-review-comment v1\nbase 1111111111111111111111111111111111111111\nhead 2222222222222222222222222222222222222222\n-->\nPrivate body.\n' >"$COMMENTS_LOCAL"
	local revision
	revision=$(git hash-object --no-filters "$COMMENTS_LOCAL")
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments entries --document local --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$output" = "$(printf 'comments-document\t%s\t%s\tlocal\tpresent\t%s\ncomment-entry\t1\t12\t1\tGeneral\ncomment-version\t1\t1111111111111111111111111111111111111111\t2222222222222222222222222222222222222222' "$COMMENTS_LOCAL" "$COMMENTS_CONTEXT" "$revision")" ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

invalid_metadata() {
	printf '## 9. Question\n\n<!-- git-review-comment v1\nbase %s\nhead %s\n%s\n-->\nBody.\n' "$COMMENTS_BASE" "$COMMENTS_TIP" "$1" >"$COMMENTS_LOCAL"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments entries --document local --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-diagnostic" {print $2 "\t" $3}')" = $'1\tmetadata' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-version" || $1=="comment-path" || $1=="comment-location" {print}')" = '' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments entries diagnoses an unknown side without a usable partial reference" { invalid_metadata 'side future-side'; }
@test "comments entries diagnoses a missing line endpoint" { invalid_metadata $'head-path sample.txt\nside head\nstart 2'; }
@test "comments entries diagnoses inverted coordinates" { invalid_metadata $'head-path sample.txt\nside head\nstart 3\nend 2'; }
@test "comments entries diagnoses line zero" { invalid_metadata $'head-path sample.txt\nside head\nstart 0\nend 1'; }
@test "comments entries diagnoses invalid path escapes" { invalid_metadata 'head-path sample%2Ftxt'; }
@test "comments entries diagnoses duplicate metadata keys" { invalid_metadata "base $COMMENTS_BASE"; }
@test "comments entries diagnoses a historical path escaping the repository root" { invalid_metadata 'head-path ../outside.txt'; }

@test "comments entries reports exact physical lines and visible zero with BOM CRLF" {
	cp "$BATS_TEST_DIRNAME/fixtures/comments/bom-crlf.md" "$COMMENTS_LOCAL"
	local revision
	revision=$(git hash-object --no-filters "$COMMENTS_LOCAL")
	run --separate-stderr git review comments entries --document local --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$output" = "$(printf 'comments-document\t%s\t%s\tlocal\tpresent\t%s\ncomment-entry\t1\t93\t3\tcafé\ncomment-entry\t2\t0\t6\t' "$COMMENTS_LOCAL" "$COMMENTS_CONTEXT" "$revision")" ]
	cmp "$BATS_TEST_DIRNAME/fixtures/comments/bom-crlf.md" "$COMMENTS_LOCAL"
}

@test "comments entries diagnoses an unknown metadata version but renumber preserves it" {
	printf '## 9. Question\n<!-- git-review-comment v2\nhead future\n-->\nBody.\n' >"$COMMENTS_LOCAL"
	run --separate-stderr git review comments entries --document local --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-diagnostic" {print $3}')" = metadata ]
	run --separate-stderr git review comments renumber --document local
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	printf '## 1. Question\n<!-- git-review-comment v2\nhead future\n-->\nBody.\n' >"$COMMENTS_TMP/expected"
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_LOCAL"
}

@test "comments entries treats nonadjacent HTML metadata as ordinary prose" {
	printf '## 1. Question\nBody starts here.\n<!-- git-review-comment v1\nbase %s\nhead %s\n-->\n' "$COMMENTS_BASE" "$COMMENTS_TIP" >"$COMMENTS_LOCAL"
	run --separate-stderr git review comments entries --document local --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-version" {print}')" = '' ]
}

@test "comments historical codec does not strip a decoded trailing newline" {
	printf '## 1. Question\n\n<!-- git-review-comment v1\nbase %s\nhead %s\nbase-path sample.txt\nhead-path sample.txt%%0A\n-->\n' "$COMMENTS_BASE" "$COMMENTS_TIP" >"$COMMENTS_LOCAL"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments diff --document local --entry 1 --porcelain
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comment path cannot be represented in porcelain' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments status keeps a count while diagnosing invalid reference metadata" {
	printf '## 9. Question\n<!-- git-review-comment v1\nbase invalid\n-->\nBody.\n' >"$COMMENTS_LOCAL"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-count" {print $3}')" = 1 ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-diagnostic" {print $2 "\t" $3}')" = "$(printf '%s\tmetadata' "$COMMENTS_LOCAL")" ]
}
