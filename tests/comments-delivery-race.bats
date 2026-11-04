#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # bats assigns status/output in each test.
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

# Pause after the destination rename, independent of how staging reads bytes.
pause_after_delivery() {
	local real_mv
	real_mv=$(command -v mv)
	comments_barrier_create "$COMMENTS_TMP/after-delivery"
	mkdir "$COMMENTS_TMP/wrappers"
	export RACE_REAL_MV="$real_mv" RACE_BARRIER="$COMMENTS_TMP/after-delivery"
	export RACE_DESTINATION="$COMMENTS_WORK/.review/comments.md"
	cat >"$COMMENTS_TMP/wrappers/mv" <<'WRAPPER'
#!/bin/sh
set -eu
for argument do
	if [ "$argument" = "$RACE_DESTINATION" ]; then
		"$RACE_REAL_MV" "$@"
		timeout "$COMMENTS_BARRIER_TIMEOUT" sh -c 'printf "ready\n" >"$1/ready"; read -r message <"$1/release"; [ "$message" = release ]' sh "$RACE_BARRIER"
		exit 0
	fi
done
exec "$RACE_REAL_MV" "$@"
WRAPPER
	chmod +x "$COMMENTS_TMP/wrappers/mv"
	export PATH="$COMMENTS_TMP/wrappers:$PATH"
}

check_delivery_race() {
	local changed=$1 writer finish_status=0 prepared context
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Original prepared observation'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	prepared=$COMMENTS_SHARED context=$COMMENTS_CONTEXT
	cp "$prepared" "$COMMENTS_TMP/original"
	pause_after_delivery
	git-review finish >"$COMMENTS_TMP/finish.out" 2>"$COMMENTS_TMP/finish.err" &
	writer=$!
	comments_barrier_arrived "$RACE_BARRIER"
	if [ "$changed" = destination ]; then
		printf 'Concurrent destination observation\n' >.review/comments.md
	else
		printf '\nConcurrent preparation observation\n' >>"$prepared"
	fi
	cp .review/comments.md "$COMMENTS_TMP/destination"
	cp "$prepared" "$COMMENTS_TMP/preparation"
	comments_barrier_resume "$RACE_BARRIER"
	wait "$writer" || finish_status=$?
	[ "$finish_status" -eq 1 ]
	[[ "$(cat "$COMMENTS_TMP/finish.err")" == *'code was extracted but Shared comments could not be prepared'* ]]
	cmp "$COMMENTS_TMP/destination" .review/comments.md
	cmp "$COMMENTS_TMP/preparation" "$prepared"
	[ "$(git diff --cached --name-only)" = '' ]
	comments_refresh_paths
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery" {print $3}')" = pending ]
	# Reconcile explicitly and retry prose only; no code replay or lost update.
	cp "$prepared" .review/comments.md
	run --separate-stderr git review comments prepare --context "$context"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	git show :.review/comments.md >"$COMMENTS_TMP/staged"
	cmp "$COMMENTS_TMP/preparation" "$COMMENTS_TMP/staged"
	[ ! -e "$prepared" ]
	local generation
	generation=$(cat "$(git rev-parse --absolute-git-dir)/review-comments/results/$context/current")
	[ "$(awk -F '\t' '$1=="shared_revision" {print $2}' "$(git rev-parse --absolute-git-dir)/review-comments/results/$context/$generation/manifest")" = "$(git rev-parse :.review/comments.md)" ]
}

@test "comments delivery rejects destination changed after its rename before staging" { check_delivery_race destination; }
@test "comments delivery rejects preparation changed after its rename before staging" { check_delivery_race preparation; }

@test "comments publication preserves preparation edited after staging before publication" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Delivered observation'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local prepared=$COMMENTS_SHARED writer finish_status=0
	cp "$prepared" "$COMMENTS_TMP/delivered"
	# Pause before publication starts, after delivery has already succeeded.
	comments_inject_operation mktemp '*/.generation.XXXXXX' barrier
	git-review finish >"$COMMENTS_TMP/finish.out" 2>"$COMMENTS_TMP/finish.err" &
	writer=$!
	comments_barrier_arrived "$COMMENTS_TMP/inject"
	printf '\nNew preparation from an old editor\n' >>"$prepared"
	cp "$prepared" "$COMMENTS_TMP/current"
	comments_barrier_resume "$COMMENTS_TMP/inject"
	wait "$writer" || finish_status=$?
	[ "$finish_status" -eq 1 ]
	[[ "$(cat "$COMMENTS_TMP/finish.err")" == *'code was extracted but comments results could not be retained'* ]]
	cmp "$COMMENTS_TMP/current" "$prepared"
	git show :.review/comments.md >"$COMMENTS_TMP/staged"
	cmp "$COMMENTS_TMP/delivered" "$COMMENTS_TMP/staged"
	comments_refresh_paths
	[ "$COMMENTS_SHARED" = "$prepared" ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery" {print $3}')" = pending ]
}

