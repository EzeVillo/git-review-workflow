#!/usr/bin/env bats
load helpers/comments
setup_file() { bats_require_minimum_version 1.13.0; }
setup() { comments_setup; }
teardown() { comments_teardown; }

check_finish_delivery() {
	run --separate-stderr comments_start "$1"
	[ "$status" -eq 0 ]
	local tip
	tip=$(git config branch.review/feature/comments.reviewtip)
	run --separate-stderr git review comments add --document local --text 'Private observation stays private.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'Shared question goes to the output.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/local"
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/shared"
	if [ "$2" = code ]; then printf 'reviewer correction\n' >>sample.txt; fi
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = review-fixes/feature/comments ]
	[ "$(git rev-parse HEAD)" = "$tip" ]
	cmp "$COMMENTS_TMP/shared" .review/comments.md
	[ "$(git ls-files -- .review/comments.md)" = .review/comments.md ]
	git show :.review/comments.md >"$COMMENTS_TMP/staged-shared"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_TMP/staged-shared"
	if [ "$2" = code ]; then
		[ "$(git diff --cached --name-only)" = $'.review/comments.md\nsample.txt' ]
		[ "$(tail -n 1 sample.txt)" = 'reviewer correction' ]
	else
		[ "$(git diff --cached --name-only)" = .review/comments.md ]
	fi
	comments_refresh_paths
	cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
	run --separate-stderr git review clean --keep-fixes feature/comments
	[ "$status" -eq 0 ]
	comments_refresh_paths
	cmp "$COMMENTS_TMP/local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/shared" "$COMMENTS_SHARED"
}

@test "comments whole finish delivers Shared with no code correction commit" { check_finish_delivery whole prose; }
@test "comments whole finish stages Shared together with code corrections" { check_finish_delivery whole code; }
@test "comments walk finish delivers Shared with no code correction commit" { check_finish_delivery walk prose; }
@test "comments walk finish stages Shared together with code corrections" { check_finish_delivery walk code; }
@test "comments step finish delivers Shared with no code correction commit" { check_finish_delivery step prose; }
@test "comments step finish stages Shared together with code corrections" { check_finish_delivery step code; }

@test "isolated workspace stages Shared and code while Local stays with the active review" {
	comments_start whole
	git review comments add --document local --text 'Private observation.'
	git review comments add --document shared --text 'Shared observation.'
	comments_refresh_paths
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/expected-shared"
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/expected-local"
	printf 'reviewer correction\n' >>sample.txt
	before=$(git write-tree)
	output_dir="$COMMENTS_TMP/output"

	run --separate-stderr git review workspace finish --with-shared "$output_dir"
	[ "$status" -eq 0 ]
	[ "$(git -C "$output_dir" diff --cached --name-only)" = $'.review/comments.md\nsample.txt' ]
	git -C "$output_dir" show :.review/comments.md >"$COMMENTS_TMP/staged-shared"
	cmp "$COMMENTS_TMP/expected-shared" "$COMMENTS_TMP/staged-shared"
	cmp "$COMMENTS_TMP/expected-shared" "$output_dir/.review/comments.md"
	grep -Fx 'reviewer correction' "$output_dir/sample.txt"
	[ ! -e "$output_dir/.git/review-comments" ]
	[ ! -e .review/comments.md ]
	[ "$(git symbolic-ref --short HEAD)" = review/feature/comments ]
	[ "$(git write-tree)" = "$before" ]
	cmp "$COMMENTS_TMP/expected-local" "$COMMENTS_LOCAL"
	cmp "$COMMENTS_TMP/expected-shared" "$COMMENTS_SHARED"
}

