#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
}
teardown() { comments_teardown; }

@test "comments captures a file range using actual base and head without writing code" {
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments add --document local --path sample.txt --side head --start-line 2 --end-line 3 --text 'Why?'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	[ "$(sed -n '/^<!-- git-review-comment v1$/,/^-->$/p' "$COMMENTS_LOCAL")" = "$(printf '<!-- git-review-comment v1\nbase %s\nhead %s\nbase-path sample.txt\nhead-path sample.txt\nside head\nstart 2\nend 3\n-->' "$COMMENTS_BASE" "$COMMENTS_TIP")" ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" branch head refs index raw-index.bytes staged unstaged worktree objects
}

@test "comments rejects incomplete refs lines and out of blob coordinates before materialization" {
	local scenario
	for scenario in base lines zero inverted outside side; do
		case "$scenario" in
			base) set -- --base "$COMMENTS_BASE" ;;
			lines) set -- --path sample.txt --side head --start-line 1 ;;
			zero) set -- --path sample.txt --side head --start-line 0 --end-line 1 ;;
			inverted) set -- --path sample.txt --side head --start-line 3 --end-line 2 ;;
			outside) set -- --path sample.txt --side head --start-line 1 --end-line 99 ;;
			side) set -- --side head --start-line 1 --end-line 1 ;;
		esac
		comments_snapshot "$COMMENTS_TMP/before"
		run --separate-stderr git review comments add --document local --text 'Why?' "$@"
		[ "$status" -eq 1 ]
		[ "$output" = '' ]
		[[ "$stderr" == 'error: '* ]]
		comments_snapshot "$COMMENTS_TMP/after"
		comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	done
}

@test "comments marks a dirty working file unversioned and never saves its contents" {
	printf 'dirty fourth line\n' >>sample.txt
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments add --document shared --path sample.txt --side head --start-line 4 --end-line 4 --text 'Dirty line.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	[ "$(sed -n '/^unversioned /p' "$COMMENTS_SHARED")" = 'unversioned 1' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" head refs index raw-index.bytes staged unstaged worktree objects
}

@test "comments explicit tree objects remain tree references and do not become HEAD" {
	local base_tree head_tree
	base_tree=$(git rev-parse "$COMMENTS_BASE^{tree}")
	head_tree=$(git rev-parse "$COMMENTS_TIP^{tree}")
	run --separate-stderr git review comments add --document local --base "$base_tree" --head "$head_tree" --text 'Tree range.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	[ "$(sed -n '/^base /p;/^head /p' "$COMMENTS_LOCAL")" = "$(printf 'base %s\nhead %s' "$base_tree" "$head_tree")" ]
}

@test "comments rejects huge line coordinates without shell integer overflow" {
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments add --document local --path sample.txt --side head --start-line 1 --end-line 99999999999999999999999999999999999999999999 --text 'Why?'
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comment line range exceeds the captured blob' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments rejects a selected side without a path even without line coordinates" {
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments add --document local --side head --text 'Why?'
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comment side requires a path on the selected side' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments missing requested file never silently becomes a general comment" {
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments add --document local --path absent.txt --text 'Why?'
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comment path is absent from the captured range; use --unversioned for a working file' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments SHA256 repository captures full commit and tree IDs and resolves immutable recipes" {
	COMMENTS_WORK="$COMMENTS_TMP/sha256"
	git init --quiet --object-format=sha256 "$COMMENTS_WORK"
	cd "$COMMENTS_WORK"
	git config reviewworkflow.base main
	printf 'base line\n' >sample.txt
	git add sample.txt
	git commit --quiet -m base
	COMMENTS_BASE=$(git rev-parse HEAD)
	git switch --quiet -c feature/comments
	printf 'head line\nsecond line\n' >sample.txt
	git commit --quiet -am head
	COMMENTS_TIP=$(git rev-parse HEAD)
	git switch --quiet main
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --path sample.txt --side head --start-line 2 --end-line 2 --text 'Commit capture.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	[[ "$COMMENTS_CONTEXT" =~ ^[0-9a-f]{64}$ ]]
	[ "$(sed -n '/^base /p;/^head /p' "$COMMENTS_LOCAL")" = "$(printf 'base %s\nhead %s' "$COMMENTS_BASE" "$COMMENTS_TIP")" ]
	local base_tree head_tree
	base_tree=$(git rev-parse "$COMMENTS_BASE^{tree}")
	head_tree=$(git rev-parse "$COMMENTS_TIP^{tree}")
	run --separate-stderr git review comments add --document shared --base "$base_tree" --head "$head_tree" --path sample.txt --text 'Tree capture.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(sed -n '/^base /p;/^head /p' "$COMMENTS_SHARED")" = "$(printf 'base %s\nhead %s' "$base_tree" "$head_tree")" ]
	local document
	for document in local shared; do
		run --separate-stderr git review comments diff --document "$document" --entry 1 --porcelain
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-diff" {print}')" = "$(printf 'comment-diff\t1\t%s\t%s' "$base_tree" "$head_tree")" ]
	done
}
