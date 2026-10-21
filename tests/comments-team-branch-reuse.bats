#!/usr/bin/env bats
# shellcheck disable=SC2154 # bats assigns stderr through run --separate-stderr.
load helpers/comments
load helpers/comments-team
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; team_seed_remote; }
teardown() { comments_teardown; }

check_reused_branch() {
	local integration=$1 original_local original_context
	team_clone author
	team_clone alice
	team_cd alice
	team_start
	team_review comments add --document local --text 'Previous PR private sentinel'
	comments_refresh_paths
	original_context=$COMMENTS_CONTEXT
	team_review finish
	team_review clean
	comments_refresh_paths
	original_local=$COMMENTS_LOCAL
	cp "$original_local" "$TEAM_ROOT/previous.local"
	git switch --quiet main
	team_cd author
	git switch --quiet main
	case "$integration" in
		ff) git merge --quiet --ff-only feature/comments ;;
		merge) git merge --quiet --no-ff feature/comments -m 'Integrate original PR' ;;
		squash) git merge --quiet --squash feature/comments; git commit --quiet -m 'Squash original PR' ;;
	esac
	git push --quiet origin main
	git push --quiet origin --delete feature/comments
	git branch -D feature/comments >/dev/null
	git switch --quiet -c feature/comments
	printf 'A different PR under the same name\n' >next-pr.txt
	git add next-pr.txt
	git commit --quiet -m 'Recreate source branch for new PR'
	git push --quiet origin feature/comments
	team_cd alice
	team_review start --no-walk feature/comments
	team_review comments status --porcelain
	local identity
	identity=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-identity" {print $2}')
	if [ "$integration" = squash ]; then
		[ "$identity" = ambiguous ]
		comments_snapshot "$TEAM_ROOT/before-ambiguous"
		run --separate-stderr git review comments add --document local --text 'Must require a choice'
		[ "$status" -eq 1 ]
		[ "$stderr" = 'error: choose --new-context or --use-context before writing comments' ]
		comments_snapshot "$TEAM_ROOT/after-ambiguous"
		comments_assert_snapshot "$TEAM_ROOT/before-ambiguous" "$TEAM_ROOT/after-ambiguous"
		team_review comments add --document local --new-context --text 'New PR observation'
	else
		[ "$identity" = fresh ]
		team_review comments add --document local --text 'New PR observation'
	fi
	comments_refresh_paths
	[ "$COMMENTS_CONTEXT" != "$original_context" ]
	[ "$(grep -Fc 'Previous PR private sentinel' "$COMMENTS_LOCAL" || true)" = 0 ]
	[ ! -e "$COMMENTS_SHARED" ]
	cmp "$TEAM_ROOT/previous.local" "$original_local"
	team_review abort
	cmp "$TEAM_ROOT/previous.local" "$original_local"
	team_assert_private
}

@test "comments team deleted branch name is fresh after fast-forward integration" { check_reused_branch ff; }
@test "comments team deleted branch name is fresh after merge integration" { check_reused_branch merge; }
@test "comments team deleted branch name needs explicit choice after squash integration" { check_reused_branch squash; }
