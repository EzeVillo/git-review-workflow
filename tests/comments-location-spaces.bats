#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments rename capture keeps leading and trailing spaces in literal argv paths" {
	# A trailing space is legal in a Git tree but cannot be checked out by
	# Win32. Exercise the same real rename through objects on every platform.
	local base head blob tree
	blob=$(printf 'same rename bytes\n' | git hash-object -w --stdin)
	tree=$(printf '100644 blob %s\t old path.txt \0' "$blob" | git mktree -z)
	base=$(printf 'spaced base\n' | git commit-tree "$tree" -p "$COMMENTS_TIP")
	tree=$(printf '100644 blob %s\t new path.txt \0' "$blob" | git mktree -z)
	head=$(printf 'spaced head\n' | git commit-tree "$tree" -p "$base")
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --base "$base" --head "$head" --path ' new path.txt ' --text 'Literal path.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	[ "$(sed -n '/^base-path /p;/^head-path /p' "$COMMENTS_LOCAL")" = $'base-path  old path.txt \nhead-path  new path.txt ' ]
	run --separate-stderr git review comments diff --document local --entry 1 --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-blob" {print $2 "\t" $3 "\t" $4}')" = $' old path.txt \tbase\tpresent\n new path.txt \thead\tpresent' ]
}
