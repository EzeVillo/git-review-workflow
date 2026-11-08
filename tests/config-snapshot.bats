#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; export SNAPSHOT_LIB="$BATS_TEST_DIRNAME/../bin/git-review-lib.sh"; }
teardown() { comments_teardown; }

@test "snapshot reads ordinary values in the caller without decoding subprocesses" {
    git config branch.review/test.reviewsource 'feature/spaces % $() `literal` "quoted"'
    git config branch.review/test.reviewmode ''
    git config --add branch.review/test.reviewtip first
    git config --add branch.review/test.reviewtip '  último 漢字  '
    run --separate-stderr sh -eu -c '
        . "$SNAPSHOT_LIB"
        review_config_init
        [ "$_review_config_ready:$_review_config_values_ready" = 1:1 ]
        review_config_get() { echo "unexpected decoding" >&2; return 9; }
        review_config_read branch.review/test.reviewsource
        [ "$_review_config_found" = 1 ]
        printf "%s\n" "$_review_config_value"
        review_config_read branch.review/test.reviewmode whole
        [ "$_review_config_found:$_review_config_value" = 1: ]
        review_config_read branch.review/test.reviewmissing whole
        [ "$_review_config_found:$_review_config_value" = 0:whole ]
        review_config_read branch.review/test.reviewtip
        [ "$_review_config_found:$_review_config_value" = "1:  último 漢字  " ]
    '
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "$output" = 'feature/spaces % $() `literal` "quoted"' ]
}

@test "snapshot exceptional bytes match the existing scalar decoder" {
    value=$(printf 'line\n\tcarriage\rback\\slash\001\177\n\nEND')
    value=${value%END}
    git config branch.review/test.reviewsource "$value"
    run --separate-stderr sh -eu -c '
        . "$SNAPSHOT_LIB"
        expected=$(git config branch.review/test.reviewsource)
        review_config_init
        legacy=$(review_config_get branch.review/test.reviewsource)
        review_config_read branch.review/test.reviewsource
        [ "$_review_config_found" = 1 ]
        [ "$_review_config_value" = "$expected" ]
        [ "$_review_config_value" = "$legacy" ]
        review_config_read branch.review/test.reviewmissing "fallback\\literal"
        [ "$_review_config_found:$_review_config_value" = "0:fallback\\literal" ]
    '
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "$output" = '' ]
    [ "$(git config branch.review/test.reviewsource)" = "${value%$'\n\n'}" ]
}

@test "snapshot metadata remains data even with shell syntax and framing text" {
    value='$(touch injected); `touch injected`; __review_config_values__ __review_config_end__'
    git config branch.review/test.reviewsource "$value"
    run --separate-stderr sh -eu -c '
        . "$SNAPSHOT_LIB"
        review_config_init
        review_config_read branch.review/test.reviewsource
        [ "$_review_config_value" = "$(git config branch.review/test.reviewsource)" ]
        [ ! -e injected ]
    '
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "$output" = '' ]
    [ ! -e injected ]
}

@test "snapshot canonical records retain the previous guard representation" {
    git config branch.review/test.reviewsource 'Unicode ñ and spaces'
    git config branch.review/test.reviewmode ''
    git config --add branch.review/test.reviewsource "$(printf 'tab\tLF\nback\\slash')"
    {
        git config --null --get-regexp '^branch\..*\.review'
        printf '\000__review_config_ok__\n\000'
    } | od -An -v -tu1 | LC_ALL=C awk '
        {for(i=1;i<=NF;i++) {
            b=$i+0
            if(b==0) {
                if(value) printf "%s\t%s\n", key, encoded
                key=""; encoded=""; value=0
            } else if(!value && b==10) value=1
            else if(value) encoded=encoded sprintf("\\0%03o", b)
            else key=key sprintf("%c", b)
        }}' >"$COMMENTS_TMP/expected"
    run --separate-stderr sh -eu -c '
        . "$SNAPSHOT_LIB"
        review_config_init
        [ "$_review_config_ready" = 1 ]
        printf "%s\n" "$_review_config_records" >"$COMMENTS_TMP/actual"
        cmp "$COMMENTS_TMP/expected" "$COMMENTS_TMP/actual"
    '
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "$output" = '' ]
}

@test "snapshot cursor writes invalidate the readable view only after success" {
    git config branch.review/test.reviewstep 1
    run --separate-stderr sh -eu -c '
        . "$SNAPSHOT_LIB"
        review_config_init
        review_config_cursor branch.review/test.reviewstep 2
        [ "$_review_config_values_ready" = 0 ]
        review_config_read branch.review/test.reviewstep
        [ "$_review_config_value" = 2 ]
        review_config_init
        git() { return 19; }
        if review_config_cursor branch.review/test.reviewstep 3; then exit 9; fi
        [ "$_review_config_values_ready" = 1 ]
        review_config_read branch.review/test.reviewstep
        [ "$_review_config_value" = 2 ]
    '
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "$output" = '' ]
    [ "$(git config branch.review/test.reviewstep)" = 2 ]
}

@test "snapshot reload failure clears both views and never returns old metadata" {
    git config branch.review/test.reviewsource old
    run --separate-stderr sh -eu -c '
        . "$SNAPSHOT_LIB"
        review_config_init
        git() { return 19; }
        review_config_init
        [ "$_review_config_ready:$_review_config_values_ready" = 0:0 ]
        review_config_read branch.review/test.reviewsource missing
        [ "$_review_config_found:$_review_config_value" = 0:missing ]
    '
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "$output" = '' ]
}

@test "snapshot empty metadata and live reads preserve missing versus empty" {
    run --separate-stderr sh -eu -c '
        . "$SNAPSHOT_LIB"
        review_config_read branch.review/test.reviewsource fallback
        [ "$_review_config_found:$_review_config_value" = 0:fallback ]
        review_config_init
        [ "$_review_config_ready:$_review_config_values_ready" = 1:1 ]
        review_config_read branch.review/test.reviewsource fallback
        [ "$_review_config_found:$_review_config_value" = 0:fallback ]
        git config branch.review/test.reviewsource ""
        review_config_init
        review_config_read branch.review/test.reviewsource fallback
        [ "$_review_config_found:$_review_config_value" = 1: ]
    '
    [ "$status" -eq 0 ]
    [ "$stderr" = '' ]
    [ "$output" = '' ]
}
