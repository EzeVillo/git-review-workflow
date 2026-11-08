#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments paths returns the owned session paths and displayed guard in every layout" {
    for layout in whole step walk compare; do
        comments_start "$layout" >/dev/null
        git review comments add --document local --text 'Private preparation.' >/dev/null
        comments_refresh_paths
        local_path=$COMMENTS_LOCAL shared_path=$COMMENTS_SHARED
        guard=$(git review status --porcelain | awk -F '\t' '$1=="guard" {print $2}')
        session=$(git config branch.review/feature/comments.reviewcommentssession)
        comments_snapshot "$COMMENTS_TMP/before"
        run --separate-stderr git review comments paths --porcelain
        [ "$status" -eq 0 ]
        [ "$stderr" = '' ]
        [ "$output" = "$(printf 'comments-paths\t1\t%s\t%s\ncomments-path\tlocal\t%s\ncomments-path\tshared\t%s\ncomments-paths\tcomplete' "$guard" "$session" "$local_path" "$shared_path")" ]
        comments_snapshot "$COMMENTS_TMP/after"
        comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
        git review abort >/dev/null
    done
}

@test "comments paths does not select a context or create documents for a provisional session" {
    comments_start whole >/dev/null
    session=$(git config branch.review/feature/comments.reviewcommentssession)
    comments_snapshot "$COMMENTS_TMP/before"
    run --separate-stderr git review comments paths --porcelain
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "${#lines[@]}" -eq 4 ]
    [ ! -e ".git/review-comments/sessions/$session/local.md" ]
    [ ! -e ".git/review-comments/sessions/$session/shared.md" ]
    ! git config branch.review/feature/comments.reviewcommentscontext
    comments_snapshot "$COMMENTS_TMP/after"
    comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments paths reports legacy custody explicitly instead of an empty document list" {
    comments_start whole >/dev/null
    git config --unset branch.review/feature/comments.reviewcommentssession
    git config --unset branch.review/feature/comments.reviewcommentsowner
    guard=$(git review status --porcelain | awk -F '\t' '$1=="guard" {print $2}')
    comments_snapshot "$COMMENTS_TMP/before"
    run --separate-stderr git review comments paths --porcelain
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "$output" = "$(printf 'comments-paths\t1\t%s\tlegacy\ncomments-paths\tcomplete' "$guard")" ]
    comments_snapshot "$COMMENTS_TMP/after"
    comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments paths refuses missing format unsupported options and use outside a review" {
    run --separate-stderr git review comments paths --porcelain
    [ "$status" -eq 2 ]
    [ "$output" = '' ]
    [ "$stderr" = 'error: comments paths requires an active review' ]
    comments_start whole >/dev/null
    for arg in '' --all --context; do
        if [ -z "$arg" ]; then run --separate-stderr git review comments paths
        else run --separate-stderr git review comments paths --porcelain "$arg"; fi
        [ "$status" -eq 1 ]
        [ "$output" = '' ]
        if [ -z "$arg" ]; then [ "$stderr" = 'error: paths requires --porcelain' ]
        else [ "$stderr" = "error: unexpected comments argument: $arg" ]; fi
    done
    [ "$(git branch --show-current)" = review/feature/comments ]
}

