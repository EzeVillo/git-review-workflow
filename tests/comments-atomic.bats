#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() {
	comments_setup
	comments_fixture_context 1111111111111111111111111111111111111111 compare
	comments_fixture_result
	printf 'old local\n' >"$COMMENTS_RESULT_DIR/local.md"
	printf 'old shared\n' >"$COMMENTS_RESULT_DIR/shared.md"
	printf 'context\t%s\nlocal\tpresent\nshared\tpresent\n' "$COMMENTS_CONTEXT" >"$COMMENTS_RESULT_DIR/manifest"
	COMMENTS_INPUT="$COMMENTS_TMP/input"
	mkdir "$COMMENTS_INPUT"
}
teardown() { comments_teardown; }

@test "comments generations publish absent empty and present as distinct document states" {
	local state
	for state in absent empty present; do
		case "$state" in
			absent) ;;
			empty) : >"$COMMENTS_INPUT/local.md"; : >"$COMMENTS_INPUT/shared.md" ;;
			present) printf 'new local\n' >"$COMMENTS_INPUT/local.md"; printf 'new shared\n' >"$COMMENTS_INPUT/shared.md" ;;
		esac
		run --separate-stderr comments_driver publish "$COMMENTS_CONTEXT" "$COMMENTS_INPUT"
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		local generation destination
		generation=$(cat "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/current")
		[[ "$generation" =~ ^[0-9a-f]{40,64}$ ]]
		destination="$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/$generation"
		comments_assert_file "$destination/local.md" "$COMMENTS_INPUT/local.md"
		comments_assert_file "$destination/shared.md" "$COMMENTS_INPUT/shared.md"
		[ "$(awk -F '\t' '$1 == "context" {print $2}' "$destination/manifest")" = "$COMMENTS_CONTEXT" ]
		[ "$(awk -F '\t' '$1 == "local" {print $2}' "$destination/manifest")" = "$(if [ "$state" = absent ]; then printf absent; else printf present; fi)" ]
	done
}

@test "comments generations fail each copy and retain complete previous generation" {
	local document
	printf 'new local\n' >"$COMMENTS_INPUT/local.md"
	printf 'new shared\n' >"$COMMENTS_INPUT/shared.md"
	for document in local shared; do
		comments_inject_operation cp "*/$document.md" fail
		run --separate-stderr comments_driver publish "$COMMENTS_CONTEXT" "$COMMENTS_INPUT"
		[ "$status" -eq 1 ]
		[ "$output" = '' ]
		[[ "$stderr" == *'injected operation failure'* ]]
		[ -f "$COMMENTS_TMP/inject/hit/argument" ]
		[ "$(cat "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/current")" = 4444444444444444444444444444444444444444 ]
		[ "$(cat "$COMMENTS_RESULT_DIR/local.md")" = 'old local' ]
		[ "$(cat "$COMMENTS_RESULT_DIR/shared.md")" = 'old shared' ]
		# Remove only the wrapper's one-shot hit, so the next document is tested.
		rm "$COMMENTS_TMP/inject/hit/argument"
		rmdir "$COMMENTS_TMP/inject/hit"
		# Restore PATH before constructing the next wrapper (avoid wrapper recursion).
		export PATH="${PATH#*:}"
	done
}

@test "comments generations failed current rename never exposes a mixed pair and retry succeeds" {
	printf 'new local\n' >"$COMMENTS_INPUT/local.md"
	printf 'new shared\n' >"$COMMENTS_INPUT/shared.md"
	comments_inject_operation mv '*/current' fail
	run --separate-stderr comments_driver publish "$COMMENTS_CONTEXT" "$COMMENTS_INPUT"
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[[ "$stderr" == *'injected operation failure'* ]]
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
	[ "$(cat "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/current")" = 4444444444444444444444444444444444444444 ]
	[ "$(cat "$COMMENTS_RESULT_DIR/local.md")" = 'old local' ]
	[ "$(cat "$COMMENTS_RESULT_DIR/shared.md")" = 'old shared' ]
	run --separate-stderr comments_driver publish "$COMMENTS_CONTEXT" "$COMMENTS_INPUT"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	local generation
	generation=$(cat "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/current")
	[ "$generation" != 4444444444444444444444444444444444444444 ]
	cmp "$COMMENTS_INPUT/local.md" "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/$generation/local.md"
	cmp "$COMMENTS_INPUT/shared.md" "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/$generation/shared.md"
}

