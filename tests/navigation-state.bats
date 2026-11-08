#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

reply_equals_status() {
	printf '%s\n' "$output" | sed '/^navigation	/d; /^notice	/d; /^why	/d; /^why-line	/d' >"$COMMENTS_TMP/reply"
	git review status --porcelain >"$COMMENTS_TMP/status"
	cmp "$COMMENTS_TMP/reply" "$COMMENTS_TMP/status"
}

@test "walk navigation returns the complete updated status without changing code" {
	comments_start walk >/dev/null
	git diff --binary HEAD >"$COMMENTS_TMP/before"
	guard=$(git review status --porcelain | awk -F '\t' '$1=="guard" {print $2}')
	run --separate-stderr git review --expect-state "$guard" next --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(git config branch.review/feature/comments.reviewwalkstep)" = 2 ]
	[[ "$output" == *"$(printf 'navigation\tmoved')" ]]
	reply_equals_status
	git diff --binary HEAD >"$COMMENTS_TMP/after"
	cmp "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
	run --separate-stderr git review prev --porcelain
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/comments.reviewwalkstep)" = 1 ]
	reply_equals_status
}

@test "step reply includes the new HEAD banked edits subjects authors and files" {
	comments_start step >/dev/null
	printf 'private edit\n' >>sample.txt
	run --separate-stderr git review next --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(git config branch.review/feature/comments.reviewstep)" = 2 ]
	git show-ref --verify --quiet refs/review-edits/feature/comments/1
	reply_equals_status
	run --separate-stderr git review prev --porcelain
	[ "$status" -eq 0 ]
	grep -Fx 'private edit' sample.txt
	reply_equals_status
}

@test "a boundary returns unchanged state and a typed notice" {
	comments_start walk >/dev/null
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review prev --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[[ "$output" == *"$(printf 'navigation\tunchanged\nnotice\talready at the first entry')" ]]
	reply_equals_status
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "the last entry and commit emit state first and an unchanged notice" {
	for layout in walk step; do
		comments_start "$layout" >/dev/null
		if [ "$layout" = walk ]; then key=reviewwalkstep; count=reviewwalkcount; noun=entries
		else key=reviewstep; count=reviewcount; noun=commits; fi
		total=$(git config "branch.review/feature/comments.$count")
		while [ "$(git config "branch.review/feature/comments.$key")" -lt "$total" ]; do git review next >/dev/null; done
		run --separate-stderr git review next --porcelain
		[ "$status" -eq 0 ]
		[ "$stderr" = '' ]
		[[ "${lines[0]}" == "$(printf 'state\t')"* ]]
		[[ "$output" == *"$(printf 'navigation\tunchanged\nnotice\tno more %s' "$noun")" ]]
		[ "$(git config "branch.review/feature/comments.$key")" = "$total" ]
		reply_equals_status
		git review abort >/dev/null
	done
}

@test "stale navigation refuses before loading or repairing the reading order" {
	comments_start walk >/dev/null
	guard=$(git review status --porcelain | awk -F '\t' '$1=="guard" {print $2}')
	git config branch.review/feature/comments.reviewwalkstep 100
	comments_snapshot "$COMMENTS_TMP/before"
	run --separate-stderr git review --expect-state "$guard" next --porcelain
	[ "$status" -eq 4 ]
	[ "$stderr" = 'error: review state changed' ]
	[ "$output" = '' ]
	comments_snapshot "$COMMENTS_TMP/after"
	comments_assert_snapshot "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "guarded walk reply reads branch config range and walkthrough only once" {
	comments_start walk >/dev/null
	guard=$(git review status --porcelain | awk -F '\t' '$1=="guard" {print $2}')
	export NAV_REAL_GIT="$(command -v git)" NAV_CALLS="$COMMENTS_TMP/calls"
	mkdir "$COMMENTS_TMP/trace"
	cat >"$COMMENTS_TMP/trace/git" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$NAV_CALLS"
exec "$NAV_REAL_GIT" "$@"
EOF
	chmod +x "$COMMENTS_TMP/trace/git"
	export PATH="$COMMENTS_TMP/trace:$PATH"
	run --separate-stderr sh "$BATS_TEST_DIRNAME/../bin/git-review" --expect-state "$guard" next --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(awk '$1=="config" && $2=="--null" {n++} END {print n+0}' "$NAV_CALLS")" -eq 1 ]
	[ "$(awk '$1=="symbolic-ref" {n++} END {print n+0}' "$NAV_CALLS")" -eq 1 ]
	[ "$(awk '$1=="show" && /:.review\/walkthrough.md$/ {n++} END {print n+0}' "$NAV_CALLS")" -eq 1 ]
	[ "$(awk '$1=="-c" && $3=="diff" {n++} END {print n+0}' "$NAV_CALLS")" -eq 1 ]
}

@test "compare navigation preserves endpoints readonly and keys in its reply" {
	git switch --quiet feature/comments
	mkdir .review
	printf '# Walkthrough\n\n## 1. sample.txt\n\n> key\n\nFirst.\n\n## 2. other file.txt\n\n> key\n\nSecond.\n' >.review/walkthrough.md
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough
	git switch --quiet main
	git review compare --keys main feature/comments >/dev/null
	run --separate-stderr git review next --porcelain
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[[ "$output" == *"$(printf 'readonly\ncomparison\t')"* ]]
	[[ "$output" == *"$(printf '\nkeys\n')"* ]]
	reply_equals_status
}

@test "a failed cursor write emits no successful reply and leaves code and cursor intact" {
	comments_start walk >/dev/null
	git diff --binary HEAD >"$COMMENTS_TMP/before"
	: >"$(git rev-parse --git-dir)/config.lock"
	run --separate-stderr git review next --porcelain
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"could not lock config file"* ]]
	[ "$output" = '' ]
	[ "$(git config branch.review/feature/comments.reviewwalkstep)" = 1 ]
	git diff --binary HEAD >"$COMMENTS_TMP/after"
	cmp "$COMMENTS_TMP/before" "$COMMENTS_TMP/after"
}

