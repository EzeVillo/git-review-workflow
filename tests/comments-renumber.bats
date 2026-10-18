#!/usr/bin/env bats
load helpers/comments
load helpers/comments-renumber
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

@test "comments renumber preserves freeform prose and repeated headings" { comments_check_renumber_fixture freeform; }
@test "comments renumber preserves all one hundred independent bodies" { comments_check_renumber_fixture hundred; }
@test "comments renumber ignores fenced quoted indented and HTML headings" { comments_check_renumber_fixture fences-html; }
@test "comments renumber preserves paths references and future keys" { comments_check_renumber_fixture paths-references; }
@test "comments renumber keeps an unclosed fence as code to EOF" { comments_check_renumber_fixture open-fence; }

@test "comments renumber rejects ambiguous HTML without rewriting any bytes" {
	cp "$BATS_TEST_DIRNAME/fixtures/comments/open-html.md" "$COMMENTS_LOCAL"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments renumber --document local
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comment boundaries could not be preserved; document unchanged' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments renumber does not create an absent document" {
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments renumber --document shared
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments document is absent' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments entries uses physical ordinal and heading line despite repeated numbers" {
	printf 'Preface\n\n## 9. First\nBody\n## 9. Second\n' >"$COMMENTS_LOCAL"
	local revision
	revision=$(git hash-object --no-filters "$COMMENTS_LOCAL")
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments entries --document local --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$output" = "$(printf 'comments-document\t%s\t%s\tlocal\tpresent\t%s\ncomment-entry\t1\t9\t3\tFirst\ncomment-entry\t2\t9\t5\tSecond' "$COMMENTS_LOCAL" "$COMMENTS_CONTEXT" "$revision")" ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}
