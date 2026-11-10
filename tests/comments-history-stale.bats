#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'First physical entry.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
}
teardown() { comments_teardown; }

@test "comments history zero out of range and huge ordinals fail with precise diagnostics" {
	comments_snapshot "$COMMENTS_TMP/before"
	local ordinal
	for ordinal in 0 2 99999999999999999999999999999999999999999999999999; do
		run --separate-stderr git review comments diff --document local --entry "$ordinal" --porcelain
		[ "$status" -eq 1 ]
		[ "$output" = '' ]
		if [ "$ordinal" = 0 ]; then [ "$stderr" = 'error: --entry requires a positive physical ordinal' ]
		else [ "$stderr" = 'error: comment entry not found' ]
		fi
	done
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments history picker cannot reopen an entry after its visible numbers were renumbered" {
	sed 's/^## 1\./## 9./' "$COMMENTS_LOCAL" >"$COMMENTS_TMP/number-nine"
	cp "$COMMENTS_TMP/number-nine" "$COMMENTS_LOCAL"
	local revision
	revision=$(git hash-object --no-filters "$COMMENTS_LOCAL")
	run --separate-stderr git review comments renumber --document local
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments diff --document local --entry 1 --expect-document "$revision" --porcelain
	[ "$status" -eq 4 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments document is stale' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments history rejects a replacement between revision validation and reading the entry" {
	run --separate-stderr git review comments add --document local --path 'other file.txt' --side head --text 'Second physical entry.'
	[ "$status" -eq 0 ]
	local revision
	revision=$(git hash-object --no-filters "$COMMENTS_LOCAL")
	sed -n '/^## 2\./,$p' "$COMMENTS_LOCAL" >"$COMMENTS_TMP/replacement"
	export HISTORY_REAL_GIT="$(command -v git)" HISTORY_PATH="$COMMENTS_LOCAL"
	mkdir "$COMMENTS_TMP/race"
	cat >"$COMMENTS_TMP/race/git" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = hash-object ] && [ "${2:-}" = --no-filters ] &&
	[ "${4:-}" = "$HISTORY_PATH" ] && [ ! -e "$COMMENTS_TMP/race/hit" ]; then
	"$HISTORY_REAL_GIT" "$@"
	cp "$COMMENTS_TMP/replacement" "$HISTORY_PATH"
	: >"$COMMENTS_TMP/race/hit"
	exit 0
fi
exec "$HISTORY_REAL_GIT" "$@"
EOF
	chmod +x "$COMMENTS_TMP/race/git"
	run --separate-stderr env PATH="$COMMENTS_TMP/race:$PATH" sh "$BATS_TEST_DIRNAME/../bin/git-review" comments diff --document local --entry 1 --expect-document "$revision" --porcelain
	[ -f "$COMMENTS_TMP/race/hit" ]
	[ "$status" -eq 4 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments document is stale' ]
	cmp "$COMMENTS_TMP/replacement" "$COMMENTS_LOCAL"
}
