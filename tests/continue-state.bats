#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

continue_guard() { git review list --porcelain | awk -F '\t' '$1=="continue-guard" {print $2}'; }

check_continue_state() {
	comments_start "$1" >/dev/null
	git review comments add --document local --text 'Keep private prose.' >/dev/null
	if [ "$1" != compare ]; then
		git review comments add --document shared --text 'Keep Shared prose.' >/dev/null
	fi
	comments_refresh_paths
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/local-before"
	printf 'private code edit\n' >>sample.txt
	comments_snapshot "$COMMENTS_TMP/before"
	git review save >/dev/null
	local token
	token=$(continue_guard)
	[[ "$token" =~ ^[0-9a-f]{40}$|^[0-9a-f]{64}$ ]]
	run --separate-stderr git review --expect-state "$token" continue --porcelain feature/comments
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "${lines[0]}" = $'continue-state\t1' ]
	[ "${lines[${#lines[@]}-1]}" = $'continue-state\tcomplete' ]
	printf '%s\n' "$output" | sed '1d;$d' >"$COMMENTS_TMP/reply"
	git review status --porcelain >"$COMMENTS_TMP/status"
	cmp "$COMMENTS_TMP/reply" "$COMMENTS_TMP/status"
	[ "$(git branch --show-current)" = review/feature/comments ]
	[ "$(git branch --list review-saved/feature/comments)" = '' ]
	cmp "$COMMENTS_TMP/local-before" "$COMMENTS_LOCAL"
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" index staged unstaged worktree
}

@test "continue porcelain returns authoritative whole state and preserves private work" { check_continue_state whole; }
@test "continue porcelain returns authoritative step state and preserves private work" { check_continue_state step; }
@test "continue porcelain returns authoritative walk state and preserves private work" { check_continue_state walk; }
@test "continue porcelain retains compare endpoints and readonly state" { check_continue_state compare; }

@test "continue capability and guard are additive list records only with saved reviews" {
	run --separate-stderr git review list --porcelain
	[ "$status" -eq 0 ]
	[ "$output" = '' ]
	comments_start whole >/dev/null
	git review save >/dev/null
	run --separate-stderr git review list --porcelain
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="capability" && $2=="continue-state" {n++} END {print n+0}')" -eq 1 ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="continue-guard" {n++} END {print n+0}')" -eq 1 ]
	run --separate-stderr git review status --porcelain
	[ "$status" -eq 2 ]
	[ "$output" = '' ]
	run --separate-stderr git review continue feature/comments
	[ "$status" -eq 0 ]
	[[ "$output" == 'resumed review of feature/comments '* ]]
	[[ "$output" != *'continue-state'* ]]
}

@test "continue inventory keeps the short saved ref spelling when a tag collides" {
	comments_start whole >/dev/null
	git review save >/dev/null
	git tag review-saved/feature/comments main
	local expected
	expected=$(git for-each-ref --format='%(refname:short)' refs/heads/review-saved/)
	run --separate-stderr git review list --porcelain
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="branch" && $3=="1" {print $2}')" = "$expected" ]
}

check_stale_continue() {
	comments_start whole >/dev/null
	git review save >/dev/null
	local token
	token=$(continue_guard)
	[ -n "$token" ]
	case "$1" in
		branch) git switch --quiet -c other-main ;;
		head) git commit --quiet --allow-empty -m 'Current branch moved' ;;
		ref) git update-ref refs/heads/review-saved/feature/comments "$COMMENTS_BASE" ;;
		metadata) git config branch.review-saved/feature/comments.reviewreadonly 1 ;;
	esac
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review --expect-state "$token" continue --porcelain feature/comments
	[ "$status" -eq 4 ]
	[ "$stderr" = 'error: review state changed' ]
	[ "$output" = '' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "continue rejects a changed checkout before any effect" { check_stale_continue branch; }
@test "continue rejects a changed current HEAD before any effect" { check_stale_continue head; }
@test "continue rejects a changed saved ref before any effect" { check_stale_continue ref; }
@test "continue rejects changed saved metadata before any effect" { check_stale_continue metadata; }

@test "continue inventory guards distinguish gitdirs with the same checkout and saved refs" {
	comments_start whole >/dev/null
	git review save >/dev/null
	git switch --quiet --detach HEAD
	git worktree add --quiet --detach "$COMMENTS_TMP/linked" HEAD
	local token other_token
	token=$(continue_guard)
	other_token=$(git -C "$COMMENTS_TMP/linked" review list --porcelain | awk -F '\t' '$1=="continue-guard" {print $2}')
	[ -n "$token" ]
	[ -n "$other_token" ]
	[ "$token" != "$other_token" ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git -C "$COMMENTS_TMP/linked" review --expect-state "$token" continue --porcelain feature/comments
	[ "$status" -eq 4 ]
	[ "$stderr" = 'error: review state changed' ]
	[ "$output" = '' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

check_continue_reporting_failure() {
	comments_start whole >/dev/null
	printf 'private code edit\n' >>sample.txt
	comments_snapshot "$COMMENTS_TMP/before"
	git review save >/dev/null
	local token
	token=$(continue_guard)
	[ -n "$token" ]
	export CONTINUE_REAL_GIT="$(command -v git)" CONTINUE_REPORT_FAULT=$1
	mkdir "$COMMENTS_TMP/trace"
	cat >"$COMMENTS_TMP/trace/git" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = config ] && [ "${2:-}" = --null ]; then
	if ! "$CONTINUE_REAL_GIT" show-ref --verify --quiet refs/heads/review-saved/feature/comments; then
		if [ "$CONTINUE_REPORT_FAULT" = source ]; then
			"$CONTINUE_REAL_GIT" config --unset branch.review/feature/comments.reviewsource
		else exit 7
		fi
	fi
fi
exec "$CONTINUE_REAL_GIT" "$@"
EOF
	chmod +x "$COMMENTS_TMP/trace/git"
	export PATH="$COMMENTS_TMP/trace:$PATH"
	run --separate-stderr sh "$BATS_TEST_DIRNAME/../bin/git-review" --expect-state "$token" continue --porcelain feature/comments
	[ "$status" -eq 0 ]
	[ "$stderr" = 'note: review resumed; final state could not be read' ]
	[[ "$output" != *$'continue-state\tcomplete'* ]]
	export PATH=${PATH#"$COMMENTS_TMP/trace:"}
	[ "$(git branch --show-current)" = review/feature/comments ]
	[ "$(git branch --list review-saved/feature/comments)" = '' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" index staged unstaged worktree
}

@test "continue final reporting failure does not turn a completed resume into a retry" { check_continue_reporting_failure read; }
@test "continue final report never publishes a review with missing source metadata" { check_continue_reporting_failure source; }
