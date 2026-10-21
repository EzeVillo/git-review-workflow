#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

# These are independent repositories: only commits pushed to the local bare
# remote cross the boundary. In particular, no reviewer gitdir is copied.
team_clone() {
	git clone --quiet "$COMMENTS_TMP/remote.git" "$COMMENTS_TMP/$1"
	cd "$COMMENTS_TMP/$1"
	git config user.name "$1"
	git config user.email "$1@example.invalid"
	git config reviewworkflow.base main
}

team_review_ok() {
	run --separate-stderr git review "$@"
	if [ "$status" -ne 0 ]; then printf '%s\n' "$output" "$stderr" >&2; fi
	[ "$status" -eq 0 ]
}

team_start() {
	case "$1" in
		whole) team_review_ok start --no-walk feature/comments ;;
		step) team_review_ok start --step feature/comments ;;
		walk) team_review_ok start feature/comments ;;
	esac
}

team_new_branch() {
	local branch=$1
	git switch --quiet -c "$branch" main
	printf '%s\n' "$branch" >"$branch.txt"
	git add "$branch.txt"
	git commit --quiet -m "$branch"
	git push --quiet origin "$branch"
	git switch --quiet main
}

team_flow() {
	local mode=$1 strategy=$2 alice_context shared_before historical expected_historical
	git switch --quiet feature/comments
	mkdir -p .review
	printf '# Walkthrough\n\n## 1. sample.txt\n\nRead the change.\n\n## 2. other file.txt\n\nRead the addition.\n' >.review/walkthrough.md
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough
	git switch --quiet main
	git clone --quiet --bare "$COMMENTS_WORK" "$COMMENTS_TMP/remote.git"
	team_clone author
	team_new_branch before-merge
	team_clone alice
	team_start "$mode"
	team_review_ok comments add --document local --text 'Alice private sentinel'
	team_review_ok comments add --document shared --path sample.txt --side head --start-line 2 --end-line 2 --text 'Alice asks'
	comments_refresh_paths
	alice_context=$COMMENTS_CONTEXT
	shared_before=$COMMENTS_SHARED
	team_review_ok comments diff --document shared --entry 1 --porcelain
	expected_historical=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-diff" {print $4}')
	[ -n "$expected_historical" ]
	[ "$(git diff --name-only)" = '' ]
	team_review_ok save
	[ "$(git branch --show-current)" = main ]
	team_review_ok continue feature/comments
	comments_refresh_paths
	[ "$COMMENTS_CONTEXT" = "$alice_context" ]
	[ "$COMMENTS_SHARED" = "$shared_before" ]
	if [ "$mode" = step ]; then team_review_ok next; fi
	printf 'Alice correction\n' >>sample.txt
	team_review_ok finish
	[ "$(git branch --show-current)" = review-fixes/feature/comments ]
	[ "$(git diff --cached --name-only)" = $'.review/comments.md\nsample.txt' ]
	[ "$(git ls-files -- .review/comments.md)" = .review/comments.md ]
	[ -f .review/comments.md ]
	git add sample.txt .review/comments.md
	git commit --quiet -m 'Alice correction and shared question'
	git push --quiet origin HEAD:refs/heads/alice-feedback
	cd "$COMMENTS_TMP/author"
	git fetch --quiet origin
	git switch --quiet -c feature/comments origin/feature/comments
	git merge --quiet --ff-only origin/alice-feedback
	sed 's/Alice asks/Author answers/' .review/comments.md >"$COMMENTS_TMP/reply.md"
	cp "$COMMENTS_TMP/reply.md" .review/comments.md
	git add .review/comments.md
	git commit --quiet -m 'Author answers in a separate commit'
	git push --quiet origin feature/comments
	team_clone bob
	team_start "$mode"
	team_review_ok comments init --document shared
	comments_refresh_paths
	[ "$COMMENTS_CONTEXT" = "$alice_context" ]
	[ ! -e "$COMMENTS_LOCAL" ]
	[ "$(grep -Fc 'Author answers' "$COMMENTS_SHARED")" = 1 ]
	team_review_ok comments diff --document shared --entry 1 --porcelain
	historical=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-diff" {print $4}')
	[ "$historical" = "$expected_historical" ]
	team_review_ok comments add --document shared --text 'Bob follow-up'
	team_review_ok finish
	git add .review/comments.md
	git commit --quiet -m 'Bob follow-up'
	git push --quiet origin HEAD:refs/heads/bob-feedback
	cd "$COMMENTS_TMP/author"
	git fetch --quiet origin
	git merge --quiet --ff-only origin/bob-feedback
	git push --quiet origin feature/comments
	git switch --quiet main
	case "$strategy" in
		ff) git merge --quiet --ff-only feature/comments ;;
		merge) git merge --quiet --no-ff feature/comments -m 'Merge reviewed change' ;;
		squash) git merge --quiet --squash feature/comments; git commit --quiet -m 'Squash reviewed change' ;;
	esac
	git push --quiet origin main
	team_new_branch after-merge
	team_clone carol
	local branch
	for branch in before-merge after-merge; do
		team_review_ok start --no-walk "$branch"
		team_review_ok comments status --porcelain
		[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-identity" {print $2}')" = fresh ]
		team_review_ok comments add --document shared --text "Carol on $branch"
		comments_refresh_paths
		[ "$COMMENTS_CONTEXT" != "$alice_context" ]
		[ "$(grep -Fc 'Alice asks' "$COMMENTS_SHARED" || true)" = 0 ]
		[ "$(grep -Fc 'Author answers' "$COMMENTS_SHARED" || true)" = 0 ]
		[ "$(grep -Fc 'Bob follow-up' "$COMMENTS_SHARED" || true)" = 0 ]
		[ "$(grep -Fc "Carol on $branch" "$COMMENTS_SHARED")" = 1 ]
		team_review_ok abort
	done
	# Local prose never entered a commit in any actor's clone or the bare remote.
	cd "$COMMENTS_TMP/remote.git"
	run --separate-stderr git log --all --format= -p -G 'Alice private sentinel'
	[ "$status" -eq 0 ]
	[ "$output" = '' ]
	[ "$stderr" = '' ]
}

