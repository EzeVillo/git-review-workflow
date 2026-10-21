#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
    comments_setup
    run --separate-stderr comments_start whole
    [ "$status" -eq 0 ]
    run --separate-stderr git review comments add --document local --text 'First'
    [ "$status" -eq 0 ]
    run --separate-stderr git review comments add --document shared --text 'Keep shared'
    [ "$status" -eq 0 ]
    comments_refresh_paths
}
teardown() { comments_teardown; }

@test "comments delete entry preserves duplicate numbers metadata fences and bytes of other entries" {
    printf '\357\273\277Preface\r\n\r\n## 9. First\r\n<!-- git-review-comment v1\r\n-->\r\nKeep first\r\n\r\n## 9. Remove\nBody\n```md\n## 8. Fenced heading\n```\n<!-- hidden\n## 6. Hidden heading\n-->\n\n## 42. Last\r\nKeep last' >"$COMMENTS_LOCAL"
    printf '\357\273\277Preface\r\n\r\n## 9. First\r\n<!-- git-review-comment v1\r\n-->\r\nKeep first\r\n\r\n## 42. Last\r\nKeep last' >"$COMMENTS_TMP/expected"
    cp "$COMMENTS_SHARED" "$COMMENTS_TMP/shared"
    local before revision
    before=$(git status --porcelain)
    revision=$(git hash-object --no-filters "$COMMENTS_LOCAL")
    run --separate-stderr git review comments delete --document local --entry 2 --expect-document "$revision"
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "$output" = 'Deleted local comment entry 2.' ]
    cmp "$COMMENTS_TMP/expected" "$COMMENTS_LOCAL"
    cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
    [ "$(git status --porcelain)" = "$before" ]
    run --separate-stderr git review comments entries --document local --porcelain
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-entry" {print $2 ":" $3}')" = "$(printf '1:9\n2:42')" ]
}

@test "comments delete first and last entries keeps document BOM and does not remove document" {
    printf '\357\273\277## 8. First\r\nGone\r\n## 17. Last\nKeep' >"$COMMENTS_LOCAL"
    run --separate-stderr git review comments delete --document local --entry 1
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    printf '\357\273\277## 17. Last\nKeep' >"$COMMENTS_TMP/expected"
    cmp "$COMMENTS_TMP/expected" "$COMMENTS_LOCAL"
    run --separate-stderr git review comments delete --document local --entry 1
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    printf '\357\273\277' >"$COMMENTS_TMP/expected"
    cmp "$COMMENTS_TMP/expected" "$COMMENTS_LOCAL"
}

@test "comments delete entry rejects invalid missing and out of range ordinals without changes" {
    local ordinal
    for ordinal in 0 -1 bogus 2 999999999999999999999999; do
        comments_snapshot "$COMMENTS_TMP/before"
        run --separate-stderr git review comments delete --document local --entry "$ordinal"
        [ "$status" -eq 1 ]
        [ "$output" = '' ]
        case "$ordinal" in
            0|-1|bogus) [ "$stderr" = 'error: --entry requires a positive physical ordinal' ] ;;
            *) [ "$stderr" = 'error: comment entry not found' ] ;;
        esac
        comments_snapshot "$COMMENTS_TMP/after"
        comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
    done
}

@test "comments delete entry rejects stale documents and contexts without changes" {
    local revision
    revision=$(git hash-object --no-filters "$COMMENTS_LOCAL")
    printf '\nExternal change\n' >>"$COMMENTS_LOCAL"
    comments_snapshot "$COMMENTS_TMP/before"
    run --separate-stderr git review comments delete --document local --entry 1 --expect-document "$revision"
    [ "$status" -eq 4 ]
    [ "$output" = '' ]
    [ "$stderr" = 'error: comments document is stale' ]
    comments_snapshot "$COMMENTS_TMP/after"
    comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
    run --separate-stderr git review comments delete --document local --entry 1 --expect-context 1111111111111111111111111111111111111111
    [ "$status" -eq 4 ]
    [ "$output" = '' ]
    [ "$stderr" = 'error: comments context is stale' ]
    comments_snapshot "$COMMENTS_TMP/after"
    comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments delete entry refuses ambiguous containers without changing documents" {
    printf '## 1. First\nText\n## 2. Second\n```md\nUnclosed\n' >"$COMMENTS_LOCAL"
    comments_snapshot "$COMMENTS_TMP/before"
    run --separate-stderr git review comments delete --document local --entry 1
    [ "$status" -eq 1 ]
    [ "$output" = '' ]
    [ "$stderr" = 'error: comment boundaries could not be preserved; document unchanged' ]
    comments_snapshot "$COMMENTS_TMP/after"
    comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments delivered Shared is readable and deletion requires a review" {
    run --separate-stderr git review finish
    [ "$status" -eq 0 ]
    cp .review/comments.md "$COMMENTS_TMP/delivered"
    run --separate-stderr git review comments delete --document shared --context "$COMMENTS_CONTEXT" --entry 1
    [ "$status" -eq 2 ]
    [ "$stderr" = 'error: repository Shared can only be changed inside a review' ]
    [ "$output" = '' ]
    cmp "$COMMENTS_TMP/delivered" .review/comments.md
    run --separate-stderr git review comments entries --document shared --context "$COMMENTS_CONTEXT" --porcelain
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-entry" {n++} END {print n+0}')" = 1 ]
}

