#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments portable Shared is readable in another clone before invoking the product and keeps its context" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Unshared private sentinel.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Plain Markdown with $(touch EXECUTED) and `touch EXECUTED` as text.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/shared"
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	git switch --quiet feature/comments
	git add .review/comments.md
	git commit --quiet -m 'author includes Shared document'
	git clone --quiet --no-hardlinks --branch feature/comments "$COMMENTS_WORK" "$COMMENTS_TMP/reader"
	cd "$COMMENTS_TMP/reader"
	# This reader phase uses only Git and ordinary file I/O, without invoking
	# the product, a Markdown runtime or any provider integration.
	git show HEAD:.review/comments.md >"$COMMENTS_TMP/plain-reader"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_TMP/plain-reader"
	run --separate-stderr git grep -F 'Unshared private sentinel.' HEAD --
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = '' ]
	[ ! -e EXECUTED ]
	git branch main origin/main
	git config reviewworkflow.base main
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ "$COMMENTS_CONTEXT" = "$context" ]
	[ ! -e "$COMMENTS_LOCAL" ]
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
	[ ! -e EXECUTED ]
}

@test "comments manual copying between documents preserves references without an entry transfer operation" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Keep this private.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --path sample.txt --side head --start-line 2 --end-line 2 --text 'Choose this observation for Shared.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Original Shared observation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	sed -n '/^## 2\./,$p' "$COMMENTS_LOCAL" >"$COMMENTS_TMP/chosen-block"
	printf '\n' >>"$COMMENTS_SHARED"
	cat "$COMMENTS_TMP/chosen-block" >>"$COMMENTS_SHARED"
	sed -n '/^## 1\./,/^## 2\./p' "$COMMENTS_SHARED" | sed '$d' >"$COMMENTS_TMP/shared-block"
	printf '\n' >>"$COMMENTS_LOCAL"
	cat "$COMMENTS_TMP/shared-block" >>"$COMMENTS_LOCAL"
	comments_refresh_paths
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-count" {print $3}')" = $'3\n2' ]
	run --separate-stderr git review comments diff --document shared --entry 2 --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-diff" {print $3 "\t" $4}')" = "$(printf '%s\t%s' "$(git rev-parse "$COMMENTS_BASE^{tree}")" "$(git rev-parse "$COMMENTS_TIP^{tree}")")" ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-location" {print}')" = $'comment-location\t2\thead\t2\t2' ]
	[ "$(grep -Fc 'Keep this private.' "$COMMENTS_SHARED" || true)" = 0 ]
}
