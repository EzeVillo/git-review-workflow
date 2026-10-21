#!/usr/bin/env bats
# shellcheck disable=SC2154 # bats assigns stderr through run --separate-stderr.
load helpers/comments
load helpers/comments-team
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; team_seed_remote; }
teardown() { comments_teardown; }

@test "comments team killed publisher keeps prose and code for explicit lock recovery and undo" {
	team_clone alice
	team_cd alice
	team_start
	team_add_feedback alice
	comments_refresh_paths
	local prepared=$COMMENTS_SHARED local_path=$COMMENTS_LOCAL context=$COMMENTS_CONTEXT writer writer_status=0 lock
	cp "$prepared" "$TEAM_ROOT/prepared.md"
	cp "$local_path" "$TEAM_ROOT/local.md"
	comments_inject_operation mv '*/current' barrier
	git-review finish >"$TEAM_ROOT/finish.out" 2>"$TEAM_ROOT/finish.err" &
	writer=$!
	comments_barrier_arrived "$COMMENTS_TMP/inject"
	lock="$(git rev-parse --absolute-git-dir)/review-comments/locks/$context.lock"
	[ -f "$lock/owner" ]
	[ "$(awk -F '\t' '$1=="pid" {print $2}' "$lock/owner")" = "$writer" ]
	kill -KILL "$writer"
	wait "$writer" || writer_status=$?
	[ "$writer_status" -eq 137 ]
	comments_barrier_resume "$COMMENTS_TMP/inject"
	[ "$(git branch --show-current)" = review-fixes/feature/comments ]
	[ "$(git rev-parse HEAD)" = "$TEAM_SEED" ]
	[ "$(git diff --cached --name-only)" = "$(printf '.review/comments.md\nalice-fix.txt')" ]
	git show :.review/comments.md >"$TEAM_ROOT/staged.md"
	cmp "$TEAM_ROOT/prepared.md" "$TEAM_ROOT/staged.md"
	cmp "$TEAM_ROOT/prepared.md" "$prepared"
	cmp "$TEAM_ROOT/local.md" "$local_path"
	# Unknown locks are never stolen merely because a PID looks dead. This is
	# explicit operator recovery of this fixture's verified dead publisher.
	run --separate-stderr git-review finish --abort
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: comments context is locked' ]
	[ -f "$lock/owner" ]
	rm "$lock/owner"
	rmdir "$lock"
	team_review finish --abort
	comments_refresh_paths
	cmp "$TEAM_ROOT/prepared.md" "$COMMENTS_SHARED"
	cmp "$TEAM_ROOT/local.md" "$COMMENTS_LOCAL"
	team_review finish
	[ "$(git rev-parse HEAD)" = "$TEAM_SEED" ]
	[ "$(git diff --cached --name-only)" = "$(printf '.review/comments.md\nalice-fix.txt')" ]
	[ "$(grep -Fc 'alice question' .review/comments.md)" = 1 ]
	git commit --quiet -m 'Recovered publisher feedback'
	[ "$(git rev-list --count "$TEAM_SEED..HEAD")" = 1 ]
	git push --quiet origin HEAD:refs/heads/feature/comments
	team_assert_reader alice
}
