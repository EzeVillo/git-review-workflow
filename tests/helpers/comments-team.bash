# Shared integration fixtures: commits cross a real bare remote; private Git
# directories never move between people. No timing or provider mocks.
# shellcheck disable=SC2034,SC2154 # Fixture globals and bats run results are consumed by callers.

team_ok() {
	run --separate-stderr "$@"
	if [ "$status" -ne 0 ]; then printf 'stdout:\n%s\nstderr:\n%s\n' "$output" "$stderr" >&2; return 1; fi
}

team_review() { team_ok git review "$@"; }

team_seed_remote() {
	TEAM_ROOT=$COMMENTS_TMP/team
	TEAM_REMOTE=$TEAM_ROOT/remote.git
	mkdir "$TEAM_ROOT"
	git switch --quiet feature/comments
	mkdir .review
	printf '# Walkthrough\n\n## 1. sample.txt\nRead the change.\n\n## 2. other file.txt\nRead the addition.\n' >.review/walkthrough.md
	git add .review/walkthrough.md
	git commit --quiet -m 'Author reading order'
	TEAM_CAPTURE=$(git rev-parse HEAD)
	git switch --quiet main
	team_review start --offline --no-walk feature/comments || return
	team_review comments add --document shared --path sample.txt --side head --start-line 2 --end-line 2 --text 'Initial team question' || return
	team_review comments add --document shared --text 'Unchanged team note' || return
	comments_refresh_paths || return
	TEAM_CONTEXT=$COMMENTS_CONTEXT
	team_review finish || return
	cp .review/comments.md "$TEAM_ROOT/seed.md"
	git commit --quiet -m 'Initial shared discussion'
	git switch --quiet feature/comments
	git merge --quiet --ff-only review-fixes/feature/comments
	TEAM_SEED=$(git rev-parse HEAD)
	git switch --quiet main
	git clone --quiet --bare --no-hardlinks "$COMMENTS_WORK" "$TEAM_REMOTE"
}

team_clone() {
	git clone --quiet --no-hardlinks "$TEAM_REMOTE" "$TEAM_ROOT/$1" || return
	git -C "$TEAM_ROOT/$1" config reviewworkflow.base main
	git -C "$TEAM_ROOT/$1" config user.name "$1"
	git -C "$TEAM_ROOT/$1" config user.email "$1@example.invalid"
	git -C "$TEAM_ROOT/$1" branch feature/comments origin/feature/comments
}

team_cd() {
	cd "$TEAM_ROOT/$1" || return
	COMMENTS_WORK=$(git rev-parse --show-toplevel) || return
}

team_start() {
	case "${1:-whole}" in
		whole) team_review start --offline --no-walk feature/comments ;;
		step) team_review start --offline --step feature/comments ;;
		walk) team_review start --offline feature/comments ;;
	esac
}

team_add_feedback() {
	local actor=$1
	team_review comments add --document local --text "TEAM_PRIVATE_$actor" || return
	team_review comments add --document shared --path sample.txt --side head --start-line 2 --end-line 2 --text "$actor question" || return
	comments_refresh_paths || return
	[ "$COMMENTS_CONTEXT" = "$TEAM_CONTEXT" ] || return
	printf '%s correction\n' "$actor" >"$actor-fix.txt"
	sed -n '/^## 3\./,$p' "$COMMENTS_SHARED" >"$TEAM_ROOT/$actor.block"
	team_review comments diff --document shared --entry 3 --porcelain || return
	printf '%s\n' "$output" | awk -F '\t' '$1=="comment-diff" {print $3 "\t" $4} $1=="comment-blob" {print}' >"$TEAM_ROOT/$actor.recipe"
}

team_publish_feedback() {
	local actor=$1
	team_review finish || return
	[ "$(git rev-parse HEAD)" = "$TEAM_SEED" ] || return
	[ "$(git diff --cached --name-only)" = "$(printf '.review/comments.md\n%s-fix.txt' "$actor")" ] || return
	cp .review/comments.md "$TEAM_ROOT/$actor.md"
	git commit --quiet -m "$actor feedback" || return
	git push --quiet origin "HEAD:refs/heads/feedback-$actor"
}

# Explicit author resolution. Keep the original discussion and selected blocks
# byte-for-byte; do not implement a semantic merge in the fixture or product.
team_resolve() {
	cp "$TEAM_ROOT/seed.md" .review/comments.md
	local actor
	for actor do
		printf '\n' >>.review/comments.md
		cat "$TEAM_ROOT/$actor.block" >>.review/comments.md
	done
	git add .review/comments.md
}

team_assert_private() (
	cd "$TEAM_REMOTE" || exit
	run --separate-stderr git log --all --format= -p -G TEAM_PRIVATE_
	[ "$status" -eq 0 ]
	[ "$output" = '' ]
	[ "$stderr" = '' ]
)

team_assert_reader() {
	team_clone reader || return
	team_cd reader || return
	team_review start --no-walk feature/comments || return
	comments_refresh_paths || return
	[ "$COMMENTS_CONTEXT" = "$TEAM_CONTEXT" ] || return
	[ ! -e "$COMMENTS_LOCAL" ] || return
	team_review comments entries --document shared --porcelain || return
	local bodies expected actor ordinal=3
	bodies=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-body" && $3!="" {print $3}')
	expected=$(printf 'Initial team question\nUnchanged team note\n'; for actor do printf '%s question\n' "$actor"; done)
	[ "$bodies" = "$expected" ] || return
	for actor do
		[ "$(cat "$actor-fix.txt")" = "$actor correction" ] || return
		team_review comments diff --document shared --entry "$ordinal" --porcelain || return
		printf '%s\n' "$output" | awk -F '\t' '$1=="comment-diff" {print $3 "\t" $4} $1=="comment-blob" {print}' >"$TEAM_ROOT/actual.recipe"
		cmp "$TEAM_ROOT/$actor.recipe" "$TEAM_ROOT/actual.recipe" || return
		ordinal=$((ordinal + 1))
	done
	team_review comments renumber --document shared || return
	team_review comments entries --document shared --porcelain || return
	local numbers
	numbers=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-entry" {print $3}')
	[ "$numbers" = "$(seq 1 $((2 + $#)))" ] || return
	team_assert_private
}