@test "comments team whole flow survives fast forward and branches before and after merge" { team_flow whole ff; }
@test "comments team whole flow survives merge commit and branches before and after merge" { team_flow whole merge; }
@test "comments team whole flow survives squash and branches before and after merge" { team_flow whole squash; }
@test "comments team step flow survives fast forward and branches before and after merge" { team_flow step ff; }
@test "comments team step flow survives merge commit and branches before and after merge" { team_flow step merge; }
@test "comments team step flow survives squash and branches before and after merge" { team_flow step squash; }
@test "comments team walk flow survives fast forward and branches before and after merge" { team_flow walk ff; }
@test "comments team walk flow survives merge commit and branches before and after merge" { team_flow walk merge; }
@test "comments team walk flow survives squash and branches before and after merge" { team_flow walk squash; }

@test "comments author reply is the prepared Shared without reviving the old question" {
	local root="$COMMENTS_TMP/round-trip" script="$BATS_TEST_DIRNAME/helpers/comments-team-history.sh"
	mkdir "$root"
	run --separate-stderr sh "$script" init "$root"
	[ "$status" -eq 0 ]
	cd "$root/reviewer"
	team_review_ok start --no-walk feature/team
	team_review_ok comments add --document shared --text 'Reviewer question'
	team_review_ok finish
	run --separate-stderr sh "$script" publish "$root"
	[ "$status" -eq 0 ]
	team_review_ok clean feature/team
	team_review_ok start --no-walk feature/team
	team_review_ok comments init --document shared
	comments_refresh_paths
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-diagnostic" {print $3}')" = '' ]
	[ "$(grep -Fc 'Author response' "$COMMENTS_SHARED")" = 1 ]
	[ "$(grep -Fc 'Author response' .review/comments.md)" = 1 ]
	cp .review/comments.md "$COMMENTS_SHARED"
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/accepted-reply.md"
	team_review_ok finish
	comments_refresh_paths
	cmp "$COMMENTS_TMP/accepted-reply.md" "$COMMENTS_SHARED"
	cmp "$COMMENTS_TMP/accepted-reply.md" .review/comments.md
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-diagnostic" {print $3}')" = '' ]
}

