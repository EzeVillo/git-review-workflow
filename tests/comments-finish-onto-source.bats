#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

check_onto_source() {
	run --separate-stderr comments_start "$1"
	[ "$status" -eq 0 ]
	local tip
	tip=$(git config branch.review/feature/comments.reviewtip)
	run --separate-stderr git review comments add --document local --text 'Private onto-source observation.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Shared onto-source observation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/prepared"
	printf 'reviewer correction\n' >>sample.txt
	run --separate-stderr git review finish --onto-source
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = feature/comments ]
	[ "$(git rev-parse HEAD)" = "$tip" ]
	[ "$(git diff --cached --name-only)" = sample.txt ]
	cmp "$COMMENTS_TMP/prepared" .review/comments.md
	[ "$(git ls-files -- .review/comments.md)" = '' ]
	comments_refresh_paths
	[ "$(tail -n 1 "$COMMENTS_LOCAL")" = 'Private onto-source observation.' ]
}

@test "comments whole onto-source delivers Shared to the actual source output" { check_onto_source whole; }
@test "comments walk onto-source delivers Shared to the actual source output" { check_onto_source walk; }
@test "comments step onto-source delivers Shared to the actual source output" { check_onto_source step; }

@test "comments onto-source advanced branch guard preserves prepared documents and does not deliver" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Keep this prepared observation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/prepared"
	local advanced
	advanced=$(git commit-tree "$(git rev-parse "$COMMENTS_TIP^{tree}")" -p "$COMMENTS_TIP" -m 'Author advances the source')
	git update-ref refs/heads/feature/comments "$advanced" "$COMMENTS_TIP"
	run --separate-stderr git review finish --onto-source
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'local feature/comments is not at the reviewed tip'* ]]
	[ "$(git rev-parse feature/comments)" = "$advanced" ]
	[ "$(git symbolic-ref --short HEAD)" = review/feature/comments ]
	[ ! -e .review/comments.md ]
	cmp "$COMMENTS_TMP/prepared" "$COMMENTS_SHARED"
}
