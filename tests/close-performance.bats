#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

trace_close() {
	export CLOSE_REAL_GIT="$(command -v git)" CLOSE_CALLS="$COMMENTS_TMP/calls" CLOSE_COUNT="$COMMENTS_TMP/count"
	printf '0\n' >"$CLOSE_COUNT"
	mkdir "$COMMENTS_TMP/trace"
	cat >"$COMMENTS_TMP/trace/git" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$CLOSE_CALLS"
if [ "${1:-}" = config ] && [ "${2:-}" = --null ]; then
	n=$(cat "$CLOSE_COUNT"); n=$((n + 1)); printf '%s\n' "$n" >"$CLOSE_COUNT"
	if [ "${CLOSE_FAIL:-0}" = 1 ]; then exit 7; fi
	if [ "$n" -eq "${CLOSE_FAIL_AT:-0}" ]; then exit 7; fi
	if [ "$n" -eq "${CLOSE_CHANGE_AT:-0}" ]; then
		"$CLOSE_REAL_GIT" config branch.review/feature/comments.reviewcommentsowner /another/gitdir
	fi
	if [ "$n" -eq "${CLOSE_DEST_AT:-0}" ]; then
		"$CLOSE_REAL_GIT" config branch.review-saved/feature/comments.reviewcommentssession bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
	fi
fi
exec "$CLOSE_REAL_GIT" "$@"
EOF
	chmod +x "$COMMENTS_TMP/trace/git"
	export PATH="$COMMENTS_TMP/trace:$PATH"
}

guard() { git review status --porcelain | awk -F '\t' '$1=="guard" {print $2}'; }

@test "guarded save batches metadata reads and retains the complete review" {
	comments_start walk >/dev/null
	git review comments add --document local --text 'Keep this prose.' >/dev/null
	comments_refresh_paths
	before=$(cat "$COMMENTS_LOCAL")
	token=$(guard)
	trace_close
	run --separate-stderr sh "$BATS_TEST_DIRNAME/../bin/git-review" --expect-state "$token" save
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	# The sixth snapshot is the fresh custody check immediately before publishing
	# the transfer manifest; full Comments state is no longer reconstructed there.
	[ "$(awk '$1=="config" && $2=="--null" {n++} END {print n+0}' "$CLOSE_CALLS")" -eq 6 ]
	[ "$(awk '$1=="config" && $2 ~ /^branch.review\/feature\/comments\./ {n++} END {print n+0}' "$CLOSE_CALLS")" -eq 0 ]
	[ "$(awk '$1=="merge-base" {n++} END {print n+0}' "$CLOSE_CALLS")" -eq 0 ]
	[ "$(git branch --show-current)" = main ]
	git show-ref --verify --quiet refs/heads/review-saved/feature/comments
	[ "$(cat "$COMMENTS_LOCAL")" = "$before" ]
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/comments.reviewwalkstep)" = 1 ]
	[ "$(cat "$COMMENTS_LOCAL")" = "$before" ]
}

@test "guarded cancel batches metadata without removing custody rechecks" {
	comments_start walk >/dev/null
	token=$(guard)
	trace_close
	run --separate-stderr sh "$BATS_TEST_DIRNAME/../bin/git-review" --expect-state "$token" abort
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(awk '$1=="config" && $2=="--null" {n++} END {print n+0}' "$CLOSE_CALLS")" -eq 4 ]
	[ "$(awk '$1=="config" && $2 ~ /^branch.review\/feature\/comments\./ {n++} END {print n+0}' "$CLOSE_CALLS")" -eq 0 ]
	[ "$(git branch --show-current)" = main ]
	[ "$(git branch --list review/feature/comments)" = '' ]
	[ "$(git status --porcelain)" = '' ]
}

check_changed_owner() {
	comments_start walk >/dev/null
	git review comments add --document local --text 'Must remain recoverable.' >/dev/null
	comments_refresh_paths
	before=$(cat "$COMMENTS_LOCAL")
	token=$(guard)
	export CLOSE_CHANGE_AT=3
	trace_close
	run --separate-stderr sh "$BATS_TEST_DIRNAME/../bin/git-review" --expect-state "$token" "$1"
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: comments session belongs to another gitdir' ]
	[ "$output" = '' ]
	[ "$(git branch --show-current)" = review/feature/comments ]
	[ "$(git branch --list review-saved/feature/comments)" = '' ]
	[ "$(cat "$COMMENTS_LOCAL")" = "$before" ]
}

@test "save rereads ownership after acquiring its lock" { check_changed_owner save; }
@test "cancel rereads ownership after acquiring its lock" { check_changed_owner abort; }

@test "save refuses a destination claimed after its metadata copy" {
	comments_start walk >/dev/null
	git review comments add --document local --text 'Keep private prose on failure.' >/dev/null
	comments_refresh_paths
	before=$(cat "$COMMENTS_LOCAL")
	token=$(guard)
	export CLOSE_DEST_AT=5
	trace_close
	run --separate-stderr sh "$BATS_TEST_DIRNAME/../bin/git-review" --expect-state "$token" save
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: another comments session owns the destination' ]
	[ "$output" = '' ]
	[ "$(git branch --show-current)" = review/feature/comments ]
	[ "$(cat "$COMMENTS_LOCAL")" = "$before" ]
	[ "$(awk -F '\t' '$1=="custodian" {print $2}' "${COMMENTS_LOCAL%/*}/manifest")" = review/feature/comments ]
	[ "$(git config branch.review-saved/feature/comments.reviewcommentssession)" = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ]
}

@test "a failed post-lock snapshot keeps the active review and its prose" {
	comments_start walk >/dev/null
	git review comments add --document local --text 'Keep this after a read failure.' >/dev/null
	comments_refresh_paths
	before=$(cat "$COMMENTS_LOCAL")
	token=$(guard)
	export CLOSE_FAIL_AT=3
	trace_close
	run --separate-stderr sh "$BATS_TEST_DIRNAME/../bin/git-review" --expect-state "$token" save
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: could not read review metadata' ]
	[ "$output" = '' ]
	[ "$(git branch --show-current)" = review/feature/comments ]
	[ "$(git branch --list review-saved/feature/comments)" = '' ]
	[ "$(cat "$COMMENTS_LOCAL")" = "$before" ]
}

@test "a failed close snapshot rejects the operation without changing Git" {
	comments_start walk >/dev/null
	token=$(guard)
	comments_snapshot "$COMMENTS_TMP/before"
	export CLOSE_FAIL=1
	trace_close
	for verb in save abort; do
		run --separate-stderr sh "$BATS_TEST_DIRNAME/../bin/git-review" --expect-state "$token" "$verb"
		[ "$status" -eq 1 ]
		[ "$stderr" = 'error: could not read review metadata' ]
		[ "$output" = '' ]
	done
	unset CLOSE_FAIL
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}
