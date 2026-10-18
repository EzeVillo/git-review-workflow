#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --path sample.txt --side head --start-line 2 --end-line 2 --text 'Observe H1.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
}
teardown() { comments_teardown; }

@test "comments historical recipe resolves original immutable trees blobs and coordinates" {
	local base_tree head_tree base_blob head_blob
	base_tree=$(git rev-parse "$COMMENTS_BASE^{tree}")
	head_tree=$(git rev-parse "$COMMENTS_TIP^{tree}")
	base_blob=$(git rev-parse "$COMMENTS_BASE:sample.txt")
	head_blob=$(git rev-parse "$COMMENTS_TIP:sample.txt")
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments diff --document local --entry 1 --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$output" = "$(printf 'comment-diff\t1\t%s\t%s\ncomment-blob\tsample.txt\tbase\tpresent\t%s\ncomment-blob\tsample.txt\thead\tpresent\t%s\ncomment-location\t1\thead\t2\t2' "$base_tree" "$head_tree" "$base_blob" "$head_blob")" ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments historical diff still opens original code after current file deletion" {
	rm sample.txt
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments diff --document local --entry 1
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	git --no-pager diff --no-ext-diff --no-textconv "$COMMENTS_BASE" "$COMMENTS_TIP" -- ':(literal)sample.txt' >"$COMMENTS_TMP/expected-diff"
	printf '%s\n' "$output" >"$COMMENTS_TMP/actual-diff"
	cmp "$COMMENTS_TMP/expected-diff" "$COMMENTS_TMP/actual-diff"
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments historical selection rejects a stale revision even with the same visible number" {
	local revision
	revision=$(git hash-object --no-filters "$COMMENTS_LOCAL")
	printf '\n## 1. Duplicate number\nOther body\n' >>"$COMMENTS_LOCAL"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments diff --document local --entry 1 --expect-document "$revision" --porcelain
	[ "$status" -eq 4 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments document is stale' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments historical missing object returns five without partial recipe or HEAD fallback" {
	printf '## 8. Missing\n\n<!-- git-review-comment v1\nbase 1111111111111111111111111111111111111111\nhead %s\n-->\n' "$COMMENTS_TIP" >"$COMMENTS_LOCAL"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments diff --document local --entry 1 --porcelain
	[ "$status" -eq 5 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: historical revision or content not found' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments historical manual entry never substitutes the current range" {
	printf '## 1. Manual\nNo references.\n' >"$COMMENTS_LOCAL"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments diff --document local --entry 1
	[ "$status" -eq 5 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comment has no reproducible historical range' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments historical general recipe rejects a missing tree even when its commit survives" {
	local tree
	tree=$(git rev-parse "$COMMENTS_TIP^{tree}")
	printf '## 1. General\n\n<!-- git-review-comment v1\nbase %s\nhead %s\n-->\n' "$COMMENTS_BASE" "$COMMENTS_TIP" >"$COMMENTS_LOCAL"
	rm ".git/objects/${tree:0:2}/${tree:2}"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments diff --document local --entry 1 --porcelain
	[ "$status" -eq 5 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: historical revision or content not found' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments two historical pairs survive renumber a later commit another branch and current file deletion" {
	local fixture_index="$COMMENTS_TMP/fixture-index" blob tree h2
	blob=$(printf 'first\nchanged again\nthird\n' | git hash-object -w --stdin)
	GIT_INDEX_FILE="$fixture_index" git read-tree "$COMMENTS_TIP^{tree}"
	GIT_INDEX_FILE="$fixture_index" git update-index --cacheinfo "100644,$blob,sample.txt"
	tree=$(GIT_INDEX_FILE="$fixture_index" git write-tree)
	h2=$(git commit-tree "$tree" -p "$COMMENTS_TIP" -m 'Historical second pair fixture')
	run --separate-stderr git review comments add --document local --base "$COMMENTS_TIP" --head "$h2" --path sample.txt --side head --start-line 2 --end-line 2 --text 'Observe H2.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	# Deliberately repeat visible numbers, then use physical ordinals after the
	# real renumber operation. Expected trees come from the fixture, never HEAD.
	sed 's/^## [0-9][0-9]*\./## 9./' "$COMMENTS_LOCAL" >"$COMMENTS_TMP/repeated"
	cp "$COMMENTS_TMP/repeated" "$COMMENTS_LOCAL"
	run --separate-stderr git review comments renumber --document local
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	git switch --quiet -c historical-reader
	printf 'H3 is unrelated to both observations.\n' >sample.txt
	git add sample.txt
	git commit --quiet -m H3
	rm sample.txt
	local ordinal expected_base expected_head
	for ordinal in 1 2; do
		if [ "$ordinal" -eq 1 ]; then expected_base=$(git rev-parse "$COMMENTS_BASE^{tree}"); expected_head=$(git rev-parse "$COMMENTS_TIP^{tree}")
		else expected_base=$(git rev-parse "$COMMENTS_TIP^{tree}"); expected_head=$tree
		fi
		comments_snapshot "$COMMENTS_TMP/before"
		run --separate-stderr git review comments diff --document local --entry "$ordinal" --porcelain
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-diff" {print}')" = "$(printf 'comment-diff\t%s\t%s\t%s' "$ordinal" "$expected_base" "$expected_head")" ]
		comments_snapshot "$COMMENTS_TMP/after"
		comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	done
}