@test "draft recovery is reflected in the reply metadata guard and draft path" {
	git switch --quiet feature/comments
	mkdir .review
	printf '# Walkthrough\n\n## 1. sample.txt\n> key\n\nFirst.\n\n## 2. other file.txt\n> key\n\nSecond.\n' >.review/walkthrough.md
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough
	git switch --quiet main
	git review start --offline --keys feature/comments >/dev/null
	git review next >/dev/null
	guard=$(git review status --porcelain | awk -F '\t' '$1=="guard" {print $2}')
	head_before=$(git rev-parse HEAD)
	draft="$(git rev-parse --git-dir)/review-walkthrough/feature/comments.md"
	mkdir -p "$(dirname "$draft")"
	printf '# Walkthrough\n\n## 1. sample.txt\n> key\n\nOnly this file now.\n' >"$draft"
	run --separate-stderr git review --expect-state "$guard" next --porcelain
	[ "$status" -eq 0 ]
	[[ "$stderr" == *"the cursor was at 2 and moved to 1"* ]]
	[ "$(git config branch.review/feature/comments.reviewwalkstep)" = 1 ]
	[ "$(git config branch.review/feature/comments.reviewwalkcount)" = 1 ]
	[ "$(git rev-parse HEAD)" = "$head_before" ]
	[[ "$output" == *"$(printf '\ndraft\t')"* ]]
	reply_equals_status
}

@test "an unavailable snapshot refuses a reply mutation before writing the cursor" {
	comments_start walk >/dev/null
	export NAV_REAL_GIT="$(command -v git)"
	mkdir "$COMMENTS_TMP/fault"
	cat >"$COMMENTS_TMP/fault/git" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = config ] && [ "${2:-}" = --null ]; then
	echo 'error: injected config read failure' >&2
	exit 128
fi
exec "$NAV_REAL_GIT" "$@"
EOF
	chmod +x "$COMMENTS_TMP/fault/git"
	export PATH="$COMMENTS_TMP/fault:$PATH"
	run --separate-stderr sh "$BATS_TEST_DIRNAME/../bin/git-review" next --porcelain
	[ "$status" -eq 1 ]
	[ "$output" = '' ]
	[[ "$stderr" == *"error: could not read review metadata" ]]
	[ "$(git config branch.review/feature/comments.reviewwalkstep)" = 1 ]
}
