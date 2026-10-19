#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments capture Local Shared Local stays independent in whole walk and step" {
	local mode
	for mode in whole walk step; do
		COMMENTS_WORK="$COMMENTS_TMP/$mode"
		git clone --quiet --no-hardlinks "$COMMENTS_TMP/work" "$COMMENTS_WORK"
		cd "$COMMENTS_WORK"
		git branch feature/comments origin/feature/comments
		git config reviewworkflow.base main
		run --separate-stderr comments_start "$mode"
		[ "$status" -eq 0 ]
		comments_snapshot "$COMMENTS_TMP/before-$mode"
		run --separate-stderr git review comments add --document local --text 'Private first.'
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		comments_refresh_paths
		[ ! -e "$COMMENTS_SHARED" ]
		cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/first-$mode"
		run --separate-stderr git review comments add --document shared --text 'Shared second.'
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		cmp "$COMMENTS_LOCAL" "$COMMENTS_TMP/first-$mode"
		cp "$COMMENTS_SHARED" "$COMMENTS_TMP/shared-$mode"
		run --separate-stderr git review comments add --document local --text 'Private third.'
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		cmp "$COMMENTS_SHARED" "$COMMENTS_TMP/shared-$mode"
		comments_refresh_paths
		[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-count" {print $3}')" = "$(printf '2\n1')" ]
		[ "$(awk '/^Private / {print}' "$COMMENTS_LOCAL")" = "$(printf 'Private first.\nPrivate third.')" ]
		[ "$(awk '/^Shared / {print}' "$COMMENTS_SHARED")" = 'Shared second.' ]
		comments_snapshot "$COMMENTS_TMP/after-$mode"
		comments_assert_snapshot "$COMMENTS_TMP/before-$mode" "$COMMENTS_TMP/after-$mode" head branch refs index raw-index.bytes staged unstaged worktree objects
	done
}

@test "comments captured general entry has exact marker refs heading and body" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Why retry?'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	printf '# Comments\n\n<!-- git-review-comments v1\ncontext %s\n-->\n\n## 1. General\n\n<!-- git-review-comment v1\nbase %s\nhead %s\n-->\n\nWhy retry?\n' "$COMMENTS_CONTEXT" "$COMMENTS_BASE" "$COMMENTS_TIP" >"$COMMENTS_TMP/expected"
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_LOCAL"
}

@test "comments capture counts physical blocks and preserves manually edited original bytes" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments init --document local
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cp "$BATS_TEST_DIRNAME/fixtures/comments/no-final-lf.md" "$COMMENTS_LOCAL"
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/original"
	run --separate-stderr git review comments add --document local --text 'Another question.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	local size
	size=$(wc -c <"$COMMENTS_TMP/original")
	dd if="$COMMENTS_LOCAL" of="$COMMENTS_TMP/prefix" bs=1 count="$size" 2>/dev/null
	cmp "$COMMENTS_TMP/original" "$COMMENTS_TMP/prefix"
	[ "$(awk '/^## / {print}' "$COMMENTS_LOCAL")" = "$(printf '## 7. File\n## 2. General')" ]
}

check_repeated_location() {
	run --separate-stderr comments_start "$1"
	[ "$status" -eq 0 ]
	local head
	head=$(git config branch.review/feature/comments.reviewtip)
	if [ "$1" = step ]; then head=$(git rev-parse feature/comments~1); fi
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments add --document local --path sample.txt --side head --start-line 2 --end-line 2 --text 'First repeated location.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --path sample.txt --side head --start-line 2 --end-line 2 --text 'Second repeated location.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Separate shared general comment.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-count" {print $3}')" = $'2\n1' ]
	[ "$(awk '/^First repeated|^Second repeated/ {print}' "$COMMENTS_LOCAL")" = $'First repeated location.\nSecond repeated location.' ]
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/shared"
	# A manual deletion leaves display number 2 intact and edits its body. The
	# writer does not reconstruct, deduplicate or renumber the remaining prose.
	printf '# Comments\n\n<!-- git-review-comments v1\ncontext %s\n-->\n\n## 2. sample.txt\n\n<!-- git-review-comment v1\nbase %s\nhead %s\nbase-path sample.txt\nhead-path sample.txt\nside head\nstart 2\nend 2\n-->\n\nSecond repeated location (edited).\n' "$COMMENTS_CONTEXT" "$COMMENTS_BASE" "$head" >"$COMMENTS_TMP/edited"
	cp "$COMMENTS_TMP/edited" "$COMMENTS_LOCAL"
	comments_refresh_paths
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-count" {print $3}')" = $'1\n1' ]
	cmp "$COMMENTS_TMP/edited" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" branch head refs index raw-index.bytes staged unstaged worktree objects
}

@test "comments whole keeps repeated locations and rereads manual editing and deletion" { check_repeated_location whole; }
@test "comments walk keeps repeated locations and rereads manual editing and deletion" { check_repeated_location walk; }
@test "comments step keeps repeated locations and rereads manual editing and deletion" { check_repeated_location step; }