@test "comments paths never scans prose hashes documents or resolves capture history" {
    comments_start step >/dev/null
    git review comments add --document local --text 'Private preparation.' >/dev/null
    comments_refresh_paths
    printf '# Broken Markdown\n<!--\n' >"$COMMENTS_LOCAL"
    export PATHS_REAL_GIT="$(command -v git)"
    mkdir "$COMMENTS_TMP/wrapper"
    cat >"$COMMENTS_TMP/wrapper/git" <<'EOF'
#!/bin/sh
case "$1" in
show|diff|merge-base|rev-list|cat-file) echo 'error: history query is forbidden' >&2; exit 29 ;;
hash-object) if [ "$2" != --stdin ]; then echo 'error: document hash is forbidden' >&2; exit 29; fi ;;
esac
exec "$PATHS_REAL_GIT" "$@"
EOF
    chmod +x "$COMMENTS_TMP/wrapper/git"
    comments_snapshot "$COMMENTS_TMP/before"
    run --separate-stderr env PATH="$COMMENTS_TMP/wrapper:$PATH" sh "$BATS_TEST_DIRNAME/../bin/git-review" comments paths --porcelain
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "${lines[3]}" = "$(printf 'comments-paths\tcomplete')" ]
    comments_snapshot "$COMMENTS_TMP/after"
    comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments paths rejects duplicate custody fields and keeps preparation unchanged" {
    comments_start whole >/dev/null
    session=$(git config branch.review/feature/comments.reviewcommentssession)
    manifest=".git/review-comments/sessions/$session/manifest"
    cp "$manifest" "$COMMENTS_TMP/original"
    for key in session context owner_gitdir custodian; do
        cp "$COMMENTS_TMP/original" "$manifest"
        awk -F '\t' -v key="$key" '$1==key {print}' "$COMMENTS_TMP/original" >>"$manifest"
        comments_snapshot "$COMMENTS_TMP/before"
        run --separate-stderr git review comments paths --porcelain
        [ "$status" -eq 1 ]
        [ "$output" = '' ]
        [ "$stderr" = 'error: comments session ownership does not match' ]
        run --separate-stderr git review save
        [ "$status" -eq 1 ]
        [ "$stderr" = 'error: comments session ownership does not match' ]
        ! git show-ref --verify --quiet refs/heads/review-saved/feature/comments
        comments_snapshot "$COMMENTS_TMP/after"
        comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
    done
}

@test "comments paths rejects missing foreign or nonregular custody before reporting any paths" {
    comments_start whole >/dev/null
    git review comments add --document local --text 'Keep this preparation.' >/dev/null
    comments_refresh_paths
    manifest="$(dirname "$COMMENTS_LOCAL")/manifest"
    cp "$manifest" "$COMMENTS_TMP/original"
    for fault in missing foreign directory; do
        cp "$COMMENTS_TMP/original" "$manifest"
        case "$fault" in
        missing) rm "$manifest" ;;
        foreign) git config branch.review/feature/comments.reviewcommentsowner '/foreign/gitdir' ;;
        directory) mkdir "$COMMENTS_SHARED" ;;
        esac
        comments_snapshot "$COMMENTS_TMP/before"
        run --separate-stderr git review comments paths --porcelain
        [ "$status" -eq 1 ]
        [ "$output" = '' ]
        case "$fault" in
        missing) [ "$stderr" = 'error: comments session ownership does not match' ] ;;
        foreign) [ "$stderr" = 'error: comments session belongs to another gitdir' ] ;;
        directory) [ "$stderr" = "error: unsafe comments path: $COMMENTS_SHARED" ] ;;
        esac
        comments_snapshot "$COMMENTS_TMP/after"
        comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
        git config branch.review/feature/comments.reviewcommentsowner "$(git rev-parse --absolute-git-dir)"
    done
}

@test "comments paths encodes percent literally while preserving Unicode spaces and plus" {
    git clone --quiet "$COMMENTS_WORK" "$COMMENTS_TMP/repo % + café"
    cd "$COMMENTS_TMP/repo % + café"
    git branch feature/comments origin/feature/comments >/dev/null
    git config reviewworkflow.base main
    comments_start whole >/dev/null
    gitdir=$(git rev-parse --absolute-git-dir)
    session=$(git config branch.review/feature/comments.reviewcommentssession)
    encoded=${gitdir//%/%25}
    run --separate-stderr git review comments paths --porcelain
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "${lines[1]}" = "$(printf 'comments-path\tlocal\t%s/review-comments/sessions/%s/local.md' "$encoded" "$session")" ]
    [ "${lines[2]}" = "$(printf 'comments-path\tshared\t%s/review-comments/sessions/%s/shared.md' "$encoded" "$session")" ]
    [ "$(git branch --show-current)" = review/feature/comments ]
}
