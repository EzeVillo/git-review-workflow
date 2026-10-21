#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments history keeps hostile UTF-8 and metacharacter paths literal and decodes only once" {
	local names=('a space.txt' 'acentó.txt' '-leading.txt' 'wild*.txt' 'quest?.txt' 'colon:name.txt' 'percent%3E.txt' 'greater>.txt' 'tick`$(oops).txt' 'percent%09.txt')
	local encoded=('a space.txt' 'acentó.txt' '-leading.txt' 'wild*.txt' 'quest?.txt' 'colon:name.txt' 'percent%253E.txt' 'greater%3E.txt' 'tick`$(oops).txt' 'percent%2509.txt')
	git switch --quiet feature/comments
	local name
	for name in "${names[@]}"; do printf 'old\n' >"$name"; done
	git add -A
	git commit --quiet -m 'path base'
	local base head
	base=$(git rev-parse HEAD)
	for name in "${names[@]}"; do printf 'new\n' >"$name"; done
	git add -A
	git commit --quiet -m 'path head'
	head=$(git rev-parse HEAD)
	git switch --quiet main
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	local i base_tree head_tree base_blob head_blob
	base_tree=$(git rev-parse "$base^{tree}")
	head_tree=$(git rev-parse "$head^{tree}")
	for ((i=0; i<${#names[@]}; i++)); do
		name=${names[$i]}
		run --separate-stderr git review comments add --document local --base "$base" --head "$head" --path "$name" --side head --start-line 1 --end-line 1 --text 'Keep this path literal.'
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		base_blob=$(git rev-parse "$base:$name")
		head_blob=$(git rev-parse "$head:$name")
		comments_snapshot "$COMMENTS_TMP/before"
		run --separate-stderr git review comments diff --document local --entry "$((i+1))" --porcelain
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		[ "$output" = "$(printf 'comment-diff\t%s\t%s\t%s\ncomment-blob\t%s\tbase\tpresent\t%s\ncomment-blob\t%s\thead\tpresent\t%s\ncomment-location\t%s\thead\t1\t1' "$((i+1))" "$base_tree" "$head_tree" "${encoded[$i]}" "$base_blob" "${encoded[$i]}" "$head_blob" "$((i+1))")" ]
		comments_snapshot "$COMMENTS_TMP/after"
		comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	done
	[ ! -e oops ]
}

@test "comments rename recipe preserves both names and addition deletion distinguish absent from empty" {
	git switch --quiet feature/comments
	printf 'unchanged rename contents\n' >'old name.txt'
	printf 'removed\n' >deleted.txt
	git add -A
	git commit --quiet -m 'rename base'
	local base head
	base=$(git rev-parse HEAD)
	git mv 'old name.txt' 'new name.txt'
	rm deleted.txt
	: >empty.txt
	git add -A
	git commit --quiet -m 'rename head'
	head=$(git rev-parse HEAD)
	git switch --quiet main
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --base "$base" --head "$head" --path 'new name.txt' --text Rename
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	run --separate-stderr git review comments diff --document shared --entry 1 --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-blob" {print $2 "\t" $3 "\t" $4}')" = $'old name.txt\tbase\tpresent\nnew name.txt\thead\tpresent' ]
	run --separate-stderr git review comments add --document shared --base "$base" --head "$head" --path empty.txt --text Addition
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments diff --document shared --entry 2 --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	local empty_blob
	empty_blob=$(printf '' | git hash-object --stdin)
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-blob" {print}')" = "$(printf 'comment-blob\tempty.txt\tbase\tabsent\ncomment-blob\tempty.txt\thead\tpresent\t%s' "$empty_blob")" ]
	run --separate-stderr git review comments add --document shared --base "$base" --head "$head" --path deleted.txt --text Deletion
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments diff --document shared --entry 3 --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-blob" {print $3 "\t" $4}')" = $'base\tpresent\nhead\tabsent' ]
}

@test "comments history rejects TSV control paths after exactly one decode without a partial recipe" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments init --document local
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local encoded
	for encoded in 'sample%09.txt' 'sample%0D.txt' 'sample.txt%0A'; do
		printf '## 1. Manual\n<!-- git-review-comment v1\nbase %s\nhead %s\nhead-path %s\n-->\n' "$COMMENTS_BASE" "$COMMENTS_TIP" "$encoded" >"$COMMENTS_LOCAL"
		comments_snapshot "$COMMENTS_TMP/before"
		run --separate-stderr git review comments diff --document local --entry 1 --porcelain
		[ "$status" -eq 1 ]
		[ "$output" = '' ]
		[ "$stderr" = 'error: comment path cannot be represented in porcelain' ]
		comments_snapshot "$COMMENTS_TMP/after"
		comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	done
}
