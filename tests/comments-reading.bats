#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments entries expose full prose and scope without leaking metadata or changing files" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	printf 'First paragraph with 100%% and\ta tab.\n\n```md\n## 9. Not an entry\n```\nLast paragraph.\n' >"$COMMENTS_TMP/body"
	run --separate-stderr git review comments add --document local --path sample.txt --side base --start-line 1 --end-line 1 --stdin <"$COMMENTS_TMP/body"
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments entries --document local --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-scope" {print $2 "\t" $3 "\t" $4}')" = $'1\tselection\tbase' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-body" && $3!="" {print $3}')" = $'First paragraph with 100%25 and%09a tab.\n```md\n## 9. Not an entry\n```\nLast paragraph.' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-entry" {n++} END {print n}')" -eq 1 ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments entries distinguish file sides and general comments with repeated visible numbers" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --path sample.txt --side head --text 'On the new file.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'About the whole review.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments entries --document local --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-scope" {print $2 "\t" $3 "\t" $4}')" = $'1\tfile\thead\n2\tgeneral\t' ]
}

@test "comments entries and diff reject prose changed during the snapshot read" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Original prose.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	export COMMENTS_RACE_PATH=$COMMENTS_LOCAL COMMENTS_REAL_GIT
	COMMENTS_REAL_GIT=$(command -v git)
	export COMMENTS_RACE_MARKER=$COMMENTS_TMP/raced
	mkdir "$COMMENTS_TMP/wrappers"
	cat >"$COMMENTS_TMP/wrappers/git" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = hash-object ] && [ "${2:-}" = --no-filters ] && [ "${3:-}" = -- ] && [ "${4:-}" = "$COMMENTS_RACE_PATH" ] && [ ! -e "$COMMENTS_RACE_MARKER" ]; then
	"$COMMENTS_REAL_GIT" "$@"
	printf '\nConcurrent prose.\n' >>"$COMMENTS_RACE_PATH"
	: >"$COMMENTS_RACE_MARKER"
	exit 0
fi
exec "$COMMENTS_REAL_GIT" "$@"
EOF
	chmod +x "$COMMENTS_TMP/wrappers/git"
	local operation before_index
	before_index=$(git ls-files --stage)
	for operation in entries diff; do
		cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/before-prose"
		rm -f "$COMMENTS_RACE_MARKER"
		if [ "$operation" = entries ]; then
			run --separate-stderr env PATH="$COMMENTS_TMP/wrappers:$PATH" "$BATS_TEST_DIRNAME/../bin/git-review" comments entries --document local --porcelain
		else
			run --separate-stderr env PATH="$COMMENTS_TMP/wrappers:$PATH" "$BATS_TEST_DIRNAME/../bin/git-review" comments diff --document local --entry 1 --porcelain
		fi
		[ "$status" -eq 4 ]
		[ "$output" = '' ]
		[ "$stderr" = 'error: comments document is stale' ]
		printf '\nConcurrent prose.\n' >>"$COMMENTS_TMP/before-prose"
		cmp "$COMMENTS_TMP/before-prose" "$COMMENTS_LOCAL"
		[ "$(git ls-files --stage)" = "$before_index" ]
	done
}

@test "comments deletion after finish removes only the retained document and rejects stale bytes" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Keep private.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Deliver this.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local retained=$COMMENTS_LOCAL guard revision
	guard=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-context" {print $5;exit}')
	revision=$(git hash-object --no-filters "$retained")
	cp .review/comments.md "$COMMENTS_TMP/delivered"
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/shared"
	printf '\nEditor change.\n' >>"$retained"
	run --separate-stderr git review comments delete --context "$context" --document local --expect-context "$guard" --expect-document "$revision"
	[ "$status" -eq 4 ]
	[ "$stderr" = 'error: comments document is stale' ]
	[ -f "$retained" ]
	revision=$(git hash-object --no-filters "$retained")
	run --separate-stderr git review comments delete --context "$context" --document local --expect-context "$guard" --expect-document "$revision"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$output" = 'Deleted local comments.' ]
	[ ! -e "$retained" ]
	cmp "$COMMENTS_TMP/delivered" .review/comments.md
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
}

@test "comments deleting retained Shared dismisses pending delivery without changing its destination" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Pending prose.'
	[ "$status" -eq 0 ]
	mkdir .review
	printf 'Concurrent destination.\n' >.review/comments.md
	run --separate-stderr git review finish
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'code was extracted but Shared comments could not be prepared'* ]]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT retained=$COMMENTS_SHARED
	cp .review/comments.md "$COMMENTS_TMP/destination"
	run --separate-stderr git review comments delete --context "$context" --document shared
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ ! -e "$retained" ]
	run --separate-stderr git review comments status --context "$context" --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery" {print $3}')" = discarded ]
	run --separate-stderr git review comments prepare --context "$context"
	[ "$status" -eq 2 ]
	[ "$stderr" = 'error: the prepared Shared document was deleted' ]
	cmp "$COMMENTS_TMP/destination" .review/comments.md
}
