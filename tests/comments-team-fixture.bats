#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "team history fixture uses LF at clone time even with global autocrlf" {
	git config --global core.autocrlf true
	mkdir "$COMMENTS_TMP/history"
	run --separate-stderr sh "$BATS_TEST_DIRNAME/helpers/comments-team-history.sh" init "$COMMENTS_TMP/history"
	[ "$status" -eq 0 ]
	[ "$output" = '' ]
	printf 'base\n' >"$COMMENTS_TMP/expected"
	local actor
	for actor in author reviewer; do
		[ "$(git -C "$COMMENTS_TMP/history/$actor" config core.autocrlf)" = false ]
		[ "$(git -C "$COMMENTS_TMP/history/$actor" status --porcelain)" = '' ]
		cmp "$COMMENTS_TMP/expected" "$COMMENTS_TMP/history/$actor/sample.txt"
	done
	cd "$COMMENTS_TMP/history/reviewer"
	run --separate-stderr git review start --no-walk feature/team
	[ "$status" -eq 0 ]
	[ "$(git branch --show-current)" = review/feature/team ]
	[ "$(git diff --cached --name-only)" = sample.txt ]
}
