#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments status exposes machine owner for selective client saves" {
    run --separate-stderr comments_start whole
    [ "$status" -eq 0 ]
    run --separate-stderr git review comments add --document local --text 'Private observation.'
    [ "$status" -eq 0 ]
    comments_refresh_paths
    comments_snapshot "$COMMENTS_TMP/before"
    run --separate-stderr git review comments status --porcelain
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-owner" {print $2 "\t" $3}')" = "$(printf '%s\tfeature/comments' "$COMMENTS_CONTEXT")" ]
    [ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-owner" {print $4}')" = review/feature/comments ]
    comments_snapshot "$COMMENTS_TMP/after"
    comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments status all includes saved documents while another review is active" {
    run --separate-stderr comments_start whole
    [ "$status" -eq 0 ]
    run --separate-stderr git review comments add --document local --text 'Saved observation.'
    [ "$status" -eq 0 ]
    comments_refresh_paths
    local saved_context="$COMMENTS_CONTEXT"
    run --separate-stderr git review save
    [ "$status" -eq 0 ]
    git branch feature/other feature/comments
    run --separate-stderr git review start --offline --no-walk feature/other
    [ "$status" -eq 0 ]
    run --separate-stderr git review comments add --document shared --text 'Other observation.'
    [ "$status" -eq 0 ]
    comments_refresh_paths
    local active_context="$COMMENTS_CONTEXT"
    [ "$active_context" != "$saved_context" ]
    comments_snapshot "$COMMENTS_TMP/before"
    run --separate-stderr git review comments status --all --porcelain
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-context" {print $2}' | sort)" = "$(printf '%s\n%s\n' "$active_context" "$saved_context" | sort)" ]
    [ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-owner" && $3=="feature/comments" {print $2}')" = "$saved_context" ]
    [ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-owner" && $2=="'"$saved_context"'" {print $4}')" = review-saved/feature/comments ]
    [ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-document" {n++} END {print n}')" = 4 ]
    comments_snapshot "$COMMENTS_TMP/after"
    comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}
