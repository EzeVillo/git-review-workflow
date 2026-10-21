#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats assigns status/output per test.
# shellcheck disable=SC2154 # bats assigns stderr through run --separate-stderr.
load helpers/comments
load helpers/comments-team
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; team_seed_remote; }
teardown() { comments_teardown; }

check_cherry_pick() {
	local choice=$1 comment_commit code_commit expected
	team_clone alice
	team_cd alice
	team_start
	team_add_feedback alice
	team_review finish
	git commit --quiet -m 'Publish comments separately' -- .review/comments.md
	comment_commit=$(git rev-parse HEAD)
	git commit --quiet -m 'Publish code separately'
	code_commit=$(git rev-parse HEAD)
	git push --quiet origin HEAD:refs/heads/feedback-alice
	team_clone author
	team_cd author
	git switch --quiet feature/comments
	printf 'Author advances independently\n' >author.txt
	git add author.txt
	git commit --quiet -m 'Advance before cherry-pick'
	case "$choice" in
		comments) team_ok git cherry-pick "$comment_commit" ;;
		code) team_ok git cherry-pick "$code_commit" ;;
		both) team_ok git cherry-pick "$comment_commit" "$code_commit" ;;
	esac
	git push --quiet origin feature/comments
	team_clone reader
	team_cd reader
	team_start
	comments_refresh_paths
	[ "$COMMENTS_CONTEXT" = "$TEAM_CONTEXT" ]
	[ ! -e "$COMMENTS_LOCAL" ]
	team_review comments entries --document shared --porcelain
	expected=$(printf 'Initial team question\nUnchanged team note')
	if [ "$choice" != code ]; then expected=$(printf '%s\nalice question' "$expected"); fi
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-body" && $3!="" {print $3}')" = "$expected" ]
	if [ "$choice" = comments ]; then [ ! -e alice-fix.txt ]; else [ "$(cat alice-fix.txt)" = 'alice correction' ]; fi
	if [ "$choice" != code ]; then
		team_review comments diff --document shared --entry 3 --porcelain
		printf '%s\n' "$output" | awk -F '\t' '$1=="comment-diff" {print $3 "\t" $4} $1=="comment-blob" {print}' >"$TEAM_ROOT/actual.recipe"
		cmp "$TEAM_ROOT/alice.recipe" "$TEAM_ROOT/actual.recipe"
	fi
	team_assert_private
}

@test "comments team cherry-pick of comments alone transfers prose and original references" { check_cherry_pick comments; }
@test "comments team cherry-pick of code alone does not transfer private or new shared prose" { check_cherry_pick code; }
@test "comments team cherry-pick of code and comments transfers each exactly once" { check_cherry_pick both; }

check_changed_path() {
	local change=$1 old_blob
	team_clone author
	team_cd author
	git switch --quiet feature/comments
	old_blob=$(git rev-parse "$TEAM_CAPTURE:sample.txt")
	case "$change" in
		rename) git mv sample.txt renamed.txt ;;
		delete) git rm --quiet sample.txt ;;
		rewrite) printf 'Completely rewritten\n' >sample.txt ;;
	esac
	git add -A
	git commit --quiet -m "Author $change after observation"
	git push --quiet origin feature/comments
	team_clone reader
	team_cd reader
	team_start
	comments_refresh_paths
	comments_snapshot "$TEAM_ROOT/before-history"
	team_review comments diff --document shared --entry 1 --porcelain
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-blob" && $3=="head" {print $5}')" = "$old_blob" ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-blob" && $3=="head" {print $2}')" = sample.txt ]
	team_review comments diff --document shared --entry 1
	[[ "$output" == *'+changed'* ]]
	[[ "$output" != *'Completely rewritten'* ]]
	comments_snapshot "$TEAM_ROOT/after-history"
	comments_assert_snapshot "$TEAM_ROOT/before-history" "$TEAM_ROOT/after-history"
}

@test "comments team renamed file keeps the original observation diff" { check_changed_path rename; }
@test "comments team deleted file keeps the original observation diff" { check_changed_path delete; }
@test "comments team rewritten file keeps the original observation diff" { check_changed_path rewrite; }

@test "comments team shallow checkout reads public prose without fetching missing history" {
	git clone --quiet --depth 1 --branch feature/comments "file://$TEAM_REMOTE" "$TEAM_ROOT/reader"
	team_cd reader
	[ "$(git rev-parse --is-shallow-repository)" = true ]
	[ ! -e .git/review-comments ]
	comments_snapshot "$TEAM_ROOT/before-shallow"
	team_review comments entries --document shared --porcelain
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-body" && $3!="" {print $3}')" = "$(printf 'Initial team question\nUnchanged team note')" ]
	run --separate-stderr git review comments diff --document shared --entry 1 --porcelain
	[ "$status" -eq 5 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: historical revision or content not found' ]
	comments_snapshot "$TEAM_ROOT/after-shallow"
	comments_assert_snapshot "$TEAM_ROOT/before-shallow" "$TEAM_ROOT/after-shallow"
	[ ! -e .git/review-comments ]
}