@test "isolated workspace preserves the frozen Shared patch after a code conflict" {
	git switch -q feature/comments
	printf 'first\nauthor final\nthird\n' >sample.txt
	git commit -qam 'change the same line again'
	tip=$(git rev-parse HEAD)
	git switch -q main
	comments_start step
	printf 'first\nreviewer correction\nthird\n' >sample.txt
	git review comments add --document shared --text 'Shared at export time.'
	comments_refresh_paths
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/expected-shared"
	git review next
	checkout="$COMMENTS_TMP/second"
	git review workspace checkout "$checkout"
	printf 'independent correction\n' >>"$checkout/other file.txt"
	conflicted="$COMMENTS_TMP/conflicted"

	run --separate-stderr git review workspace finish --with-shared "$conflicted"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'resolve and stage the conflict'* ]]
	[ -n "$(git -C "$conflicted" ls-files --unmerged -- sample.txt)" ]
	[ ! -e "$conflicted/.review/comments.md" ]
	printf 'first\nresolved correction\nthird\n' >"$conflicted/sample.txt"
	git -C "$conflicted" add sample.txt
	git review comments add --document shared --text 'Added after export.'

	output_dir="$COMMENTS_TMP/output"
	run --separate-stderr git -C "$conflicted" review workspace resume "$output_dir"
	[ "$status" -eq 0 ]
	[ "$(git -C "$output_dir" rev-parse HEAD)" = "$tip" ]
	git -C "$output_dir" show :.review/comments.md >"$COMMENTS_TMP/staged-shared"
	cmp "$COMMENTS_TMP/expected-shared" "$COMMENTS_TMP/staged-shared"
	grep -Fx 'independent correction' "$output_dir/other file.txt"
	grep -Fx 'resolved correction' "$output_dir/sample.txt"
	grep -Fx 'reviewer correction' sample.txt
	grep -Fx 'Added after export.' "$COMMENTS_SHARED"
}

@test "managed isolated finish closes and undo reopens without touching either checkout" {
	comments_start whole
	git review comments add --document local --text 'Keep this private.'
	git review comments add --document shared --text 'Include in the output.'
	comments_refresh_paths
	prepared=$COMMENTS_SHARED
	cp "$prepared" "$COMMENTS_TMP/expected-shared"
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/expected-local"
	result_pointer="$(git rev-parse --absolute-git-dir)/review-comments/results/$COMMENTS_CONTEXT/current"
	printf 'reviewer correction\n' >>sample.txt
	index=$(git write-tree)
	head=$(git rev-parse HEAD)
	output_dir="$COMMENTS_TMP/output"

	run --separate-stderr git review finish --workspace "$output_dir"
	[ "$status" -eq 0 ]
	output_path=$(git -C "$output_dir" rev-parse --show-toplevel)
	[ "$output" = "$output_path" ]
	[ "$(git config branch.review/feature/comments.reviewworkspacefinish)" = "$output_path" ]
	[ "$(git write-tree)" = "$index" ]
	[ "$(git rev-parse HEAD)" = "$head" ]
	[ "$(git symbolic-ref --short HEAD)" = review/feature/comments ]
	git -C "$output_dir" show :.review/comments.md >"$COMMENTS_TMP/staged-shared"
	cmp "$COMMENTS_TMP/expected-shared" "$COMMENTS_TMP/staged-shared"
	result=$(cat "$result_pointer")
	cmp "$COMMENTS_TMP/expected-local" "${result_pointer%/*}/$result/local.md"
	[ ! -e "$output_dir/.git/review-comments" ]
	[ ! -e .review/comments.md ]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *$'finish-workspace\t'"$output_path"* ]]
	run --separate-stderr git review save
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: the review is closed; run git review finish --abort to reopen it' ]
	run --separate-stderr git review comments add --document shared --text 'Cannot add to a closed review.'
	[ "$status" -ne 0 ]
	cmp "$COMMENTS_TMP/expected-shared" "$prepared"
	printf 'outstanding output edit\n' >>"$output_dir/sample.txt"
	printf 'independent origin edit\n' >>sample.txt

	run git review finish --abort
	[ "$status" -eq 0 ]
	[ -z "$(git config branch.review/feature/comments.reviewworkspacefinish || true)" ]
	[ ! -e "$result_pointer" ]
	[ "$(git write-tree)" = "$index" ]
	[ "$(git rev-parse HEAD)" = "$head" ]
	grep -Fx 'outstanding output edit' "$output_dir/sample.txt"
	grep -Fx 'independent origin edit' sample.txt
	cmp "$COMMENTS_TMP/expected-shared" "$prepared"
	git review comments add --document shared --text 'Review reopened.'
	grep -Fx 'Review reopened.' "$prepared"
}

