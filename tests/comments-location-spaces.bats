#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments rename capture keeps leading and trailing spaces in literal argv paths" {
	git switch --quiet feature/comments
	printf 'same rename bytes\n' >' old path.txt '
	git add -A
	git commit --quiet -m 'spaced base'
	local base head
	base=$(git rev-parse HEAD)
	git mv ' old path.txt ' ' new path.txt '
	git commit --quiet -m 'spaced head'
	head=$(git rev-parse HEAD)
	git switch --quiet main
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
