# Byte oracle shared by the format and byte-preservation test families.
# shellcheck disable=SC2154 # The bats runtime and comments_setup own these variables.
comments_check_renumber_fixture() {
	local fixture="$1" document destination
	for document in local shared; do
		if [ "$document" = local ]; then destination=$COMMENTS_LOCAL; else destination=$COMMENTS_SHARED; fi
		cp "$BATS_TEST_DIRNAME/fixtures/comments/$fixture.md" "$destination"
		comments_snapshot "$COMMENTS_TMP/before"
		run --separate-stderr git review comments renumber --document "$document"
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		cmp "$BATS_TEST_DIRNAME/fixtures/comments/$fixture.expected.md" "$destination"
		comments_snapshot "$COMMENTS_TMP/after"
		comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after" head branch refs config index raw-index.bytes staged unstaged worktree objects
		cp "$destination" "$COMMENTS_TMP/first"
		run --separate-stderr git review comments renumber --document "$document"
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		cmp "$COMMENTS_TMP/first" "$destination"
	done
}