@test "comments remote review does not inherit a merged context from a stale local base" {
	local root="$COMMENTS_TMP/stale-base" script="$BATS_TEST_DIRNAME/helpers/comments-team-history.sh" previous_context
	mkdir "$root"
	run --separate-stderr sh "$script" init "$root"
	[ "$status" -eq 0 ]
	cd "$root/reviewer"
	team_review_ok start --no-walk feature/team
	team_review_ok comments add --document shared --text 'Reviewer question'
	comments_refresh_paths
	previous_context=$COMMENTS_CONTEXT
	team_review_ok finish
	run --separate-stderr sh "$script" publish "$root"
	[ "$status" -eq 0 ]
	team_review_ok clean feature/team
	run --separate-stderr sh "$script" merge "$root" ff
	[ "$status" -eq 0 ]
	[ "$(git rev-parse main)" != "$(git rev-parse origin/main)" ]
	team_review_ok start --no-walk after-merge
	team_review_ok comments status --porcelain
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-identity" {print $2}')" = fresh ]
	team_review_ok comments add --document shared --text 'Independent question'
	comments_refresh_paths
	[ "$COMMENTS_CONTEXT" != "$previous_context" ]
	[ "$(grep -Fc 'Independent question' "$COMMENTS_SHARED")" = 1 ]
	[ "$(grep -Fc 'Author response' "$COMMENTS_SHARED" || true)" = 0 ]
	team_review_ok abort
}

@test "comments concurrent reviewers preserve both deliveries through a real Git merge conflict" {
	local actor first_context='' second_context=''
	git clone --quiet --bare "$COMMENTS_WORK" "$COMMENTS_TMP/remote.git"
	for actor in alice bob; do
		team_clone "$actor"
		team_review_ok start --no-walk feature/comments
		team_review_ok comments add --document local --text "$actor private sentinel"
		team_review_ok comments add --document shared --text "$actor public question"
		comments_refresh_paths
		if [ "$actor" = alice ]; then first_context=$COMMENTS_CONTEXT
		else second_context=$COMMENTS_CONTEXT
		fi
		team_review_ok finish
		cp .review/comments.md "$COMMENTS_TMP/$actor-delivery.md"
		git add .review/comments.md
		git commit --quiet -m "$actor feedback"
		git push --quiet origin "HEAD:refs/heads/$actor-feedback"
	done
	[ "$first_context" != "$second_context" ]
	team_clone author
	git switch --quiet -c feature/comments origin/feature/comments
	git merge --quiet --ff-only origin/alice-feedback
	run --separate-stderr git merge --no-edit origin/bob-feedback
	[ "$status" -eq 1 ]
	[[ "$output" == *'CONFLICT (add/add): Merge conflict in .review/comments.md'* ]]
	[ "$(git diff --name-only --diff-filter=U)" = .review/comments.md ]
	[ "$(grep -Fc 'alice public question' .review/comments.md)" = 1 ]
	[ "$(grep -Fc 'bob public question' .review/comments.md)" = 1 ]
	git show origin/alice-feedback:.review/comments.md >"$COMMENTS_TMP/alice-from-git.md"
	git show origin/bob-feedback:.review/comments.md >"$COMMENTS_TMP/bob-from-git.md"
	cmp "$COMMENTS_TMP/alice-delivery.md" "$COMMENTS_TMP/alice-from-git.md"
	cmp "$COMMENTS_TMP/bob-delivery.md" "$COMMENTS_TMP/bob-from-git.md"
	# Explicitly resolve the document identity and retain both immutable entry
	# blocks. Visible numbers can duplicate; their physical ordinals remain unique.
	cp "$COMMENTS_TMP/alice-delivery.md" .review/comments.md
	printf '\n' >>.review/comments.md
	sed -n '/^## 1\./,$p' "$COMMENTS_TMP/bob-delivery.md" >>.review/comments.md
	git add .review/comments.md
	git commit --quiet -m 'Resolve both reviewer deliveries'
	git push --quiet origin feature/comments
	team_clone carol
	team_review_ok start --no-walk feature/comments
	team_review_ok comments init --document shared
	comments_refresh_paths
	[ "$COMMENTS_CONTEXT" = "$first_context" ]
	[ ! -e "$COMMENTS_LOCAL" ]
	team_review_ok comments entries --document shared --porcelain
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-body" && $3!="" {print $3}')" = $'alice public question\nbob public question' ]
	team_review_ok comments renumber --document shared
	team_review_ok comments entries --document shared --porcelain
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-entry" {print $3}')" = $'1\n2' ]
	run --separate-stderr git log --all --format= -p -G 'private sentinel'
	[ "$status" -eq 0 ]
	[ "$output" = '' ]
	[ "$stderr" = '' ]
}

