#!/usr/bin/env bats
# shellcheck disable=SC2154 # bats supplies stderr through run --separate-stderr.
load helpers/comments
load helpers/comments-team
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; team_seed_remote; }
teardown() { comments_teardown; }

known_discussion() {
	team_clone alice
	team_cd alice
	team_start
	team_review comments add --document local --text 'Original PR private sentinel'
	team_review finish
	team_review clean --keep-fixes feature/comments
	comments_refresh_paths
	OLD_LOCAL=$COMMENTS_LOCAL
	cp "$OLD_LOCAL" "$TEAM_ROOT/old.local"
	git switch --quiet main
}

copied_branch() {
	git switch --quiet -c feature/copied main
	mkdir .review
	cp "$TEAM_ROOT/seed.md" .review/comments.md
	printf 'A different PR\n' >different.txt
	git add .
	git commit --quiet -m 'Unrelated PR copies the portable document'
	git switch --quiet main
}

@test "comments copied known context with incompatible history requires a choice" {
	known_discussion
	copied_branch
	team_review start --offline --no-walk feature/copied
	comments_snapshot "$TEAM_ROOT/before-choice"
	team_review comments status --porcelain
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-identity" {print $2}')" = ambiguous ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-candidate" {print $2}')" = "$TEAM_CONTEXT" ]
	run --separate-stderr git review comments add --document local --text 'Do not mix implicitly'
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: choose --new-context or --use-context before writing comments' ]
	comments_snapshot "$TEAM_ROOT/after-choice"
	comments_assert_snapshot "$TEAM_ROOT/before-choice" "$TEAM_ROOT/after-choice"
	cmp "$TEAM_ROOT/old.local" "$OLD_LOCAL"
}

@test "comments explicit new context preserves incoming Shared and separates old Local through undo" {
	known_discussion
	copied_branch
	team_review start --offline --no-walk feature/copied
	team_review comments add --document local --new-context --text 'Independent PR observation'
	comments_refresh_paths
	local new_context=$COMMENTS_CONTEXT prepared=$COMMENTS_SHARED
	[ "$new_context" != "$TEAM_CONTEXT" ]
	[ "$(grep -Fc 'Original PR private sentinel' "$COMMENTS_LOCAL" || true)" = 0 ]
	team_review comments entries --document shared --porcelain
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-body" && $3!="" {print $3}')" = "$(printf 'Initial team question\nUnchanged team note')" ]
	# All bytes except the portable identity remain unchanged.
	sed "s/$TEAM_CONTEXT/$new_context/" "$TEAM_ROOT/seed.md" >"$TEAM_ROOT/rebound.md"
	cmp "$TEAM_ROOT/rebound.md" "$prepared"
	team_review finish
	git show :.review/comments.md >"$TEAM_ROOT/delivered.md"
	cmp "$TEAM_ROOT/rebound.md" "$TEAM_ROOT/delivered.md"
	team_review finish --abort
	cmp "$TEAM_ROOT/rebound.md" "$prepared"
	team_review abort
	cmp "$TEAM_ROOT/old.local" "$OLD_LOCAL"
	MSYS_NO_PATHCONV=1 git show feature/copied:.review/comments.md >"$TEAM_ROOT/source.md"
	cmp "$TEAM_ROOT/seed.md" "$TEAM_ROOT/source.md"
}

@test "comments explicit continuation of copied context restores Local but uses incoming Shared" {
	known_discussion
	copied_branch
	git switch --quiet feature/copied
	sed 's/Initial team question/Author answer in copied PR/' .review/comments.md >"$TEAM_ROOT/incoming.md"
	cp "$TEAM_ROOT/incoming.md" .review/comments.md
	git commit --quiet -am 'Incoming discussion differs from retained result'
	git switch --quiet main
	team_review start --offline --no-walk feature/copied
	team_review comments add --document local --use-context "$TEAM_CONTEXT" --text 'Explicitly continue'
	comments_refresh_paths
	[ "$COMMENTS_CONTEXT" = "$TEAM_CONTEXT" ]
	[ "$(grep -Fc 'Original PR private sentinel' "$COMMENTS_LOCAL")" = 1 ]
	cmp "$TEAM_ROOT/incoming.md" "$COMMENTS_SHARED"
	team_review abort
	cmp "$TEAM_ROOT/old.local" "$OLD_LOCAL"
}

@test "comments renamed branch with compatible history continues without a choice" {
	known_discussion
	git branch feature/renamed feature/comments
	team_review start --offline --no-walk feature/renamed
	comments_refresh_paths
	[ "$COMMENTS_CONTEXT" = "$TEAM_CONTEXT" ]
	cmp "$TEAM_ROOT/old.local" "$COMMENTS_LOCAL"
	team_review comments add --document local --text 'Compatible renamed branch'
	[ "$(grep -Fc 'Original PR private sentinel' "$COMMENTS_LOCAL")" = 1 ]
}

@test "comments fresh clone accepts copied Shared without private provenance or Local adoption" {
	team_clone author
	team_cd author
	copied_branch
	git push --quiet origin feature/copied
	team_clone reader
	team_cd reader
	team_review start --no-walk feature/copied
	comments_refresh_paths
	[ "$COMMENTS_CONTEXT" = "$TEAM_CONTEXT" ]
	[ ! -e "$COMMENTS_LOCAL" ]
	cmp "$TEAM_ROOT/seed.md" "$COMMENTS_SHARED"
}

write_context_bytes() {
	# shellcheck disable=SC2016 # Markdown code fences are literal fixture bytes.
	printf '\357\273\277# Comments\r\n\r\n<!-- git-review-comments v1\r\ncontext %s\r\n-->\r\n\r\n## 7. Keep prose\r\n\r\nLiteral context %s\r\n```md\r\n<!-- git-review-comments v1\r\ncontext %s\r\n-->\r\n```\r\nNo final newline' "$1" "$TEAM_CONTEXT" "$TEAM_CONTEXT"
}

@test "comments new context rebinds only the real preamble preserving BOM CRLF examples and EOF" {
	known_discussion
	copied_branch
	git switch --quiet feature/copied
	write_context_bytes "$TEAM_CONTEXT" >.review/comments.md
	git commit --quiet -am 'Copied document with byte-sensitive prose'
	git switch --quiet main
	team_review start --offline --no-walk feature/copied
	team_review comments init --document local --new-context
	comments_refresh_paths
	[ "$COMMENTS_CONTEXT" != "$TEAM_CONTEXT" ]
	write_context_bytes "$COMMENTS_CONTEXT" >"$TEAM_ROOT/expected.md"
	cmp "$TEAM_ROOT/expected.md" "$COMMENTS_SHARED"
	cmp "$TEAM_ROOT/old.local" "$OLD_LOCAL"
}
