#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats assigns status/output per test.
# shellcheck disable=SC2154 # bats assigns stderr through run --separate-stderr.
load helpers/comments
load helpers/comments-team
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; team_seed_remote; }
teardown() { comments_teardown; }

check_three_reviewers() {
	local mode=$1 order=$2 actor merged=''
	for actor in author alice bob carol; do team_clone "$actor"; done
	for actor in alice bob carol; do
		team_cd "$actor"
		team_start "$mode"
		[ "$(git config branch.review/feature/comments.reviewtip)" = "$TEAM_SEED" ]
		team_add_feedback "$actor"
		team_publish_feedback "$actor"
	done
	team_cd author
	git switch --quiet feature/comments
	git fetch --quiet origin
	for actor in $order; do
		if [ -z "$merged" ]; then
			git merge --quiet --ff-only "origin/feedback-$actor"
		else
			run --separate-stderr git merge --no-edit "origin/feedback-$actor"
			[ "$status" -eq 1 ]
			[[ "$output" == *'CONFLICT (content): Merge conflict in .review/comments.md'* ]]
			[ "$(git diff --name-only --diff-filter=U)" = .review/comments.md ]
		fi
		merged="$merged $actor"
		if git rev-parse --verify --quiet MERGE_HEAD >/dev/null; then
			# shellcheck disable=SC2086 # the fixture owns this closed actor list.
			team_resolve $merged
			git commit --quiet -m 'Author resolves shared feedback'
		fi
	done
	git push --quiet origin feature/comments
	# shellcheck disable=SC2086 # assert the resolved order, not visible numbers.
	team_assert_reader $order
}

@test "comments team three stale reviewers preserve existing discussion in ABC order" { check_three_reviewers whole 'alice bob carol'; }
@test "comments team three stale reviewers preserve existing discussion in CBA order" { check_three_reviewers whole 'carol bob alice'; }
@test "comments team three stale reviewers preserve existing discussion in BAC order" { check_three_reviewers whole 'bob alice carol'; }
@test "comments team three step reviewers retain repeated numbers and original recipes" { check_three_reviewers step 'alice bob carol'; }
@test "comments team three walk reviewers retain repeated numbers and original recipes" { check_three_reviewers walk 'carol bob alice'; }

@test "comments team rejected stale push preserves feedback for explicit merge and retry" {
	local actor
	for actor in alice bob; do team_clone "$actor"; done
	team_cd alice
	team_start
	team_add_feedback alice
	team_publish_feedback alice
	git push --quiet origin HEAD:refs/heads/feature/comments
	team_cd bob
	[ "$(git rev-parse feature/comments)" = "$TEAM_SEED" ]
	[ "$(git --git-dir="$TEAM_REMOTE" rev-parse feature/comments)" != "$TEAM_SEED" ]
	team_start
	team_add_feedback bob
	team_publish_feedback bob
	comments_refresh_paths
	local local_path=$COMMENTS_LOCAL
	cp "$local_path" "$TEAM_ROOT/bob.local"
	git ls-files --stage >"$TEAM_ROOT/before-index"
	local own_tip
	own_tip=$(git rev-parse HEAD)
	run --separate-stderr git push origin HEAD:refs/heads/feature/comments
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'[rejected]'* ]]
	[ "$(git rev-parse HEAD)" = "$own_tip" ]
	git ls-files --stage >"$TEAM_ROOT/after-index"
	cmp "$TEAM_ROOT/before-index" "$TEAM_ROOT/after-index"
	cmp "$TEAM_ROOT/bob.local" "$local_path"
	git fetch --quiet origin
	run --separate-stderr git merge --no-edit origin/feature/comments
	[ "$status" -eq 1 ]
	[[ "$output" == *'CONFLICT (content): Merge conflict in .review/comments.md'* ]]
	team_resolve alice bob
	git commit --quiet -m 'Resolve feedback after rejected push'
	git push --quiet origin HEAD:refs/heads/feature/comments
	team_assert_reader alice bob
}

check_saved_remote_advance() {
	local mode=$1 actor prepared local_path guard
	for actor in alice bob; do team_clone "$actor"; done
	team_cd bob
	team_start "$mode"
	team_add_feedback bob
	comments_refresh_paths
	prepared=$COMMENTS_SHARED local_path=$COMMENTS_LOCAL guard=$COMMENTS_GUARD
	cp "$prepared" "$TEAM_ROOT/bob.prepared"
	cp "$local_path" "$TEAM_ROOT/bob.local"
	team_review save
	team_cd alice
	team_start
	team_add_feedback alice
	team_publish_feedback alice
	git push --quiet origin HEAD:refs/heads/feature/comments
	team_cd bob
	git fetch --quiet origin
	git branch --force feature/comments origin/feature/comments
	team_review continue feature/comments
	comments_refresh_paths
	[ "$COMMENTS_SHARED" = "$prepared" ]
	[ "$COMMENTS_GUARD" = "$guard" ]
	[ "$(git config branch.review/feature/comments.reviewtip)" = "$TEAM_SEED" ]
	cmp "$TEAM_ROOT/bob.prepared" "$prepared"
	cmp "$TEAM_ROOT/bob.local" "$local_path"
	comments_snapshot "$TEAM_ROOT/before-refusal"
	run --separate-stderr git review finish --onto-source
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'local feature/comments is not at the reviewed tip'* ]]
	[ "$(git rev-parse feature/comments)" = "$(git rev-parse origin/feature/comments)" ]
	[ "$(git config branch.review/feature/comments.reviewundohead)" != '' ]
	team_review finish --abort
	comments_snapshot "$TEAM_ROOT/after-refusal"
	comments_assert_snapshot "$TEAM_ROOT/before-refusal" "$TEAM_ROOT/after-refusal" branch head index staged unstaged worktree
	comments_refresh_paths
	[ "$COMMENTS_GUARD" = "$guard" ]
	cmp "$TEAM_ROOT/bob.prepared" "$COMMENTS_SHARED"
	cmp "$TEAM_ROOT/bob.local" "$COMMENTS_LOCAL"
	team_publish_feedback bob
	team_cd alice
	git switch --quiet feature/comments
	git merge --quiet --ff-only review-fixes/feature/comments
	git fetch --quiet origin
	run --separate-stderr git merge --no-edit origin/feedback-bob
	[ "$status" -eq 1 ]
	[[ "$output" == *'CONFLICT (content): Merge conflict in .review/comments.md'* ]]
	team_resolve alice bob
	git commit --quiet -m 'Resolve saved stale review'
	git push --quiet origin feature/comments
	team_assert_reader alice bob
}

