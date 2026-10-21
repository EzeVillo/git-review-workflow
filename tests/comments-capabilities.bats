#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

capabilities() { printf '%s\n' "$output" | awk -F '\t' '$1=="comments-capability" {print $2 "\t" $3}'; }

@test "comments capture capabilities exist before context creation and queries have no effects" {
	local mode expected
	for mode in whole step walk compare; do
		run --separate-stderr comments_start "$mode"
		[ "$status" -eq 0 ]
		comments_snapshot "$COMMENTS_TMP/before"
		run --separate-stderr git review comments status --porcelain
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		if [ "$mode" = compare ]; then expected=$'init\tlocal\nadd\tlocal'
		else expected=$'init\tlocal\ninit\tshared\nadd\tlocal\nadd\tshared'; fi
		[ "$(capabilities)" = "$expected" ]
		comments_snapshot "$COMMENTS_TMP/after"
		comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
		run --separate-stderr git review abort
		[ "$status" -eq 0 ]
	done
}

@test "comments compare rejects Shared init and add before composing or materializing" {
	run --separate-stderr comments_start compare
	[ "$status" -eq 0 ]
	local operation
	for operation in init add; do
		comments_snapshot "$COMMENTS_TMP/before"
		run --separate-stderr env GIT_EDITOR=false git review comments "$operation" --document shared
		[ "$status" -eq 2 ]
		[ "$output" = '' ]
		[ "$stderr" = 'error: shared comments cannot be created in this session' ]
		comments_snapshot "$COMMENTS_TMP/after"
		comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	done
	run --separate-stderr git review comments add --document local --text 'Comparison note.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ -f "$output" ]
	grep -Fx 'Comparison note.' "$output"
	comments_refresh_paths
	[ ! -e "$COMMENTS_SHARED" ]
	comments_snapshot "$COMMENTS_TMP/established"
	run --separate-stderr git review comments add --document shared --text 'Rejected.'
	[ "$status" -eq 2 ]
	[ "$stderr" = 'error: shared comments cannot be created in this session' ]
	comments_snapshot "$COMMENTS_TMP/after-rejection"
	comments_assert_snapshot "$COMMENTS_TMP/established" "$COMMENTS_TMP/after-rejection"
}

@test "comments outside a session offers no capture destination" {
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(capabilities)" = '' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "comments compare automatically retains latest Local bytes on abort without saving code" {
	run --separate-stderr comments_start compare
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'First note.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT path=$COMMENTS_LOCAL
	printf '\nEdited directly in the Markdown editor.\n' >>"$path"
	cp "$path" "$COMMENTS_TMP/expected"
	printf '\nDisposable code edit.\n' >>sample.txt
	run --separate-stderr git review abort
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(git symbolic-ref --short HEAD)" = main ]
	[ -z "$(git status --porcelain)" ]
	[ ! -e "$path" ]
	comments_refresh_paths
	[ "$COMMENTS_CONTEXT" = "$context" ]
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_LOCAL"
	[ ! -e "$COMMENTS_SHARED" ]
	run --separate-stderr git review comments status --porcelain
	[ "$status" -eq 0 ]
	[ "$(capabilities)" = '' ]
	run --separate-stderr git review comments entries --document local --context "$context" --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *'Edited directly in the Markdown editor.'* ]]
}

@test "comments compare failed automatic retention leaves the session and code recoverable" {
	run --separate-stderr comments_start compare
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Keep this note.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local path=$COMMENTS_LOCAL branch
	branch=$(git symbolic-ref --short HEAD)
	cp "$path" "$COMMENTS_TMP/expected"
	comments_inject_operation mv '*/current' fail
	run --separate-stderr git-review abort
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'could not publish comments generation pointer'* ]]
	[ "$(git symbolic-ref --short HEAD)" = "$branch" ]
	cmp "$COMMENTS_TMP/expected" "$path"
}

@test "comments clean retains inactive compare notes automatically" {
	run --separate-stderr comments_start compare
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'Keep after cleaning.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT path=$COMMENTS_LOCAL
	cp "$path" "$COMMENTS_TMP/expected"
	git switch --quiet --discard-changes main
	run --separate-stderr git review clean feature/comments
	[ "$status" -eq 0 ]
	[ ! -e "$path" ]
	[ -z "$(git for-each-ref --format='%(refname)' refs/heads/review/)" ]
	comments_refresh_paths
	[ "$COMMENTS_CONTEXT" = "$context" ]
	cmp "$COMMENTS_TMP/expected" "$COMMENTS_LOCAL"
	[ -z "$(git status --porcelain)" ]
}
