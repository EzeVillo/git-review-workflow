#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "save porcelain equals the ordinary final reports in every layout" {
    for layout in whole step walk compare; do
        comments_start "$layout" >/dev/null
        git review comments add --document local --text 'Private note preserved by Save.' >/dev/null
        if [ "$layout" != compare ]; then
            git review comments add --document shared --text 'Shared preparation preserved by Save.' >/dev/null
        fi
        comments_refresh_paths
        local_path=$COMMENTS_LOCAL shared_path=$COMMENTS_SHARED
        cp "$local_path" "$COMMENTS_TMP/local"
        if [ "$layout" != compare ]; then cp "$shared_path" "$COMMENTS_TMP/shared"; fi
        printf 'private edit\n' >>sample.txt
        git diff --binary >"$COMMENTS_TMP/edits"
        guard=$(git review status --porcelain | awk -F '\t' '$1=="guard" {print $2}')
        run --separate-stderr git review --expect-state "$guard" save --porcelain
        [ "$status" -eq 0 ]
        [ "$stderr" = '' ]
        [ "${lines[0]}" = "$(printf 'save-state\t1')" ]
        [ "${lines[1]}" = "$(printf 'status\t2')" ]
        [ "${lines[${#lines[@]}-1]}" = "$(printf 'save-state\tcomplete')" ]
        printf '%s\n' "$output" | sed -n 's/^list	//p' >"$COMMENTS_TMP/reply-list"
        printf '%s\n' "$output" | sed -n 's/^config	//p' >"$COMMENTS_TMP/reply-config"
        git review list --porcelain >"$COMMENTS_TMP/list"
        git review config --porcelain >"$COMMENTS_TMP/config"
        cmp "$COMMENTS_TMP/reply-list" "$COMMENTS_TMP/list"
        cmp "$COMMENTS_TMP/reply-config" "$COMMENTS_TMP/config"
        [ "$(git branch --show-current)" = main ]
        [ -z "$(git status --porcelain)" ]
        ! git show-ref --verify --quiet refs/heads/review/feature/comments
        cmp "$COMMENTS_TMP/local" "$local_path"
        if [ "$layout" != compare ]; then cmp "$COMMENTS_TMP/shared" "$shared_path"; fi
        git review continue feature/comments >/dev/null
        comments_refresh_paths
        [ "$COMMENTS_LOCAL" = "$local_path" ]
        cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
        if [ "$layout" != compare ]; then cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"; fi
        git diff --binary >"$COMMENTS_TMP/restored"
        cmp "$COMMENTS_TMP/edits" "$COMMENTS_TMP/restored"
        git review abort >/dev/null
    done
}

@test "save without porcelain preserves human output and does no reporting" {
    comments_start whole >/dev/null
    run --separate-stderr git review save
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "$output" = 'saved review of feature/comments (whole-PR review) as review-saved/feature/comments; returned to main
resume it with git review continue' ]
    [ "$(git branch --show-current)" = main ]
    git show-ref --verify --quiet refs/heads/review-saved/feature/comments
}

@test "save porcelain refuses invalid arguments and stale identity before effects" {
    comments_start walk >/dev/null
    guard=$(git review status --porcelain | awk -F '\t' '$1=="guard" {print $2}')
    run --separate-stderr git review save --porcelain unexpected
    [ "$status" -eq 1 ]
    [[ "$stderr" == 'error: unexpected argument unexpected'* ]]
    [ "$output" = '' ]
    [ "$(git branch --show-current)" = review/feature/comments ]
    ! git show-ref --verify --quiet refs/heads/review-saved/feature/comments
    git config branch.review/feature/comments.reviewwalkstep 2
    comments_snapshot "$COMMENTS_TMP/before"
    run --separate-stderr git review --expect-state "$guard" save --porcelain
    [ "$status" -eq 4 ]
    [ "$stderr" = 'error: review state changed' ]
    [ "$output" = '' ]
    comments_snapshot "$COMMENTS_TMP/after"
    comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "a failed final report cannot turn a completed save into a failed mutation" {
    comments_start whole >/dev/null
    real_git=$(command -v git)
    mkdir "$COMMENTS_TMP/wrapper"
    cat >"$COMMENTS_TMP/wrapper/git" <<EOF
#!/bin/sh
if [ "\$1" = for-each-ref ] && [ "\$("$real_git" branch --show-current)" = main ]; then
    echo 'error: injected report failure' >&2
    exit 19
fi
exec "$real_git" "\$@"
EOF
    chmod +x "$COMMENTS_TMP/wrapper/git"
    run --separate-stderr env PATH="$COMMENTS_TMP/wrapper:$PATH" sh "$BATS_TEST_DIRNAME/../bin/git-review" save --porcelain
    [ "$status" -eq 0 ]
    [[ "$stderr" == *'error: injected report failure'* ]]
    [[ "$stderr" == *'note: review saved; final state could not be read'* ]]
    [[ "$output" != *"$(printf 'save-state\tcomplete')"* ]]
    [ "$(git branch --show-current)" = main ]
    [ -z "$(git status --porcelain)" ]
    git show-ref --verify --quiet refs/heads/review-saved/feature/comments
    ! git show-ref --verify --quiet refs/heads/review/feature/comments
}
