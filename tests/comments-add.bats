#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments add porcelain returns both review guards and the current Comments report" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	local before after reply body text guard
	for text in 'First Local note.' 'Second Local note.'; do
		before=$(git review status --porcelain | awk -F '\t' '$1=="guard" {print $2}')
		[ -n "$before" ]
		guard=$(git review comments status --porcelain | awk -F '\t' '$1=="comments-guard" {print $2}')
		[ -n "$guard" ]
		printf '%s\n' "$text" >"$COMMENTS_TMP/add-input"
		run --separate-stderr git review comments add --document local --stdin --expect-context "$guard" --porcelain <"$COMMENTS_TMP/add-input"
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		reply=$output
		after=$(git review status --porcelain | awk -F '\t' '$1=="guard" {print $2}')
		[ -n "$after" ]
		[ "${reply%%$'\n'*}" = "$(printf 'comments-add-result\t1\t%s\t%s' "$before" "$after")" ]
		[ "${reply##*$'\n'}" = $'comments-add-result-end\t1' ]
		if [ "$text" = 'First Local note.' ]; then [ "$before" != "$after" ]; else [ "$before" = "$after" ]; fi
		body=$(printf '%s\n' "$reply" | sed '1d;$d')
		run --separate-stderr git review comments status --porcelain
		[ "$status" -eq 0 ]
		[ "$output" = "$body" ]
		[[ "$body" == *$'comments-add-reply\t1'* ]]
		comments_refresh_paths
		[ "$(tail -n 1 "$COMMENTS_LOCAL")" = "$text" ]
	done
}

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

@test "comments capture follows highest number and preserves manually edited original bytes" {
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
	[ "$(awk '/^## / {print}' "$COMMENTS_LOCAL")" = "$(printf '## 7. File\n## 8. General')" ]
}

@test "comments add after deleting first entry follows highest number in each document" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	local document
	for document in local shared; do
		run --separate-stderr git review comments add --document "$document" --text 'First'
		[ "$status" -eq 0 ]
		run --separate-stderr git review comments add --document "$document" --text 'Second'
		[ "$status" -eq 0 ]
		run --separate-stderr git review comments delete --document "$document" --entry 1
		[ "$status" -eq 0 ]
		run --separate-stderr git review comments add --document "$document" --text 'Third'
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		run --separate-stderr git review comments entries --document "$document" --porcelain
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-entry" {print $3}')" = $'2\n3' ]
		[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-body" && $3!="" {print $3}')" = $'Second\nThird' ]
	done
}

@test "comments add uses maximum real heading across gaps duplicates and unordered numbers" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments init --document local
	[ "$status" -eq 0 ]
	comments_refresh_paths
	printf '\357\273\277## 00042. Highest first\r\nKeep\r\n## 9. Lower\n~~~md\n## 999. Fenced\n~~~\n<!-- hidden\n## 9999. Hidden\n-->\n> ## 99999. Quoted\n    ## 999999. Indented\n## 42. Duplicate last\nKeep last' >"$COMMENTS_LOCAL"
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/original"
	run --separate-stderr git review comments add --document local --text 'Next'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	local size
	size=$(wc -c <"$COMMENTS_TMP/original")
	dd if="$COMMENTS_LOCAL" of="$COMMENTS_TMP/prefix" bs=1 count="$size" 2>/dev/null
	cmp "$COMMENTS_TMP/original" "$COMMENTS_TMP/prefix"
	run --separate-stderr git review comments entries --document local --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-entry" {print $3}')" = $'00042\n9\n42\n43' ]
}

@test "comments add increments decimal headings exactly without numeric overflow" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments init --document local
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local pair number expected
	for pair in 0000:1 0009:10 9007199254740992:9007199254740993 999999999999999999999999:1000000000000000000000000; do
		number=${pair%:*} expected=${pair#*:}
		printf '## %s. Existing\nKeep\n' "$number" >"$COMMENTS_LOCAL"
		run --separate-stderr git review comments add --document local --text 'Next'
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		[ "$(awk '/^## / {print}' "$COMMENTS_LOCAL")" = "$(printf '## %s. Existing\n## %s. General' "$number" "$expected")" ]
	done
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