check_eol_delivery() {
	local eol=$1 prepared revision
	team_clone alice
	team_cd alice
	git config core.autocrlf "$eol"
	# Both content filters are deliberately hostile. Product capture/delivery
	# must not execute them or use the working copy as the staged blob source.
	git config filter.hostile.clean 'echo clean-filter-invoked >&2; exit 1'
	git config filter.hostile.smudge 'echo smudge-filter-invoked >&2; exit 1'
	printf '.review/comments.md filter=hostile\n' >.git/info/attributes
	team_start
	team_review comments add --document shared --text 'Cross-platform reply'
	comments_refresh_paths
	prepared=$COMMENTS_SHARED
	cp "$prepared" "$TEAM_ROOT/prepared.md"
	revision=$(git hash-object --no-filters "$prepared")
	# Avoid invoking filters in the independent code-extraction phase. The
	# original imported Shared still has this clone's checkout EOL conversion.
	printf '.review/comments.md -filter\n' >.git/info/attributes
	team_review finish
	team_review comments status --porcelain
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery" {print $3}')" = delivered ]
	[ "$(git rev-parse :.review/comments.md)" = "$revision" ]
	git show :.review/comments.md >"$TEAM_ROOT/staged.md"
	cmp "$TEAM_ROOT/prepared.md" "$TEAM_ROOT/staged.md"
	[ ! -e "$prepared" ]
	team_review finish --abort
	cmp "$TEAM_ROOT/prepared.md" "$prepared"
	team_review abort
	[ "$(git status --porcelain)" = '' ]
}

@test "comments team imported Shared delivers under CRLF checkout conversion" { check_eol_delivery true; }
@test "comments team imported Shared delivers under input checkout conversion" { check_eol_delivery input; }

@test "comments team two real linked worktrees keep separate session custody" {
	team_clone alice
	team_cd alice
	local primary=$COMMENTS_WORK linked="$TEAM_ROOT/linked" left_local left_shared right_local right_shared
	git branch feature/parallel feature/comments
	git worktree add --quiet -b linked-home "$linked" main
	team_start
	team_review comments add --document local --text 'Left private observation'
	team_review comments add --document shared --text 'Left shared observation'
	comments_refresh_paths
	left_local=$COMMENTS_LOCAL left_shared=$COMMENTS_SHARED
	cp "$left_local" "$TEAM_ROOT/left.local"
	cp "$left_shared" "$TEAM_ROOT/left.shared"
	cd "$linked"
	COMMENTS_WORK=$(git rev-parse --show-toplevel)
	team_review start --offline --no-walk feature/parallel
	team_review comments add --document local --text 'Right private observation'
	team_review comments add --document shared --text 'Right shared observation'
	comments_refresh_paths
	right_local=$COMMENTS_LOCAL right_shared=$COMMENTS_SHARED
	[ "$left_local" != "$right_local" ]
	cp "$right_local" "$TEAM_ROOT/right.local"
	cp "$right_shared" "$TEAM_ROOT/right.shared"
	team_review save
	cd "$primary"
	COMMENTS_WORK=$primary
	team_review abort
	[ ! -e "$left_local" ]
	[ ! -e "$left_shared" ]
	cmp "$TEAM_ROOT/right.local" "$right_local"
	cmp "$TEAM_ROOT/right.shared" "$right_shared"
	cd "$linked"
	COMMENTS_WORK=$(git rev-parse --show-toplevel)
	team_review continue feature/parallel
	comments_refresh_paths
	[ "$COMMENTS_LOCAL" = "$right_local" ]
	[ "$COMMENTS_SHARED" = "$right_shared" ]
	team_review finish
	[ "$(grep -Fc 'Right shared observation' .review/comments.md)" = 1 ]
	[ "$(grep -Fc 'Left shared observation' .review/comments.md || true)" = 0 ]
	team_review finish --abort
	team_review abort
	[ ! -e "$right_local" ]
	[ ! -e "$right_shared" ]
}

check_active_rebase() {
	local mode=$1 prepared guard old_tip
	team_clone author
	team_clone bob
	team_cd bob
	team_start "$mode"
	team_add_feedback bob
	comments_refresh_paths
	prepared=$COMMENTS_SHARED guard=$COMMENTS_GUARD old_tip=$(git config branch.review/feature/comments.reviewtip)
	cp "$prepared" "$TEAM_ROOT/bob.prepared"
	team_cd author
	git switch --quiet main
	printf 'Advanced main\n' >advance.txt
	git add advance.txt
	git commit --quiet -m 'Advance integration base'
	git push --quiet origin main
	git switch --quiet feature/comments
	git rebase --quiet main
	git push --quiet --force-with-lease origin feature/comments
	team_cd bob
	git fetch --quiet origin
	git branch --force feature/comments origin/feature/comments
	comments_refresh_paths
	[ "$COMMENTS_GUARD" = "$guard" ]
	[ "$(git config branch.review/feature/comments.reviewtip)" = "$old_tip" ]
	[ "$(git rev-parse origin/feature/comments)" != "$old_tip" ]
	cmp "$TEAM_ROOT/bob.prepared" "$prepared"
	team_publish_feedback bob
	[ "$(git rev-parse HEAD^)" = "$old_tip" ]
	[ "$(git rev-parse feature/comments)" = "$(git rev-parse origin/feature/comments)" ]
	team_review comments diff --document shared --entry 3 --porcelain
	printf '%s\n' "$output" | awk -F '\t' '$1=="comment-diff" {print $3 "\t" $4} $1=="comment-blob" {print}' >"$TEAM_ROOT/actual.recipe"
	cmp "$TEAM_ROOT/bob.recipe" "$TEAM_ROOT/actual.recipe"
	team_assert_private
}

@test "comments team active whole review remains pinned while the author rebases" { check_active_rebase whole; }
@test "comments team active step review remains pinned while the author rebases" { check_active_rebase step; }
@test "comments team active walk review remains pinned while the author rebases" { check_active_rebase walk; }
