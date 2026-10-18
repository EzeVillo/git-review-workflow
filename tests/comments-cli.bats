#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

@test "comments all eight subcommands have help and reject unknown repeated or surplus arguments" {
	local command
	for command in status init add renumber entries diff save prepare; do
		run --separate-stderr git review comments "$command" -h
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		[[ "$output" == 'usage: git review comments '* ]]
		run --separate-stderr git review comments "$command" --unknown
		[ "$status" -eq 1 ]
		[ "$output" = '' ]
		[ "$stderr" = 'error: unexpected comments argument: --unknown' ]
		run --separate-stderr git review comments "$command" -- extra
		[ "$status" -eq 1 ]
		[ "$output" = '' ]
		[ "$stderr" = 'error: unexpected comments argument: extra' ]
	done
}

@test "comments capture requires destination on every invocation and rejects incompatible options" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments add --text test
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: --document requires local or shared' ]
	run --separate-stderr git review comments add --document local --text test --stdin
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: --text and --stdin are mutually exclusive' ]
	run --separate-stderr git review comments init --document local --document shared
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: repeated --document' ]
	run --separate-stderr git review comments init --document
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: --document requires a value' ]
	run --separate-stderr git review comments init --document local --new-context --use-context 1111111111111111111111111111111111111111
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: context options are mutually exclusive' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments option values may start with a dash and terminator rejects later options" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text --literal --
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	comments_refresh_paths
	[ "$(tail -n 1 "$COMMENTS_LOCAL")" = --literal ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments status -- --porcelain
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: unexpected comments argument: --porcelain' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments empty option values are rejected except deliberate empty text cancellation" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/before"
	local option
	for option in --path --side --base --head --start-line --expect-context --expect-document; do
		run --separate-stderr git review comments add --document local --text 'Why?' "$option" ''
		[ "$status" -eq 1 ]
		[ "$output" = '' ]
		[ "$stderr" = "error: $option requires a nonempty value" ]
	done
	run --separate-stderr git review comments add --document local --text ''
	[ "$status" -eq 0 ]
	[ "$output" = '' ]
	[ "$stderr" = '' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments every handler rejects a repeated flag and a missing value before testing session scope" {
	local command repeated missing
	comments_snapshot "$COMMENTS_TMP/before"
	for command in status init add renumber entries diff save prepare; do
		case "$command" in
			status|entries|diff|prepare) repeated=--porcelain; set -- --porcelain --porcelain ;;
			save) repeated=--expect-local; set -- --expect-local absent --expect-local absent ;;
			*) repeated=--document; set -- --document local --document local ;;
		esac
		run --separate-stderr git review comments "$command" "$@"
		[ "$status" -eq 1 ]
		[ "$output" = '' ]
		[ "$stderr" = "error: repeated $repeated" ]
		case "$command" in
			status|prepare) missing=--context ;;
			diff) missing=--entry ;;
			save) missing=--expect-local ;;
			*) missing=--document ;;
		esac
		run --separate-stderr git review comments "$command" "$missing"
		[ "$status" -eq 1 ]
		[ "$output" = '' ]
		[ "$stderr" = "error: $missing requires a value" ]
	done
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments ambiguous init and add require explicit context selection without changing preparation" {
	comments_fixture_context 1111111111111111111111111111111111111111
	comments_fixture_context 2222222222222222222222222222222222222222
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments init --document local
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: choose --new-context or --use-context before writing comments' ]
	run --separate-stderr git review comments add --document shared --text 'Keep the selection explicit.'
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[ "$stderr" = 'error: choose --new-context or --use-context before writing comments' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}