@test "comments rebased author replies require explicit context without losing either version" {
	local root="$COMMENTS_TMP/rebased" script="$BATS_TEST_DIRNAME/helpers/comments-team-history.sh" previous_context
	mkdir "$root"
	run --separate-stderr sh "$script" init "$root"
	[ "$status" -eq 0 ]
	cd "$root/reviewer"
	team_review_ok start --no-walk feature/team
	team_review_ok comments add --document shared --text 'Reviewer question'
	comments_refresh_paths
	previous_context=$COMMENTS_CONTEXT
	team_review_ok finish
	run --separate-stderr sh "$script" publish "$root"
	[ "$status" -eq 0 ]
	team_review_ok clean feature/team
	cd "$root/author"
	git switch --quiet main
	printf 'New base\n' >base-advance.txt
	git add base-advance.txt
	git commit --quiet -m 'Base advances before integration'
	git push --quiet origin main
	git switch --quiet feature/team
	git rebase --quiet main
	git push --quiet --force-with-lease origin feature/team
	cd "$root/reviewer"
	team_review_ok start --no-walk feature/team
	team_review_ok comments status --porcelain
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-identity" {print $2}')" = ambiguous ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-candidate" {print $2}')" = "$previous_context" ]
	comments_snapshot "$COMMENTS_TMP/before-rejected-capture"
	run --separate-stderr git review comments add --document shared --text 'Must not be appended'
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: choose --new-context or --use-context before writing comments' ]
	comments_snapshot "$COMMENTS_TMP/after-rejected-capture"
	comments_assert_snapshot "$COMMENTS_TMP/before-rejected-capture" "$COMMENTS_TMP/after-rejected-capture"
	team_review_ok comments add --document shared --use-context "$previous_context" --text 'Explicit continuation'
	comments_refresh_paths
	[ "$COMMENTS_CONTEXT" = "$previous_context" ]
	[ "$(grep -Fc 'Author response' "$COMMENTS_SHARED")" = 1 ]
	[ "$(grep -Fc 'Explicit continuation' "$COMMENTS_SHARED")" = 1 ]
	[ "$(grep -Fc 'Author response' .review/comments.md)" = 1 ]
}

@test "comments materialized session keeps its full base when the target advances" {
	team_review_ok start --offline --no-walk feature/comments
	team_review_ok comments add --document local --text 'Before base integration'
	comments_refresh_paths
	local guard=$COMMENTS_GUARD context=$COMMENTS_CONTEXT
	git update-ref refs/heads/main "$COMMENTS_TIP" "$COMMENTS_BASE"
	comments_refresh_paths
	[ "$COMMENTS_CONTEXT" = "$context" ]
	[ "$COMMENTS_GUARD" = "$guard" ]
	team_review_ok comments add --document local --expect-context "$guard" --text 'After base integration'
	team_review_ok comments entries --document local --porcelain
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-body" && $3!="" {print $3}')" = $'Before base integration\nAfter base integration' ]
	[ "$(git rev-parse main)" = "$COMMENTS_TIP" ]
	[ "$(git branch --show-current)" = review/feature/comments ]
}
