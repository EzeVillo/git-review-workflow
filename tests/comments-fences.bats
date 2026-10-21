#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments init --document local
	[ "$status" -eq 0 ]
	comments_refresh_paths
}
teardown() { comments_teardown; }

check_fence_case() {
	printf '%s' "$1" >"$COMMENTS_LOCAL"
	printf '%s' "$2" >"$COMMENTS_TMP/expected"
	run --separate-stderr git review comments renumber --document local
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_LOCAL"
}

@test "comments fence only closes with the same character and sufficient length" {
	check_fence_case $'```` language\n## 9. Hidden\n```\n## 8. Still hidden\n~~~~\n## 7. Still hidden\n`````\n## 9. Real\n' $'```` language\n## 9. Hidden\n```\n## 8. Still hidden\n~~~~\n## 7. Still hidden\n`````\n## 1. Real\n'
}

@test "comments fence with trailing close text does not close the container" {
	check_fence_case $'~~~\n## 9. Hidden\n~~~ trailing\n## 8. Still hidden\n~~~\n## 7. Real\n' $'~~~\n## 9. Hidden\n~~~ trailing\n## 8. Still hidden\n~~~\n## 1. Real\n'
}

@test "comments fence accepts zero through three leading spaces but not four" {
	local indent
	for indent in '' ' ' '  ' '   '; do
		check_fence_case "$(printf '%s~~~\n## 9. Hidden\n%s~~~\n## 9. Real\n' "$indent" "$indent")" "$(printf '%s~~~\n## 9. Hidden\n%s~~~\n## 1. Real\n' "$indent" "$indent")"
	done
	check_fence_case $'    ~~~\n## 9. Real\n' $'    ~~~\n## 1. Real\n'
}

@test "comments backtick in a backtick info string is not an opening fence" {
	check_fence_case $'``` invalid`info\n## 9. Real\n' $'``` invalid`info\n## 1. Real\n'
}

@test "comments quoted fences and quoted headings do not hide the next real heading" {
	check_fence_case $'> ```\n> ## 9. Quoted\n> ```\n## 9. Real\n' $'> ```\n> ## 9. Quoted\n> ```\n## 1. Real\n'
}

@test "comments closed HTML containers preserve headings inside as prose" {
	check_fence_case $'<!--\n## 9. Hidden\n-->\n## 9. Real\n' $'<!--\n## 9. Hidden\n-->\n## 1. Real\n'
}
