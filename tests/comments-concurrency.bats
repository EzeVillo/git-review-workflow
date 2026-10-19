#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	run --separate-stderr comments_start step
	[ "$status" -eq 0 ]
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_session
}
teardown() { comments_teardown; }

@test "comments guard changes with step cursor even while tip remains the same" {
	local guard
	guard=$(comments_driver guard)
	run --separate-stderr git review next
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/comments.reviewtip)" = "$COMMENTS_TIP" ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr comments_driver check "$guard" absent "$COMMENTS_SESSION_DIR/local.md"
	[ "$status" -eq 4 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments context is stale' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments guard rejects bytes and absence changed after composition" {
	local guard revision
	guard=$(comments_driver guard)
	printf 'first\n' >"$COMMENTS_SESSION_DIR/local.md"
	revision=$(git hash-object --no-filters "$COMMENTS_SESSION_DIR/local.md")
	printf 'other\n' >"$COMMENTS_SESSION_DIR/local.md"
	comments_snapshot "$COMMENTS_TMP/before"
	for revision in absent "$revision"; do
		run --separate-stderr comments_driver check "$guard" "$revision" "$COMMENTS_SESSION_DIR/local.md"
		[ "$status" -eq 4 ]
		[ "$output" = '' ]
		[ "$stderr" = 'error: comments document is stale' ]
	done
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments guard rejects changed branch custodian and endpoints" {
	local guard
	guard=$(comments_driver guard)
	git config branch.review/feature/comments.reviewtip "$COMMENTS_BASE"
	run --separate-stderr comments_driver check "$guard" absent "$COMMENTS_SESSION_DIR/local.md"
	[ "$status" -eq 4 ]
	[ "$stderr" = 'error: comments context is stale' ]
	git config branch.review/feature/comments.reviewtip "$COMMENTS_TIP"
	git switch --quiet --detach HEAD
	run --separate-stderr comments_driver check "$guard" absent "$COMMENTS_SESSION_DIR/local.md"
	[ "$status" -eq 4 ]
	[ "$stderr" = 'error: comments context is stale' ]
}

@test "comments writer keeps an externally changed original and recoverable candidate" {
	local revision
	printf 'original\n' >"$COMMENTS_SESSION_DIR/local.md"
	printf 'candidate\n' >"$COMMENTS_TMP/candidate"
	revision=$(git hash-object --no-filters "$COMMENTS_SESSION_DIR/local.md")
	comments_inject_operation cp '*/local.md.candidate.*' barrier
	comments_driver write "$COMMENTS_CONTEXT" "$COMMENTS_SESSION_DIR/local.md" "$COMMENTS_TMP/candidate" "$revision" >"$COMMENTS_TMP/writer.out" 2>"$COMMENTS_TMP/writer.err" &
	local writer=$!
	comments_barrier_arrived "$COMMENTS_TMP/inject"
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
	printf 'external\n' >"$COMMENTS_SESSION_DIR/local.md"
	comments_barrier_resume "$COMMENTS_TMP/inject"
	local writer_status=0
	wait "$writer" || writer_status=$?
	[ "$writer_status" -eq 4 ]
	[ ! -s "$COMMENTS_TMP/writer.out" ]
	[[ "$(cat "$COMMENTS_TMP/writer.err")" == 'error: comments document is stale; candidate preserved at '* ]]
	[ "$(cat "$COMMENTS_SESSION_DIR/local.md")" = external ]
	local recovery
	recovery=$(cat "$COMMENTS_TMP/inject/hit/argument")
	cmp "$COMMENTS_TMP/candidate" "$recovery"
	[ ! -e "$COMMENTS_ROOT/locks/$COMMENTS_CONTEXT.lock" ]
}