@test "comments team saved whole review keeps its baseline while another reviewer publishes" { check_saved_remote_advance whole; }
@test "comments team saved step review keeps its baseline while another reviewer publishes" { check_saved_remote_advance step; }
@test "comments team saved walk review keeps its baseline while another reviewer publishes" { check_saved_remote_advance walk; }

check_delete_reply() {
	local resolution=$1 actor
	for actor in author alice bob; do team_clone "$actor"; done
	team_cd alice
	team_start
	team_review comments delete --document shared --entry 1
	team_review finish
	git commit --quiet -m 'Alice deletes initial question'
	git push --quiet origin HEAD:refs/heads/feedback-alice
	team_cd bob
	team_start
	comments_refresh_paths
	sed 's/Initial team question/Bob answers the initial question/' "$COMMENTS_SHARED" >"$TEAM_ROOT/reply.md"
	cp "$TEAM_ROOT/reply.md" "$COMMENTS_SHARED"
	team_review finish
	git commit --quiet -m 'Bob replies to stale initial question'
	git push --quiet origin HEAD:refs/heads/feedback-bob
	team_cd author
	git switch --quiet feature/comments
	git fetch --quiet origin
	git merge --quiet --ff-only origin/feedback-alice
	run --separate-stderr git merge --no-edit origin/feedback-bob
	[ "$status" -eq 1 ]
	[[ "$output" == *'CONFLICT (content): Merge conflict in .review/comments.md'* ]]
	git show origin/feedback-alice:.review/comments.md >"$TEAM_ROOT/deleted.md"
	git show origin/feedback-bob:.review/comments.md >"$TEAM_ROOT/answered.md"
	if [ "$resolution" = delete ]; then cp "$TEAM_ROOT/deleted.md" .review/comments.md
	else cp "$TEAM_ROOT/answered.md" .review/comments.md
	fi
	git add .review/comments.md
	git commit --quiet -m 'Author explicitly resolves deletion versus reply'
	git push --quiet origin feature/comments
	team_clone reader
	team_cd reader
	team_start
	team_review comments entries --document shared --porcelain
	local expected='Unchanged team note'
	if [ "$resolution" = reply ]; then expected=$(printf 'Bob answers the initial question\nUnchanged team note'); fi
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-body" && $3!="" {print $3}')" = "$expected" ]
	team_review finish
	[ "$(git status --porcelain)" = '' ]
	[ "$(grep -Fc 'Initial team question' .review/comments.md || true)" = 0 ]
	team_assert_private
}

@test "comments team explicit deletion resolution does not revive a stale reply" { check_delete_reply delete; }
@test "comments team explicit reply resolution survives a competing deletion" { check_delete_reply reply; }

@test "comments team unresolved shared merge is unreadable until the author resolves it" {
	local actor
	for actor in author alice bob; do team_clone "$actor"; done
	for actor in alice bob; do
		team_cd "$actor"
		team_start
		team_add_feedback "$actor"
		team_publish_feedback "$actor"
	done
	team_cd author
	git switch --quiet feature/comments
	git fetch --quiet origin
	git merge --quiet --ff-only origin/feedback-alice
	run --separate-stderr git merge --no-edit origin/feedback-bob
	[ "$status" -eq 1 ]
	[ "$(git diff --name-only --diff-filter=U)" = .review/comments.md ]
	comments_snapshot "$TEAM_ROOT/before-conflict-read"
	team_review comments status --porcelain
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-document" && $4=="shared" {print $5 "\t" $6}')" = "$(printf 'present\tunreadable')" ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-count" {print}')" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-diagnostic" {print $3}')" = read ]
	run --separate-stderr git review comments entries --document shared --porcelain
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: repository Shared has unresolved merge conflicts' ]
	run --separate-stderr git review comments diff --document shared --entry 1 --porcelain
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: repository Shared has unresolved merge conflicts' ]
	comments_snapshot "$TEAM_ROOT/after-conflict-read"
	comments_assert_snapshot "$TEAM_ROOT/before-conflict-read" "$TEAM_ROOT/after-conflict-read"
	team_resolve alice bob
	git commit --quiet -m 'Resolve unreadable shared merge'
	git push --quiet origin feature/comments
	team_assert_reader alice bob
}
