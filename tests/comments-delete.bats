#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
    comments_setup
    run --separate-stderr comments_start whole
    [ "$status" -eq 0 ]
    run --separate-stderr git review comments add --document local --text 'Private note.'
    [ "$status" -eq 0 ]
    run --separate-stderr git review comments add --document shared --text 'Shared note.'
    [ "$status" -eq 0 ]
    comments_refresh_paths
}
teardown() { comments_teardown; }

@test "comments delete removes only the chosen active document and permits adding it again" {
    cp "$COMMENTS_SHARED" "$COMMENTS_TMP/shared-before"
    local before
    before=$(git status --porcelain)
    run --separate-stderr git review comments delete --document local
    [ "$status" -eq 0 ]
    [ "$output" = 'Deleted local comments.' ]
    [ "$stderr" = '' ]
    [ ! -e "$COMMENTS_LOCAL" ]
    cmp "$COMMENTS_TMP/shared-before" "$COMMENTS_SHARED"
    [ "$(git status --porcelain)" = "$before" ]
    run --separate-stderr git review comments add --document local --text 'New private note.'
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ -f "$COMMENTS_LOCAL" ]
    run --separate-stderr git review comments entries --document local --porcelain
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-entry" {n++} END {print n+0}')" = 1 ]
}

@test "comments delete stale revision preserves both documents" {
    local revision
    revision=$(git hash-object --no-filters "$COMMENTS_LOCAL")
    printf '\nChanged after confirmation.\n' >>"$COMMENTS_LOCAL"
    cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/local-before"
    cp "$COMMENTS_SHARED" "$COMMENTS_TMP/shared-before"
    run --separate-stderr git review comments delete --document local --expect-document "$revision"
    [ "$status" -eq 4 ]
    [ "$output" = '' ]
    [ "$stderr" = 'error: comments document is stale' ]
    cmp "$COMMENTS_TMP/local-before" "$COMMENTS_LOCAL"
    cmp "$COMMENTS_TMP/shared-before" "$COMMENTS_SHARED"
}

@test "comments delete rejects a stale session guard without deleting prose" {
    cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/local-before"
    run --separate-stderr git review comments delete --document local --expect-context 1111111111111111111111111111111111111111
    [ "$status" -eq 4 ]
    [ "$output" = '' ]
    [ "$stderr" = 'error: comments context is stale' ]
    cmp "$COMMENTS_TMP/local-before" "$COMMENTS_LOCAL"
    [ -f "$COMMENTS_SHARED" ]
}

@test "comments delete removes retained results after finish without changing delivery" {
    run --separate-stderr git review finish
    [ "$status" -eq 0 ]
    run --separate-stderr git review comments status --porcelain --context "$COMMENTS_CONTEXT"
    [ "$status" -eq 0 ]
    local retained
    retained=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-document" && $4=="local" {print $2}')
    [ -f "$retained" ]
    cp "$retained" "$COMMENTS_TMP/retained-before"
    run --separate-stderr git review comments delete --document local --context "$COMMENTS_CONTEXT"
    [ "$status" -eq 0 ]
    [ "$output" = 'Deleted local comments.' ]
    [ "$stderr" = '' ]
    [ ! -e "$retained" ]
    [ -f .review/comments.md ]
}
