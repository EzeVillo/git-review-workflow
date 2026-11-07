#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

current_guard() {
	git review status --porcelain 2>/dev/null | awk -F '\t' '$1 == "guard" { print $2 }'
}

@test "guarded navigation validates context without requesting a full report" {
	comments_start walk >/dev/null
	guard=$(current_guard)
	[ "${#guard}" -eq 40 ]
	run --separate-stderr git review --expect-state "$guard" next
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(git config branch.review/feature/comments.reviewwalkstep)" = 2 ]
	[ "$guard" != "$(current_guard)" ]
}

@test "stale metadata rejects the action without collateral changes" {
	comments_start walk >/dev/null
	guard=$(current_guard)
	git config branch.review/feature/comments.reviewwalkstep 2
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review --expect-state "$guard" next
	[ "$status" -eq 4 ]
	[ "$stderr" = 'error: review state changed' ]
	[ "$output" = '' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "switching away rejects cancel and keeps the original review" {
	comments_start walk >/dev/null
	guard=$(current_guard)
	git switch --quiet main
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review --expect-state "$guard" abort
	[ "$status" -eq 4 ]
	[ "$stderr" = 'error: review state changed' ]
	git show-ref --verify --quiet refs/heads/review/feature/comments
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "code edits do not invalidate a review context" {
	comments_start walk >/dev/null
	guard=$(current_guard)
	printf 'private reviewer edit\n' >>sample.txt
	[ "$guard" = "$(current_guard)" ]
	run --separate-stderr git review --expect-state "$guard" next
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	grep -Fx 'private reviewer edit' sample.txt
}

@test "a changed HEAD or comments session rejects the captured context" {
	comments_start walk >/dev/null
	guard=$(current_guard)
	git -c user.name=Test -c user.email=test@example.com commit --quiet --allow-empty --only -m 'new HEAD'
	run --separate-stderr git review --expect-state "$guard" abort
	[ "$status" -eq 4 ]
	[ "$stderr" = 'error: review state changed' ]
	[ "$(git branch --show-current)" = review/feature/comments ]
	guard=$(current_guard)
	git config branch.review/feature/comments.reviewcommentssession changed
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review --expect-state "$guard" abort
	[ "$status" -eq 4 ]
	[ "$stderr" = 'error: review state changed' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "metadata of another review does not invalidate the active context" {
	comments_start walk >/dev/null
	guard=$(current_guard)
	git config branch.review/other.reviewwalkstep 3
	[ "$guard" = "$(current_guard)" ]
	run --separate-stderr git review --expect-state "$guard" next
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(git config branch.review/feature/comments.reviewwalkstep)" = 2 ]
}

@test "outside a review the existing report stays unchanged" {
	run --separate-stderr git review status --porcelain
	[ "$status" -eq 2 ]
	[ "$output" = '' ]
	[ "$(git branch --show-current)" = main ]
}

@test "guards are bound to their gitdir even with the same HEAD and config" {
	comments_start walk >/dev/null
	guard=$(current_guard)
	git worktree add --quiet --detach "$COMMENTS_TMP/linked" HEAD
	git -C "$COMMENTS_TMP/linked" symbolic-ref HEAD refs/heads/review/feature/comments
	run --separate-stderr git -C "$COMMENTS_TMP/linked" review --expect-state "$guard" next
	[ "$status" -eq 4 ]
	[ "$stderr" = 'error: review state changed' ]
	[ "$(git config branch.review/feature/comments.reviewwalkstep)" = 1 ]
}

@test "malformed or missing guards never execute the command" {
	comments_start walk >/dev/null
	for guard in '' bad '../../../escape'; do
		run --separate-stderr git review --expect-state "$guard" next
		[ "$status" -eq 1 ]
		[ "$stderr" = 'error: invalid expected review state' ]
		[ "$(git config branch.review/feature/comments.reviewwalkstep)" = 1 ]
	done
	run --separate-stderr git review --expect-state
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: --expect-state requires a token and a command' ]
	guard=$(current_guard)
	run --separate-stderr git review --expect-state "$guard" ''
	[ "$status" -eq 1 ]
	[ "$stderr" = "error: '' is not a git review command. See 'git review -h'." ]
	[ "$(git config branch.review/feature/comments.reviewwalkstep)" = 1 ]
}

@test "an active SHA256 review uses a 64 character context guard" {
	git init --quiet --object-format=sha256 "$COMMENTS_TMP/sha256"
	cd "$COMMENTS_TMP/sha256"
	printf 'a\n' >file.txt
	git add file.txt
	git commit --quiet -m base
	git config reviewworkflow.base main
	git switch --quiet -c feature
	printf 'b\n' >file.txt
	git commit --quiet -am change
	git switch --quiet main
	git review start --offline --no-walk feature >/dev/null
	guard=$(current_guard)
	[ "${#guard}" -eq 64 ]
	run --separate-stderr git review --expect-state "$guard" status --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *"$(printf 'guard\t%s' "$guard")" ]]
}