@test "managed isolated finish closes only after its conflict output was resumed" {
	git switch -q feature/comments
	printf 'first\nauthor final\nthird\n' >sample.txt
	git commit -qam 'change the same line again'
	git switch -q main
	comments_start step
	printf 'first\nreviewer correction\nthird\n' >sample.txt
	git review comments add --document shared --text 'Shared after conflict.'
	comments_refresh_paths
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/expected-shared"
	conflicted="$COMMENTS_TMP/conflicted"
	run --separate-stderr git review finish --workspace "$conflicted"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'resolve and stage the conflict'* ]]
	[ -z "$(git config branch.review/feature/comments.reviewworkspacefinish || true)" ]
	run --separate-stderr git review finish --workspace "$conflicted" --resume
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: resume the finish workspace before closing the review' ]
	printf 'first\nresolved correction\nthird\n' >"$conflicted/sample.txt"
	git -C "$conflicted" add sample.txt
	output_dir="$COMMENTS_TMP/output"
	git -C "$conflicted" review workspace resume "$output_dir"
	run --separate-stderr git review finish --workspace "$output_dir" --resume
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/feature/comments.reviewworkspacefinish)" = "$(git -C "$output_dir" rev-parse --show-toplevel)" ]
	git -C "$output_dir" show :.review/comments.md >"$COMMENTS_TMP/staged-shared"
	cmp "$COMMENTS_TMP/expected-shared" "$COMMENTS_TMP/staged-shared"
	grep -Fx 'resolved correction' "$output_dir/sample.txt"
	grep -Fx 'reviewer correction' sample.txt
}

@test "managed isolated finish refuses to adopt a code export from another operation" {
	comments_start whole
	git review comments add --document shared --text 'Stay in the review.'
	output_dir="$COMMENTS_TMP/export"
	git review workspace finish --with-shared "$output_dir"
	index=$(git -C "$output_dir" write-tree)

	run --separate-stderr git review finish --workspace "$output_dir" --resume
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: finish workspace belongs to another review' ]
	[ -z "$(git config branch.review/feature/comments.reviewworkspacefinish || true)" ]
	[ "$(git -C "$output_dir" write-tree)" = "$index" ]
}

@test "automatic isolated finish resumes from the review and accepts without replacing the checkout" {
	export XDG_STATE_HOME="$COMMENTS_TMP/state"
	git switch -q feature/comments
	printf 'first\nauthor final\nthird\n' >sample.txt
	git commit -qam 'change the same line again'
	git switch -q main
	comments_start step
	printf 'first\nreviewer correction\nthird\n' >sample.txt
	git review comments add --document shared --text 'Share after resolving.'
	before_index=$(git write-tree)
	before_head=$(git rev-parse HEAD)

	run --separate-stderr git review finish --workspace
	[ "$status" -eq 1 ]
	conflicted=$(git config branch.review/feature/comments.reviewworkspacepending)
	[ -n "$(git -C "$conflicted" ls-files --unmerged -- sample.txt)" ]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *$'finish-workspace-conflict\t'"$conflicted"*$'finish\tconflict\t0'* ]]
	printf 'first\nresolved correction\nthird\n' >"$conflicted/sample.txt"
	git -C "$conflicted" add sample.txt
	run git review finish --resume
	[ "$status" -eq 0 ]
	finished=$(git config branch.review/feature/comments.reviewworkspacefinish)
	[ "$finished" != "$conflicted" ]
	[ -z "$(git config branch.review/feature/comments.reviewworkspacepending || true)" ]
	grep -Fx 'resolved correction' "$finished/sample.txt"
	grep -Fx 'Share after resolving.' "$finished/.review/comments.md"
	run git review clean --keep-fixes feature/comments
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$before_head" ]
	[ "$(git write-tree)" = "$before_index" ]
	! git symbolic-ref --quiet HEAD
	! git show-ref --verify --quiet refs/heads/review/feature/comments
	grep -Fx 'reviewer correction' sample.txt
	grep -Fx 'resolved correction' "$finished/sample.txt"
}

