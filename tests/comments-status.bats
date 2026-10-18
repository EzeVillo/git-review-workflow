#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments status reports prepared Shared before finish without writing delivery metadata" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Prepared Shared observation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery" {print $2 "\t" $3}')" = "$(printf '%s\tprepared' "$COMMENTS_CONTEXT")" ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments status fresh legacy session emits only provisional guard identity and capture" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	local guard
	guard=$(printf '%s\n' "$output" | awk -F '\t' '$1 == "comments-guard" {print $2}')
	[[ "$guard" =~ ^[0-9a-f]{40,64}$ ]]
	[ "$output" = "$(printf 'comments-guard\t%s\ncomments-identity\tfresh\tNo comments context yet.\ncomments-capture\t%s\t%s\t%s' "$guard" "$guard" "$COMMENTS_BASE" "$COMMENTS_TIP")" ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments status confirmed context reports both documents and exact counts" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_session
	cp "$BATS_TEST_DIRNAME/fixtures/comments/freeform.md" "$COMMENTS_SESSION_DIR/local.md"
	local revision guard local_path shared_path
	local_path="$COMMENTS_SESSION_DIR/local.md"
	shared_path="$COMMENTS_SESSION_DIR/shared.md"
	revision=$(git hash-object --no-filters "$local_path")
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	guard=$(printf '%s\n' "$output" | awk -F '\t' '$1 == "comments-guard" {print $2}')
	[ "$output" = "$(printf 'comments-guard\t%s\ncomments-identity\tresolved\tComments context selected.\ncomments-context\t%s\treview\tactive\t%s\tfeature/comments\ncomments-document\t%s\t%s\tlocal\tpresent\t%s\ncomments-count\t%s\t3\ncomments-document\t%s\t%s\tshared\tabsent\tabsent\ncomments-capture\t%s\t%s\t%s' "$guard" "$COMMENTS_CONTEXT" "$guard" "$local_path" "$COMMENTS_CONTEXT" "$revision" "$local_path" "$shared_path" "$COMMENTS_CONTEXT" "$guard" "$COMMENTS_BASE" "$COMMENTS_TIP")" ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments status empty has count zero but absent has no invented count" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_session
	: >"$COMMENTS_SESSION_DIR/local.md"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1 == "comments-count" {print $2 "\t" $3}')" = "$(printf '%s\t0' "$COMMENTS_SESSION_DIR/local.md")" ]
}

@test "comments status isolates malformed document and never emits bodies or a fake count" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_session
	cp "$BATS_TEST_DIRNAME/fixtures/comments/open-html.md" "$COMMENTS_SESSION_DIR/local.md"
	printf '## 8. Shared\nSECRET BODY\n' >"$COMMENTS_SESSION_DIR/shared.md"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1 == "comments-count" {print $2 "\t" $3}')" = "$(printf '%s\t1' "$COMMENTS_SESSION_DIR/shared.md")" ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1 == "comments-diagnostic" {print $2 "\t" $3}')" = "$(printf '%s\tformat' "$COMMENTS_SESSION_DIR/local.md")" ]
	[[ "$output" != *'SECRET BODY'* ]]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments status enumerates all results without selecting by recency" {
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_result
	comments_fixture_context 2222222222222222222222222222222222222222
	comments_fixture_result
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1 == "comments-context" {print $2 "\t" $4}')" = "$(printf '1111111111111111111111111111111111111111\tresult\n2222222222222222222222222222222222222222\tresult')" ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1 == "comments-document" {n++} END {print n}')" = 4 ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments status does not resolve historical objects per entry" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_session
	cp "$BATS_TEST_DIRNAME/fixtures/comments/paths-references.md" "$COMMENTS_SESSION_DIR/local.md"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1 == "comments-count" {print $3}')" = 2 ]
	[[ "$output" != *$'\tmissing-object\t'* ]]
}

@test "comments shared library has no effects when sourced" {
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr sh -eu -c '. "$1"' sh "$BATS_TEST_DIRNAME/../bin/git-review-lib.sh"
	[ "$status" -eq 0 ]
	[ "$output" = '' ]
	[ "$stderr" = '' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments status diagnoses an unreadable document without hiding the other row" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_session
	printf 'Local\n' >"$COMMENTS_SESSION_DIR/local.md"
	printf '## 7. Shared\nBody\n' >"$COMMENTS_SESSION_DIR/shared.md"
	comments_inject_operation git "$COMMENTS_SESSION_DIR/local.md" fail
	run --separate-stderr comments_driver status
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-document" {n++} END {print n}')" = 2 ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-count" {print $2 "\t" $3}')" = "$(printf '%s\t1' "$COMMENTS_SESSION_DIR/shared.md")" ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-diagnostic" {print $3}')" = read ]
}
