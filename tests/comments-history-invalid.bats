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

check_unreproducible_metadata() {
	printf '## 9. Manual observation\n%s\nBody remains intact.\n' "$1" >"$COMMENTS_LOCAL"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments diff --document local --entry 1 --porcelain
	[ "$status" -eq 5 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comment has no reproducible historical range' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments historical manual prose without references never borrows the current capture range" { check_unreproducible_metadata 'No metadata.'; }
@test "comments historical duplicate keys produce no usable partial reference" { check_unreproducible_metadata "$(printf '<!-- git-review-comment v1\nbase %s\nhead %s\nbase %s\n-->' "$COMMENTS_BASE" "$COMMENTS_TIP" "$COMMENTS_BASE")"; }
@test "comments historical unknown metadata version produces no usable reference" { check_unreproducible_metadata $'<!-- git-review-comment v2\nhead future\n-->'; }
@test "comments historical incomplete object pair produces no usable reference" { check_unreproducible_metadata "$(printf '<!-- git-review-comment v1\nbase %s\n-->' "$COMMENTS_BASE")"; }
@test "comments historical invalid OID produces no usable reference" { check_unreproducible_metadata "$(printf '<!-- git-review-comment v1\nbase unavailable\nhead %s\n-->' "$COMMENTS_TIP")"; }
@test "comments historical unversioned location without objects explicitly has no reproducible range" { check_unreproducible_metadata $'<!-- git-review-comment v1\nhead-path sample.txt\nside head\nstart 4\nend 4\nunversioned 1\n-->'; }

@test "comments historical unversioned objects show only Git content and never the dirty buffer" {
	printf 'DIRTY BUFFER MUST NOT ENTER HISTORY\n' >>sample.txt
	printf '## 9. Unversioned observation\n<!-- git-review-comment v1\nbase %s\nhead %s\nbase-path sample.txt\nhead-path sample.txt\nside head\nstart 4\nend 4\nunversioned 1\n-->\nBody.\n' "$COMMENTS_BASE" "$COMMENTS_TIP" >"$COMMENTS_LOCAL"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments diff --document local --entry 1
	[ "$status" -eq 0 ]
	[ "$stderr" = 'note: the captured location was unversioned; this range shows only the recorded Git objects' ]
	[[ "$output" == *'+changed'* ]]
	[[ "$output" != *'DIRTY BUFFER MUST NOT ENTER HISTORY'* ]]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}