@test "managed isolated finish preserves an empty Shared document" {
	comments_start whole
	git review comments init --document shared
	comments_refresh_paths
	: >"$COMMENTS_SHARED"
	output_dir="$COMMENTS_TMP/output"

	run --separate-stderr git review finish --workspace "$output_dir"
	[ "$status" -eq 0 ]
	[ -f "$output_dir/.review/comments.md" ]
	[ ! -s "$output_dir/.review/comments.md" ]
	[ "$(git -C "$output_dir" diff --cached --name-only)" = .review/comments.md ]
	[ -f "$COMMENTS_SHARED" ]
	[ ! -s "$COMMENTS_SHARED" ]
}

@test "comments newly chosen empty Shared is delivered as an existing zero byte file" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments init --document shared
	[ "$status" -eq 0 ]
	comments_refresh_paths
	: >"$COMMENTS_SHARED"
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	[ -f .review/comments.md ]
	[ ! -s .review/comments.md ]
	[ "$(git diff --cached --name-only)" = .review/comments.md ]
	comments_refresh_paths
	[ -f "$COMMENTS_SHARED" ]
	[ ! -s "$COMMENTS_SHARED" ]
}

@test "comments successive passes continue the portable Shared while preserving old references and Local" {
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document local --text 'First private observation.'
	[ "$status" -eq 0 ]
	run --separate-stderr git review comments add --document shared --text 'First Shared observation.'
	[ "$status" -eq 0 ]
	comments_refresh_paths
	local context=$COMMENTS_CONTEXT
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/first-shared"
	cp "$COMMENTS_LOCAL" "$COMMENTS_TMP/first-local"
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	git switch --quiet feature/comments
	git add .review/comments.md
	git commit --quiet -m 'author includes portable Shared'
	local next_tip
	next_tip=$(git rev-parse HEAD)
	run --separate-stderr git review clean feature/comments
	[ "$status" -eq 0 ]
	git switch --quiet main
	run --separate-stderr comments_start whole
	[ "$status" -eq 0 ]
	comments_refresh_paths
	[ "$COMMENTS_CONTEXT" = "$context" ]
	cmp "$COMMENTS_TMP/first-shared" "$COMMENTS_SHARED"
	cmp "$COMMENTS_TMP/first-local" "$COMMENTS_LOCAL"
	run --separate-stderr git review comments add --document shared --text 'Second Shared observation.'
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	local size
	size=$(wc -c <"$COMMENTS_TMP/first-shared")
	dd if="$COMMENTS_SHARED" of="$COMMENTS_TMP/preserved-prefix" bs=1 count="$size" 2>/dev/null
	cmp "$COMMENTS_TMP/first-shared" "$COMMENTS_TMP/preserved-prefix"
	cp "$COMMENTS_SHARED" "$COMMENTS_TMP/second-shared"
	run --separate-stderr git review finish
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$next_tip" ]
	[ "$(git diff --cached --name-only)" = .review/comments.md ]
	cmp "$COMMENTS_TMP/second-shared" .review/comments.md
	comments_refresh_paths
	cmp "$COMMENTS_TMP/first-local" "$COMMENTS_LOCAL"
}
