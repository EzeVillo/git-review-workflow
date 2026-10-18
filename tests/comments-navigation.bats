#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments step navigation keeps both documents and their original per-step capture pairs" {
	run --separate-stderr comments_start step
	[ "$status" -eq 0 ]
	local first
	first=$(git rev-parse feature/comments~1)
	run --separate-stderr git review comments add --document local --path sample.txt --text 'Private first step.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/local"
	printf 'reviewer code edit\n' >>sample.txt
	run --separate-stderr git review next
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --path 'other file.txt' --text 'Shared second step.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/shared"
	[ "$(sed -n '/^base /p;/^head /p' "$COMMENTS_LOCAL")" = "$(printf 'base %s\nhead %s' "$COMMENTS_BASE" "$first")" ]
	[ "$(sed -n '/^base /p;/^head /p' "$COMMENTS_SHARED")" = "$(printf 'base %s\nhead %s' "$first" "$COMMENTS_TIP")" ]
	run --separate-stderr git review prev
	[ "$status" -eq 0 ]
	[ ! -e 'other file.txt' ]
	cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
	run --separate-stderr git review comments diff --document shared --entry 1 --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comment-blob" {print $3 "\t" $4}')" = $'base\tabsent\nhead\tpresent' ]
	local edit
	edit=$(git rev-parse refs/review-edits/feature/comments/1)
	[ "$(git diff --name-only "$edit^" "$edit")" = sample.txt ]
	run --separate-stderr git grep -F 'Private first step.' "$edit" --
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = '' ]
}

@test "comments walk cursor changes guard but keeps the same full-range references and prose" {
	run --separate-stderr comments_start walk
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --path sample.txt --text 'Private walk.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Shared walk.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local guard tip
	guard=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-guard" {print $2}')
	tip=$(git config branch.review/feature/comments.reviewtip)
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/local"
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/shared"
	run --separate-stderr git review next
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-guard" {print $2}')" != "$guard" ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-capture" {print $3 "\t" $4}')" = "$(printf '%s\t%s' "$COMMENTS_BASE" "$tip")" ]
	cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
	run --separate-stderr git review prev
	[ "$status" -eq 0 ]
	cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
}

check_renumber_mode() {
	run --separate-stderr comments_start "$1"
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments init --document local
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local document path
	for document in local shared; do
		if [ "$document" = local ]; then path=$COMMENTS_LOCAL; else path=$COMMENTS_SHARED; fi
		printf '## 9999999999999999999999999999999999999999. Same path\nFirst body.\n## 0.\nSecond body.\n## 0. Same path\nThird body.\n' >"$path"
		printf '## 1. Same path\nFirst body.\n## 2.\nSecond body.\n## 3. Same path\nThird body.\n' >"$COMMENTS_TMP/expected"
		run --separate-stderr git review comments renumber --document "$document"
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		cmp "$COMMENTS_TMP/expected" "$path"
	done
}

@test "comments whole renumber supports both documents and arbitrarily long visible numbers" { check_renumber_mode whole; }
@test "comments walk renumber supports both documents and arbitrarily long visible numbers" { check_renumber_mode walk; }
@test "comments step renumber supports both documents and arbitrarily long visible numbers" { check_renumber_mode step; }
