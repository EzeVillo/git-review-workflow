#!/usr/bin/env bats
# shellcheck disable=SC2154 # bats supplies stderr through run --separate-stderr.
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments sandbox builds real context choices compatible rename and stale reviewers" {
	local root="$COMMENTS_TMP/team-sandbox" room
	# Clone must apply the fixture config during checkout, before configure().
	git config --global core.autocrlf true
	run --separate-stderr sh "$BATS_TEST_DIRNAME/helpers/sandbox-comments.sh" "$root" "$BATS_TEST_DIRNAME/.."
	[ "$status" -eq 0 ]
	[ -f "$root/LEEME.md" ]
	for room in choice-new choice-continue; do
		cd "$root/$room"
		run --separate-stderr git review comments status --porcelain
		[ "$status" -eq 0 ]
		[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-identity" {print $2}')" = ambiguous ]
		[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-candidate" {n++} END {print n}')" = 1 ]
	done
	cd "$root/choice-new"
	run --separate-stderr git review comments add --document local --new-context --text 'Independent comment'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ "$(grep -Fc 'Shared: original team question' "$COMMENTS_SHARED")" = 1 ]
	[ "$(grep -Fc 'Local: private notes' "$COMMENTS_LOCAL" || true)" = 0 ]
	cd "$root/choice-continue"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	local context
	context=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-candidate" {print $2}')
	run --separate-stderr git review comments add --document local --use-context "$context" --text 'Continue comment'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ "$(grep -Fc 'Local: private notes' "$COMMENTS_LOCAL")" = 1 ]
	cd "$root/renamed"
	comments_refresh_paths
	[ "$(grep -Fc 'Local: private notes' "$COMMENTS_LOCAL")" = 1 ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-identity" {print $2}')" = resolved ]
	cd "$root/stale"
	[ "$(git config branch.review/feature/discussion.reviewtip)" != "$(git --git-dir="$root/origin.git" rev-parse feature/discussion)" ]
	[ "$(cat bob-fix.txt)" = 'Bob code correction' ]
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	git commit --quiet -m 'Bob feedback'
	git fetch --quiet origin
	run --separate-stderr git merge --no-edit origin/feature/discussion
	[ "$status" -eq 1 ]
	[[ "$output" == *'CONFLICT (content): Merge conflict in .review/comments.md'* ]]
	[ "$(git diff --name-only --diff-filter=U)" = .review/comments.md ]
	[ -f alice-fix.txt ]
	[ -f bob-fix.txt ]
}