@test "comments cooperating writers serialize by refusing a live context lock" {
	comments_barrier_create "$COMMENTS_TMP/hold"
	comments_driver lock "$COMMENTS_CONTEXT" "$COMMENTS_TMP/hold" >"$COMMENTS_TMP/holder.out" 2>"$COMMENTS_TMP/holder.err" &
	local holder=$!
	comments_barrier_arrived "$COMMENTS_TMP/hold"
	printf 'candidate\n' >"$COMMENTS_TMP/candidate"
	run --separate-stderr comments_driver write "$COMMENTS_CONTEXT" "$COMMENTS_SESSION_DIR/local.md" "$COMMENTS_TMP/candidate" absent
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: comments context is locked' ]
	[ ! -e "$COMMENTS_SESSION_DIR/local.md" ]
	comments_barrier_resume "$COMMENTS_TMP/hold"
	wait "$holder"
	[ ! -s "$COMMENTS_TMP/holder.err" ]
}

@test "comments public add rechecks the capture cursor before replacing even without caller guards" {
	printf '## 1. Existing\nKeep the original.\n' >"$COMMENTS_SESSION_DIR/local.md"
	cp "$COMMENTS_SESSION_DIR/local.md" "$COMMENTS_TMP/original"
	comments_inject_operation cp '*/local.md.candidate.*' barrier
	git-review comments add --document local --text 'New body from the old cursor.' >"$COMMENTS_TMP/writer.out" 2>"$COMMENTS_TMP/writer.err" &
	local writer=$!
	comments_barrier_arrived "$COMMENTS_TMP/inject"
	git config branch.review/feature/comments.reviewstep 2
	comments_barrier_resume "$COMMENTS_TMP/inject"
	local writer_status=0
	wait "$writer" || writer_status=$?
	[ "$writer_status" -eq 4 ]
	[ ! -s "$COMMENTS_TMP/writer.out" ]
	[[ "$(cat "$COMMENTS_TMP/writer.err")" == 'error: comments document is stale; candidate preserved at '* ]]
	cmp "$COMMENTS_TMP/original" "$COMMENTS_SESSION_DIR/local.md"
	local recovery
	recovery=$(cat "$COMMENTS_TMP/inject/hit/argument")
	[ "$(tail -n 1 "$recovery")" = 'New body from the old cursor.' ]
	[ ! -e "$COMMENTS_SESSION_DIR/shared.md" ]
}

@test "comments first mutation rejects a stale document revision before creating any storage" {
	# Keep a valid review but remove the independently seeded comments fixture.
	git config --unset branch.review/feature/comments.reviewcommentscontext
	git config --unset branch.review/feature/comments.reviewcommentssession
	git config --unset branch.review/feature/comments.reviewcommentsowner
	rm -rf "$COMMENTS_ROOT"
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments add --document local --text 'No changes.' --expect-document 1111111111111111111111111111111111111111
	[ "$status" -eq 4 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments document is stale' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

reset_comments_fixture() {
	git config --unset branch.review/feature/comments.reviewcommentscontext
	git config --unset branch.review/feature/comments.reviewcommentssession
	git config --unset branch.review/feature/comments.reviewcommentsowner
	rm -rf "$COMMENTS_ROOT"
}

@test "comments first fresh composer rejects a moved step and leaves storage absent" {
	reset_comments_fixture
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	local guard
	guard=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-guard" {print $2}')
	[ -n "$guard" ]
	run --separate-stderr git review next
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments add --document local --text 'Stale form.' --expect-context "$guard" --expect-document absent
	[ "$status" -eq 4 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments context is stale' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments first ambiguous composer retains its original guard while choosing a context" {
	reset_comments_fixture
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_context 2222222222222222222222222222222222222222
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	local guard
	guard=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-guard" {print $2}')
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-identity" {print $2}')" = ambiguous ]
	run --separate-stderr git review next
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments init --document local --use-context 1111111111111111111111111111111111111111 --expect-context "$guard" --expect-document absent
	[ "$status" -eq 4 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: comments context is stale' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}