@test "comments generations reject a failed manifest publish and retry the complete pair" {
	printf 'new local\n' >"$COMMENTS_INPUT/local.md"
	: >"$COMMENTS_INPUT/shared.md"
	comments_inject_operation mv '*/manifest' fail
	run --separate-stderr comments_driver publish "$COMMENTS_CONTEXT" "$COMMENTS_INPUT"
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[[ "$stderr" == *'injected operation failure'* ]]
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
	[ "$(cat "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/current")" = 4444444444444444444444444444444444444444 ]
	run --separate-stderr comments_driver publish "$COMMENTS_CONTEXT" "$COMMENTS_INPUT"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	local generation
	generation=$(cat "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/current")
	cmp "$COMMENTS_INPUT/local.md" "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/$generation/local.md"
	cmp "$COMMENTS_INPUT/shared.md" "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/$generation/shared.md"
}

@test "comments generations detect source corruption during validation without changing current" {
	printf 'new local\n' >"$COMMENTS_INPUT/local.md"
	printf 'new shared\n' >"$COMMENTS_INPUT/shared.md"
	comments_inject_operation cmp '*/local.md' fail
	run --separate-stderr comments_driver publish "$COMMENTS_CONTEXT" "$COMMENTS_INPUT"
	[ "$status" -eq 4 ]
	[ "$output" = '' ]
	[[ "$stderr" == *'injected operation failure'* ]]
	[[ "$stderr" == *'error: comments document is stale'* ]]
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
	[ "$(cat "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/current")" = 4444444444444444444444444444444444444444 ]
}

@test "comments generations do not let mv follow a concurrent current directory" {
	printf 'new local\n' >"$COMMENTS_INPUT/local.md"
	rm "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/current"
	mkdir "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/current"
	run --separate-stderr comments_driver publish "$COMMENTS_CONTEXT" "$COMMENTS_INPUT"
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[[ "$stderr" == 'error: unsafe comments path: '* ]]
	[ -z "$(find "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/current" -mindepth 1 -print)" ]
}

prepare_input_state() {
	case "$1" in
		absent) ;;
		empty) : >"$COMMENTS_INPUT/local.md"; : >"$COMMENTS_INPUT/shared.md" ;;
		present) printf 'new local\n' >"$COMMENTS_INPUT/local.md"; printf 'new shared\n' >"$COMMENTS_INPUT/shared.md" ;;
	esac
}

assert_failed_generation() {
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$(cat "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/current")" = 4444444444444444444444444444444444444444 ]
	[ "$(cat "$COMMENTS_RESULT_DIR/local.md")" = 'old local' ]
	[ "$(cat "$COMMENTS_RESULT_DIR/shared.md")" = 'old shared' ]
}

check_create_fault() {
	prepare_input_state "$1"
	comments_inject_operation mktemp "$2" fail
	run --separate-stderr comments_driver publish "$COMMENTS_CONTEXT" "$COMMENTS_INPUT"
	assert_failed_generation
	[ -f "$COMMENTS_TMP/inject/hit/argument" ]
	[[ "$stderr" == *'injected operation failure'* ]]
	run --separate-stderr comments_driver publish "$COMMENTS_CONTEXT" "$COMMENTS_INPUT"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	local destination
	destination="$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/$(cat "$COMMENTS_ROOT/results/$COMMENTS_CONTEXT/current")"
	comments_assert_file "$destination/local.md" "$COMMENTS_INPUT/local.md"
	comments_assert_file "$destination/shared.md" "$COMMENTS_INPUT/shared.md"
}

check_manifest_fault() {
	prepare_input_state "$1"
	run --separate-stderr env COMMENTS_FAIL_MANIFEST=1 sh -eu "$BATS_TEST_DIRNAME/helpers/comments-driver.sh" publish "$COMMENTS_CONTEXT" "$COMMENTS_INPUT"
	assert_failed_generation
	[ "$stderr" = 'error: could not write comments generation manifest' ]
	[ "$(cat "$COMMENTS_TMP/manifest-write.hit")" = hit ]
	run --separate-stderr comments_driver publish "$COMMENTS_CONTEXT" "$COMMENTS_INPUT"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
}

@test "comments generation creation failure preserves absent pair and retries" { check_create_fault absent '*/.generation.*'; }
@test "comments generation creation failure preserves empty pair and retries" { check_create_fault empty '*/.generation.*'; }
@test "comments generation creation failure preserves present pair and retries" { check_create_fault present '*/.generation.*'; }
@test "comments pointer creation failure preserves absent pair and retries" { check_create_fault absent '*/current.candidate.*'; }
@test "comments pointer creation failure preserves empty pair and retries" { check_create_fault empty '*/current.candidate.*'; }
@test "comments pointer creation failure preserves present pair and retries" { check_create_fault present '*/current.candidate.*'; }
@test "comments manifest write failure preserves absent pair and retries" { check_manifest_fault absent; }
@test "comments manifest write failure preserves empty pair and retries" { check_manifest_fault empty; }
@test "comments manifest write failure preserves present pair and retries" { check_manifest_fault present; }