@test "comments unchanged incoming Shared preserves edits made before publication" {
	git switch --quiet feature/comments
	mkdir .review
	printf '# Comments\n\n## 1. Incoming\n\nOriginal incoming observation\n' >.review/comments.md
	git add .review/comments.md
	git commit --quiet -m 'Incoming Shared'
	git switch --quiet main
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local prepared=$COMMENTS_SHARED context=$COMMENTS_CONTEXT writer finish_status=0
	cp "$prepared" "$COMMENTS_TMP/incoming"
	comments_inject_operation mktemp '*/.generation.XXXXXX' barrier
	git-review finish >"$COMMENTS_TMP/finish.out" 2>"$COMMENTS_TMP/finish.err" &
	writer=$!
	comments_barrier_arrived "$COMMENTS_TMP/inject"
	printf '\nNew observation after the unchanged decision\n' >>"$prepared"
	cp "$prepared" "$COMMENTS_TMP/current"
	comments_barrier_resume "$COMMENTS_TMP/inject"
	wait "$writer" || finish_status=$?
	[ "$finish_status" -eq 1 ]
	[[ "$(cat "$COMMENTS_TMP/finish.err")" == *'code was extracted but comments results could not be retained'* ]]
	cmp "$COMMENTS_TMP/current" "$prepared"
	cmp "$COMMENTS_TMP/incoming" .review/comments.md
	[ "$(git status --porcelain)" = '' ]
	comments_refresh_paths
	[ "$(printf '%s\n' "$output" | awk -F '\t' -v context="$context" '$1=="comments-document" && $3==context && $4=="shared" {print $2}')" = "$prepared" ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' -v context="$context" '$1=="comments-delivery" && $2==context {print $3}')" = pending ]
}

check_release_race() {
	local changed=$1 writer finish_status=0 prepared
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Delivered observation'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	prepared=$COMMENTS_SHARED
	cp "$prepared" "$COMMENTS_TMP/delivered"
	comments_inject_operation mv '*/current' barrier
	git-review finish >"$COMMENTS_TMP/finish.out" 2>"$COMMENTS_TMP/finish.err" &
	writer=$!
	comments_barrier_arrived "$COMMENTS_TMP/inject"
	case "$changed" in
		preparation) printf '\nNew preparation before release\n' >>"$prepared" ;;
		destination) printf 'New destination before release\n' >.review/comments.md ;;
		index)
			printf 'New staged observation\n' >.review/comments.md
			git add .review/comments.md
			cp "$COMMENTS_TMP/delivered" .review/comments.md
			;;
	esac
	cp "$prepared" "$COMMENTS_TMP/preparation"
	cp .review/comments.md "$COMMENTS_TMP/destination"
	git ls-files --stage >"$COMMENTS_TMP/index"
	comments_barrier_resume "$COMMENTS_TMP/inject"
	wait "$writer" || finish_status=$?
	[ "$finish_status" -eq 1 ]
	printf 'Closure stderr: %s\n' "$(cat "$COMMENTS_TMP/finish.err")"
	if [ "$changed" = preparation ]; then
		[ "$(head -n 1 "$COMMENTS_TMP/finish.err")" = 'error: comments document is stale' ]
	else
		[ "$(head -n 1 "$COMMENTS_TMP/finish.err")" = 'error: Shared changed after staging; the preparation was preserved' ]
	fi
	cmp "$COMMENTS_TMP/preparation" "$prepared"
	cmp "$COMMENTS_TMP/destination" .review/comments.md
	git ls-files --stage >"$COMMENTS_TMP/after-index"
	cmp "$COMMENTS_TMP/index" "$COMMENTS_TMP/after-index"
	comments_refresh_paths
	[ "$COMMENTS_SHARED" = "$prepared" ]
	[ "$(printf '%s\n' "$output" | awk -F '\t' '$1=="comments-delivery" {print $3}')" = pending ]
	if [ "$changed" = index ]; then
		run --separate-stderr git review comments prepare --context "$COMMENTS_CONTEXT"
		[ "$status" -eq 1 ]
		[ "$stderr" = 'error: Shared index entry changed; staged comments and prepared prose were preserved' ]
		git ls-files --stage >"$COMMENTS_TMP/refused-index"
		cmp "$COMMENTS_TMP/index" "$COMMENTS_TMP/refused-index"
		git reset --quiet -- .review/comments.md
	fi
	cp "$prepared" .review/comments.md
	run --separate-stderr git review comments prepare --context "$COMMENTS_CONTEXT"
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ ! -e "$prepared" ]
	git show :.review/comments.md >"$COMMENTS_TMP/retried"
	cmp "$COMMENTS_TMP/preparation" "$COMMENTS_TMP/retried"
	run --separate-stderr git review finish --abort
	[ "$status" -eq 0 ]
	cmp "$COMMENTS_TMP/preparation" "$prepared"
	run --separate-stderr git review abort
	[ "$status" -eq 0 ]
	[ ! -e "$prepared" ]
	[ "$(git status --porcelain)" = '' ]
}

@test "comments release preserves a preparation edited after result publication" { check_release_race preparation; }
@test "comments release preserves a destination edited after staging" { check_release_race destination; }
@test "comments release preserves a concurrent Shared index entry" { check_release_race index; }
