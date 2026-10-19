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

@test "comments renumber preserves UTF-8 BOM and CRLF" { comments_check_renumber_fixture bom-crlf; }
@test "comments renumber preserves mixed EOL and literal CR" { comments_check_renumber_fixture mixed-eol; }
@test "comments renumber preserves missing final LF" { comments_check_renumber_fixture no-final-lf; }
@test "comments renumber preserves an existing empty file" { comments_check_renumber_fixture empty; }

@test "comments prose only document remains byte identical and counts zero" {
	printf '# Prose\n\nA [link](https://example.invalid/).\n\n- A list.\n> A quote.\n### A heading.\nNo final LF' >"$COMMENTS_LOCAL"
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/expected"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments renumber --document local
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_LOCAL"
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-count" {print $3}')" = 0 ]
}