@test "comments delete entry retains complete candidate on failed publication" {
    printf '## 7. First\nRemove\n## 42. Last\r\nKeep' >"$COMMENTS_LOCAL"
    cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/original"
    comments_inject_operation mv "$COMMENTS_LOCAL" fail
    run --separate-stderr git review comments delete --document local --entry 1
    [ "$status" -eq 1 ]
    [ "$output" = '' ]
    [[ "$stderr" == *'could not replace comments document; candidate preserved at '* ]]
    cmp "$COMMENTS_TMP/original" "$COMMENTS_LOCAL"
    local candidate
    candidate=${stderr##*candidate preserved at }
    printf '## 42. Last\r\nKeep' >"$COMMENTS_TMP/expected"
    cmp "$COMMENTS_TMP/expected" "$candidate"
}

@test "comments delete entry refuses a concurrent editor and keeps recoverable deletion" {
    printf '## 7. First\nRemove\n## 42. Last\nKeep\n' >"$COMMENTS_LOCAL"
    comments_inject_operation cp '*/local.md.candidate.*' barrier
    git review comments delete --document local --entry 1 >"$COMMENTS_TMP/delete.out" 2>"$COMMENTS_TMP/delete.err" &
    local writer=$!
    comments_barrier_arrived "$COMMENTS_TMP/inject"
    printf 'External edit\n' >"$COMMENTS_LOCAL"
    comments_barrier_resume "$COMMENTS_TMP/inject"
    local writer_status=0
    wait "$writer" || writer_status=$?
    [ "$writer_status" -eq 4 ]
    [ ! -s "$COMMENTS_TMP/delete.out" ]
    [[ "$(cat "$COMMENTS_TMP/delete.err")" == 'error: comments document is stale; candidate preserved at '* ]]
    printf 'External edit\n' >"$COMMENTS_TMP/external"
    cmp "$COMMENTS_TMP/external" "$COMMENTS_LOCAL"
    printf '## 42. Last\nKeep\n' >"$COMMENTS_TMP/expected"
    cmp "$COMMENTS_TMP/expected" "$(cat "$COMMENTS_TMP/inject/hit/argument")"
    [ ! -e "$COMMENTS_ROOT/locks/$COMMENTS_CONTEXT.lock" ]
}

@test "comments delete entry keeps pending Shared delivery and prepares only remaining entries" {
    run --separate-stderr git review comments add --document shared --text 'Keep this second entry'
    [ "$status" -eq 0 ]
    comments_inject_operation mv '*/.review/comments.md' fail
    run --separate-stderr git review finish
    [ "$status" -eq 1 ]
    [[ "$stderr" == *'code was extracted but Shared comments could not be prepared'* ]]
    [ ! -e .review/comments.md ]
    run --separate-stderr git review comments delete --document shared --context "$COMMENTS_CONTEXT" --entry 1
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "$output" = 'Deleted shared comment entry 1.' ]
    run --separate-stderr git review comments status --porcelain --context "$COMMENTS_CONTEXT"
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery" {print $3}')" = pending ]
    run --separate-stderr git review comments prepare --context "$COMMENTS_CONTEXT"
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "$(LC_ALL=C grep '^## ' .review/comments.md)" = '## 2. General' ]
    grep -qx 'Keep this second entry' .review/comments.md
    if grep -q 'Keep shared' .review/comments.md; then return 1; fi
}
