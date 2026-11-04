#!/usr/bin/env bats
# shellcheck disable=SC2154 # bats assigns stderr through run --separate-stderr.
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	printf 'Original body\nSecond line\n' >"$COMMENTS_TMP/baseline"
	printf 'Original body\r\nSecond line\r\n' >"$COMMENTS_TMP/destination"
}
teardown() { comments_teardown; }

check_source_comparison() {
	# shellcheck disable=SC2016 # Positional arguments belong to the child shell.
	run --separate-stderr sh -eu -c '. "$1"; comments_delivery_matches_source "$2" "$3"' sh \
		"$BATS_TEST_DIRNAME/../bin/git-review-lib.sh" "$COMMENTS_TMP/baseline" "$COMMENTS_TMP/destination"
	[ "$status" -eq "$1" ]
	[ "$output" = '' ]
	[ "$stderr" = '' ]
}

@test "comments delivery accepts only CRLF conversion enabled by Git attributes" {
	printf '.review/comments.md text eol=crlf\n' >.git/info/attributes
	check_source_comparison 0
}

@test "comments delivery keeps raw byte comparison for binary attributes despite autocrlf" {
	git config core.autocrlf true
	printf '.review/comments.md -text\n' >.git/info/attributes
	check_source_comparison 1
}

@test "comments delivery keeps raw byte comparison when no text conversion is enabled" {
	check_source_comparison 1
}

@test "comments delivery does not ignore concurrent trailing spaces under autocrlf" {
	git config core.autocrlf true
	printf 'Original body \r\nSecond line\r\n' >"$COMMENTS_TMP/destination"
	check_source_comparison 1
}

@test "comments delivery does not ignore a concurrent missing final newline under autocrlf" {
	git config core.autocrlf true
	printf 'Original body\r\nSecond line' >"$COMMENTS_TMP/destination"
	check_source_comparison 1
}

@test "comments delivery does not ignore an embedded carriage return under autocrlf" {
	git config core.autocrlf true
	printf 'Original\r body\r\nSecond line\r\n' >"$COMMENTS_TMP/destination"
	check_source_comparison 1
}

@test "comments delivery comparison never executes a configured clean filter" {
	git config core.autocrlf true
	git config filter.hostile.clean 'touch FILTER_RAN; cat'
	printf '* filter=hostile text\n' >.git/info/attributes
	check_source_comparison 0
	[ ! -e FILTER_RAN ]
}

@test "comments delivery accepts converted internal lines without adding a final newline" {
	git config core.autocrlf true
	printf 'Original body\nSecond line' >"$COMMENTS_TMP/baseline"
	printf 'Original body\r\nSecond line' >"$COMMENTS_TMP/destination"
	check_source_comparison 0
}

@test "comments delivery does not ignore a changed binary suffix under autocrlf" {
	git config core.autocrlf true
	printf 'Original\000old suffix\n' >"$COMMENTS_TMP/baseline"
	printf 'Original\000new suffix\r\n' >"$COMMENTS_TMP/destination"
	check_source_comparison 1
}

@test "comments delivery does not adopt a destination edited after its EOL comparison" {
	git switch --quiet feature/comments
	mkdir .review
	printf '# Comments\n\n## 1. Original\n\nOriginal body.\n' >.review/comments.md
	git add .review/comments.md
	git commit --quiet -m 'Incoming shared prose'
	git switch --quiet main
	git config core.autocrlf true
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Prepared reply'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local prepared=$COMMENTS_SHARED writer writer_status=0
	cp "$prepared" "$COMMENTS_TMP/prepared.md"
	comments_barrier_create "$COMMENTS_TMP/eol-race"
	export COMMENTS_EOL_REAL_AWK COMMENTS_EOL_BARRIER
	COMMENTS_EOL_REAL_AWK=$(command -v awk)
	COMMENTS_EOL_BARRIER=$COMMENTS_TMP/eol-race
	# Pause after the actual source comparison, before its caller continues.
	cat >"$COMMENTS_TMP/eol-race/awk" <<'WRAPPER'
#!/bin/sh
set -eu
case "$*" in
	*'function equal_line'*)
		"$COMMENTS_EOL_REAL_AWK" "$@"
		if mkdir "$COMMENTS_EOL_BARRIER/hit" 2>/dev/null; then
			timeout "$COMMENTS_BARRIER_TIMEOUT" sh -c 'printf "ready\n" >"$1/ready"; read -r reply <"$1/release"; [ "$reply" = release ]' sh "$COMMENTS_EOL_BARRIER"
		fi
		;;
	*) exec "$COMMENTS_EOL_REAL_AWK" "$@" ;;
esac
WRAPPER
	chmod +x "$COMMENTS_TMP/eol-race/awk"
	export PATH="$COMMENTS_TMP/eol-race:$PATH"
	git-review finish >"$COMMENTS_TMP/finish.out" 2>"$COMMENTS_TMP/finish.err" &
	writer=$!
	comments_barrier_arrived "$COMMENTS_TMP/eol-race" 10
	printf '\r\nConcurrent destination owner.\r\n' >>.review/comments.md
	cp .review/comments.md "$COMMENTS_TMP/concurrent.md"
	comments_barrier_resume "$COMMENTS_TMP/eol-race" 10
	wait "$writer" || writer_status=$?
	[ "$writer_status" -eq 1 ]
	[[ "$(cat "$COMMENTS_TMP/finish.err")" == *'Shared destination changed; candidate preserved at '* ]]
	cmp "$COMMENTS_TMP/concurrent.md" .review/comments.md
	cmp "$COMMENTS_TMP/prepared.md" "$prepared"
	git show :.review/comments.md >"$COMMENTS_TMP/staged.md"
	[ "$(grep -Fc 'Prepared reply' "$COMMENTS_TMP/staged.md" || true)" = 0 ]
	comments_refresh_paths
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery" {print $3}')" = pending ]
}
