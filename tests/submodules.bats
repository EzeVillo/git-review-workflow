#!/usr/bin/env bats
load helpers/legacy-step

setup() {
	TMP=$(mktemp -d)
	# MSYS skips argv path conversion when a path contains literal shell syntax.
	if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -am "$TMP"); fi
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"
	git config --global user.email t@example.com
	git config --global user.name tester
	git config --global core.autocrlf false
	git config --global protocol.file.allow always

	CHILD="$TMP/child"
	SERVER="$TMP/server"
	CLIENT="$TMP/client"
	MODULE="deps/shared library's \$(touch grv-unquoted)"
	git init -q "$CHILD"
	git -C "$CHILD" symbolic-ref HEAD refs/heads/main
	printf 'old\n' >"$CHILD/version"
	git -C "$CHILD" add version
	git -C "$CHILD" commit -qm initial
	CHILD_BEFORE=$(git -C "$CHILD" rev-parse HEAD)

	git init -q "$SERVER"
	git -C "$SERVER" symbolic-ref HEAD refs/heads/main
	git -C "$SERVER" submodule add -q --name library "$CHILD" "$MODULE"
	git -C "$SERVER" commit -qm base
	git clone -q --recurse-submodules "$SERVER" "$CLIENT"
	cd "$CLIENT"
	git config reviewworkflow.base main
	git config submodule.recurse true
	BASE=$(git rev-parse HEAD)
	INDEX=$(git write-tree)
	FETCH_HEAD=$(git rev-parse --git-path FETCH_HEAD)
	printf 'keep this FETCH_HEAD\n' >"$FETCH_HEAD"
}

teardown() {
	rm -rf "$TMP"
}

advance_submodule() {
	git -C "$SERVER" switch -qc topic
	printf 'new\n' >"$CHILD/version"
	git -C "$CHILD" commit -qam update
	CHILD_AFTER=$(git -C "$CHILD" rev-parse HEAD)
	git -C "$SERVER/$MODULE" pull -q --ff-only origin main
	git -C "$SERVER" commit -qam 'update submodule'
	TARGET=$(git -C "$SERVER" rev-parse HEAD)
	[ -z "$(git -C "$MODULE" cat-file -t "$CHILD_AFTER" 2>/dev/null || true)" ]
}

assert_still_on_main() {
	[ "$(git symbolic-ref --short HEAD)" = main ]
	[ "$(git rev-parse HEAD)" = "$BASE" ]
	[ "$(git write-tree)" = "$INDEX" ]
	[ "$(git -C "$MODULE" rev-parse HEAD)" = "$CHILD_BEFORE" ]
	[ -z "$(git status --porcelain)" ]
}

assert_parent_fetch_unchanged() {
	[ ! -e grv-unquoted ]
	[ "$(cat "$FETCH_HEAD")" = 'keep this FETCH_HEAD' ]
	[ "$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes/origin/)" = "$TRACKING" ]
	[ "$(git reflog show --format='%H %gs' refs/remotes/origin/main)" = "$TRACKING_LOG" ]
}

remember_parent_fetch() {
	TRACKING=$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes/origin/)
	TRACKING_LOG=$(git reflog show --format='%H %gs' refs/remotes/origin/main)
}

assert_reviewed_gitlink() {
	[ "$(git symbolic-ref --short HEAD)" = "$1" ]
	[ "$(git rev-parse HEAD)" = "$BASE" ]
	[ "$(git diff --cached --name-only)" = "$MODULE" ]
	[ "$(git rev-parse ":$MODULE")" = "$CHILD_AFTER" ]
	[ "$(git -C "$MODULE" rev-parse HEAD)" = "$CHILD_AFTER" ]
	assert_parent_fetch_unchanged
}

@test "start fetches a submodule commit before opening the review" {
	advance_submodule
	remember_parent_fetch
	run git review start topic --no-walk
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/topic.reviewtip)" = "$TARGET" ]
	assert_reviewed_gitlink review/topic
}

# bats test_tags=legacy-git
@test "start and compare protect ignored files in recursive submodule checkouts" {
	bats_require_minimum_version 1.5.0
	git -C "$SERVER" switch -qc topic
	printf 'tracked by the PR\n' >"$CHILD/build-output"
	git -C "$CHILD" add build-output
	git -C "$CHILD" commit -qm 'track build output'
	git -C "$SERVER/$MODULE" pull -q --ff-only origin main
	git -C "$SERVER" commit -qam 'update submodule'
	exclude=$(git -C "$MODULE" rev-parse --absolute-git-dir)/info/exclude
	mkdir -p "$(dirname "$exclude")"
	printf 'build-output\n' >>"$exclude"
	printf 'private child data\n' >"$MODULE/build-output"

	run --separate-stderr git review start topic --no-walk
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"would overwrite an ignored working tree path: $MODULE/build-output"* ]]
	assert_still_on_main
	[ "$(cat "$MODULE/build-output")" = 'private child data' ]
	[ -z "$(git for-each-ref refs/heads/review/)" ]

	git fetch -q --no-recurse-submodules origin
	run --separate-stderr git review compare --no-walk main origin/topic
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"would overwrite an ignored working tree path: $MODULE/build-output"* ]]
	assert_still_on_main
	[ "$(cat "$MODULE/build-output")" = 'private child data' ]
	[ -z "$(git for-each-ref refs/heads/review/)" ]
	[ ! -e grv-unquoted ]

	mv "$MODULE/build-output" "$TMP/build-output"
	run git review start topic --no-walk
	[ "$status" -eq 0 ]
	[ "$(cat "$MODULE/build-output")" = 'tracked by the PR' ]
}

# bats test_tags=legacy-git
@test "start protects ignored contents when a file replaces a populated submodule" {
	bats_require_minimum_version 1.5.0
	git config submodule.recurse false
	git -C "$SERVER" switch -qc topic
	git -C "$SERVER" rm -qf -- "$MODULE"
	printf 'ordinary file\n' >"$SERVER/$MODULE"
	git -C "$SERVER" add -- "$MODULE"
	git -C "$SERVER" commit -qm 'replace submodule'
	exclude=$(git -C "$MODULE" rev-parse --absolute-git-dir)/info/exclude
	mkdir -p "$(dirname "$exclude")"
	printf 'build-output\n' >>"$exclude"
	printf 'private child data\n' >"$MODULE/build-output"

	run --separate-stderr git review start topic --no-walk
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"would replace a submodule containing ignored working tree files: $MODULE"* ]]
	assert_still_on_main
	[ "$(cat "$MODULE/build-output")" = 'private child data' ]
	[ -z "$(git for-each-ref refs/heads/review/)" ]
	[ ! -e grv-unquoted ]
}

# bats test_tags=legacy-git
@test "start protects only overlapping paths when a submodule becomes a directory" {
	bats_require_minimum_version 1.5.0
	git -C "$SERVER" switch -qc topic
	git -C "$SERVER" rm -qf -- "$MODULE"
	mkdir -p "$SERVER/$MODULE"
	printf 'tracked by the PR\n' >"$SERVER/$MODULE/build-output"
	git -C "$SERVER" add -- "$MODULE"
	git -C "$SERVER" commit -qm 'replace gitlink with an ordinary tree'
	exclude=$(git -C "$MODULE" rev-parse --absolute-git-dir)/info/exclude
	mkdir -p "$(dirname "$exclude")"
	printf 'build-output\nlocal-cache\n' >>"$exclude"
	printf 'private child data\n' >"$MODULE/build-output"

	run --separate-stderr git review start topic --no-walk
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"would overwrite an ignored working tree path: $MODULE/build-output"* ]]
	assert_still_on_main
	[ "$(cat "$MODULE/build-output")" = 'private child data' ]
	[ -z "$(git for-each-ref refs/heads/review/)" ]

	mv "$MODULE/build-output" "$MODULE/local-cache"
	run git review start topic --no-walk
	[ "$status" -eq 0 ]
	[ "$(cat "$MODULE/local-cache")" = 'private child data' ]
	[ "$(cat "$MODULE/build-output")" = 'tracked by the PR' ]
}

start_without_gitlink() {
	git config submodule.recurse false
	git -C "$SERVER" switch -qc topic
	git -C "$SERVER" rm -qf -- "$MODULE"
	git -C "$SERVER" commit -qm 'remove submodule'
	case "$1" in
	file)
		printf 'ordinary file\n' >"$SERVER/$MODULE"
		git -C "$SERVER" add -- "$MODULE"
		;;
	case)
		alias_path=$(printf '%s' "$MODULE" | LC_ALL=C tr '[:lower:]' '[:upper:]')
		mkdir -p "$SERVER/${alias_path%/*}"
		printf 'ordinary file\n' >"$SERVER/$alias_path"
		git -C "$SERVER" add -- "$alias_path"
		git config core.ignoreCase true
		;;
	directory)
		mkdir -p "$SERVER/$MODULE"
		printf 'parent owns this file\n' >"$SERVER/$MODULE/owned"
		git -C "$SERVER" add -- "$MODULE/owned"
		;;
	other)
		printf 'unrelated file\n' >"$SERVER/other"
		git -C "$SERVER" add other
		;;
	esac
	git -C "$SERVER" commit -qm 'next change'
	git review start "${2:---step}" topic
	[ -z "$(git ls-files -- "$MODULE")" ]
	[ -f "$MODULE/.git" ]
	exclude=$(git -C "$MODULE" rev-parse --absolute-git-dir)/info/exclude
	mkdir -p "$(dirname "$exclude")"
	printf 'build-output\n' >>"$exclude"
	printf 'private child data\n' >"$MODULE/build-output"
}

# bats test_tags=legacy-git
@test "next and finish protect a checkout retained after gitlink removal" {
	bats_require_minimum_version 1.5.0
	start_without_gitlink file
	index=$(git write-tree)
	head=$(git rev-parse HEAD)
	run --separate-stderr git review next
	[ "$status" -eq 0 ]
	[ "$stderr" = '' ]
	[ "$(git config branch.review/topic.reviewreadstep)" = 2 ]
	run --separate-stderr git review finish
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"would replace a submodule containing ignored working tree files: $MODULE"* ]]
	[ "$(git symbolic-ref --short HEAD)" = review/topic ]
	[ "$(git rev-parse HEAD)" = "$head" ]
	[ "$(git write-tree)" = "$index" ]
	[ "$(git config branch.review/topic.reviewstep)" = 1 ]
	[ -z "$(git for-each-ref refs/review-edits/topic/ refs/review-undo/topic/)" ]
	[ "$(cat "$MODULE/build-output")" = 'private child data' ]
	mv "$MODULE" "${MODULE}-held"
	run legacy_review_step next
	[ "$status" -eq 0 ]
	[ "$(cat "$MODULE")" = 'ordinary file' ]
	[ "$(cat "${MODULE}-held/build-output")" = 'private child data' ]
}

# bats test_tags=legacy-git
@test "checkout guards protect a nested repository across case aliases" {
	bats_require_minimum_version 1.5.0
	start_without_gitlink case
	index=$(git write-tree)
	run --separate-stderr legacy_review_step next
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"would replace a submodule containing ignored working tree files: $MODULE"* ]]
	[ "$(git config branch.review/topic.reviewstep)" = 1 ]
	[ "$(git write-tree)" = "$index" ]
	[ "$(cat "$MODULE/build-output")" = 'private child data' ]
	[ -z "$(git for-each-ref refs/review-edits/topic/)" ]
}

# bats test_tags=legacy-git
@test "preview leaves the retained checkout outside the review snapshot" {
	start_without_gitlink other --no-walk
	printf 'reviewer correction\n' >correction
	index=$(git write-tree)
	run git review preview --stat
	[ "$status" -eq 0 ]
	[[ "$output" == *correction* ]]
	[[ "$output" != *'shared library'* ]]
	[ "$(git write-tree)" = "$index" ]
	[ "$(cat "$MODULE/build-output")" = 'private child data' ]
}

# bats test_tags=legacy-git
@test "save continue and finish do not stage a retained checkout" {
	printf 'original text\n' >"$SERVER/correction"
	git -C "$SERVER" add correction
	git -C "$SERVER" commit -qm 'track the correction file'
	git pull -q --ff-only origin main
	start_without_gitlink other
	printf 'reviewer correction\n' >correction
	run git review save
	[ "$status" -eq 0 ]
	[ "$(git diff-tree --no-commit-id --name-only -r 'refs/review-saved-edits/topic/1^' 'refs/review-saved-edits/topic/1')" = correction ]
	run git review continue topic
	[ "$status" -eq 0 ]
	run legacy_review_step next
	[ "$status" -eq 0 ]
	[ -z "$(git ls-files -- "$MODULE")" ]
	[ "$(cat "$MODULE/build-output")" = 'private child data' ]
	run git review finish
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = review-fixes/topic ]
	[ "$(git diff --cached --name-only)" = correction ]
	[ "$(cat "$MODULE/build-output")" = 'private child data' ]
}

# bats test_tags=legacy-git
@test "forced recursive checkout preserves changes in a removed submodule" {
	bats_require_minimum_version 1.5.0
	git -C "$SERVER" switch -qc topic
	printf 'first step\n' >"$SERVER/other"
	git -C "$SERVER" add other
	git -C "$SERVER" commit -qm 'first change'
	git -C "$SERVER" rm -qf -- "$MODULE"
	git -C "$SERVER" commit -qm 'remove submodule'
	git review start --step topic
	index=$(git write-tree)
	printf 'private tracked edit\n' >"$MODULE/version"
	git -C "$MODULE" add version

	run --separate-stderr legacy_review_step next
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"would discard local changes in a nested Git working tree: $MODULE"* ]]
	[ "$(git config branch.review/topic.reviewstep)" = 1 ]
	[ "$(git write-tree)" = "$index" ]
	[ -z "$(git for-each-ref refs/review-edits/topic/)" ]
	[ "$(cat "$MODULE/version")" = 'private tracked edit' ]
	[ "$(git -C "$MODULE" show :version)" = 'private tracked edit' ]
}

# bats test_tags=legacy-git
@test "capture updates parent paths beside files owned by a retained checkout" {
	start_without_gitlink directory
	run legacy_review_step next
	[ "$status" -eq 0 ]
	[ -f "$MODULE/.git" ]
	printf 'reviewer correction\n' >"$MODULE/owned"
	printf 'private untracked sibling\n' >"$MODULE/private"
	run git review finish
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = review-fixes/topic ]
	[ "$(git diff --cached --name-only)" = "$MODULE/owned" ]
	[ "$(cat "$MODULE/private")" = 'private untracked sibling' ]
	[ "$(cat "$MODULE/build-output")" = 'private child data' ]
}

start_vendored_module() {
	git config submodule.recurse false
	git -C "$SERVER" switch -qc topic
	git -C "$SERVER" rm -qf -- "$MODULE"
	git -C "$SERVER" commit -qm 'remove gitlink'
	mkdir -p "$SERVER/$MODULE"
	printf 'vendored version\n' >"$SERVER/$MODULE/version"
	printf 'vendored settings\n' >"$SERVER/$MODULE/settings"
	git -C "$SERVER" add -- "$MODULE"
	git -C "$SERVER" commit -qm 'vendor ordinary files'
	if [ "${1:-}" = replace ]; then
		git -C "$SERVER" rm -qr -- "$MODULE"
		mkdir -p "$SERVER/${MODULE%/*}"
		printf 'ordinary replacement\n' >"$SERVER/$MODULE"
	else
		printf 'updated version\n' >"$SERVER/$MODULE/version"
		printf 'new settings\n' >"$SERVER/$MODULE/settings"
		printf 'new parent file\n' >"$SERVER/$MODULE/private"
	fi
	git -C "$SERVER" add -- "$MODULE"
	git -C "$SERVER" commit -qm 'update vendored files'
	git review start --step topic
	legacy_review_step next
	[ "$(git config branch.review/topic.reviewstep)" = 2 ]
	[ -f "$MODULE/.git" ]
	[ "$(git show ":$MODULE/version")" = 'vendored version' ]
	[ "$(git -C "$MODULE" show :version)" = old ]
}

# bats test_tags=legacy-git
@test "in-place checkout keeps parent edits to files also tracked by a retained checkout" {
	start_vendored_module
	printf 'reviewer version\n' >"$MODULE/version"
	run legacy_review_step next
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/topic.reviewstep)" = 3 ]
	[ "$(cat "$MODULE/version")" = 'updated version' ]
	[ "$(git show "refs/review-edits/topic/2:$MODULE/version")" = 'reviewer version' ]
	run legacy_review_step prev
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/topic.reviewstep)" = 2 ]
	[ "$(cat "$MODULE/version")" = 'reviewer version' ]
	[ "$(git show ":$MODULE/version")" = 'vendored version' ]
	[ "$(git -C "$MODULE" write-tree)" = "$(git -C "$MODULE" rev-parse 'HEAD^{tree}')" ]
}

# bats test_tags=legacy-git
@test "finish and undo recognize parent files also ignored or tracked by a retained checkout" {
	start_vendored_module
	exclude=$(git -C "$MODULE" rev-parse --absolute-git-dir)/info/exclude
	mkdir -p "$(dirname "$exclude")"
	printf '/settings\n/cache\n' >>"$exclude"
	printf 'keep child cache\n' >"$MODULE/cache"
	git -C "$MODULE" check-ignore -q settings
	git -C "$MODULE" check-ignore -q cache
	parent_index=$(git write-tree)
	parent_head=$(git rev-parse HEAD)

	run git review finish
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = review-fixes/topic ]
	[ "$(cat "$MODULE/version")" = 'updated version' ]
	[ "$(cat "$MODULE/settings")" = 'new settings' ]
	run git review finish --abort
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = review/topic ]
	[ "$(git rev-parse HEAD)" = "$parent_head" ]
	[ "$(git write-tree)" = "$parent_index" ]
	[ "$(git config branch.review/topic.reviewstep)" = 2 ]
	[ "$(cat "$MODULE/version")" = 'vendored version' ]
	[ "$(cat "$MODULE/settings")" = 'vendored settings' ]
	[ "$(cat "$MODULE/cache")" = 'keep child cache' ]
	[ -z "$(git for-each-ref refs/review-undo/topic/)" ]
}

# bats test_tags=legacy-git
@test "parent ownership still protects the child index and child only paths" {
	bats_require_minimum_version 1.5.0
	start_vendored_module
	parent_index=$(git write-tree)
	parent_head=$(git rev-parse HEAD)
	printf 'child staged version\n' >"$MODULE/version"
	git -C "$MODULE" add version
	printf 'vendored version\n' >"$MODULE/version"
	run --separate-stderr legacy_review_step next
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"would overwrite a local path in a nested Git working tree: $MODULE/version"* ]]
	[ "$(git -C "$MODULE" show :version)" = 'child staged version' ]
	[ "$(cat "$MODULE/version")" = 'vendored version' ]
	git -C "$MODULE" reset -q HEAD -- version

	printf 'child private file\n' >"$MODULE/private"
	run --separate-stderr git review finish
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"would overwrite a local path in a nested Git working tree: $MODULE/private"* ]]
	[ "$(cat "$MODULE/private")" = 'child private file' ]
	[ "$(git rev-parse HEAD)" = "$parent_head" ]
	[ "$(git write-tree)" = "$parent_index" ]
	[ "$(git config branch.review/topic.reviewstep)" = 2 ]
	[ -z "$(git for-each-ref refs/review-edits/topic/ refs/review-undo/topic/)" ]
}

# bats test_tags=legacy-git
@test "replacing a retained directory still protects files owned only by the child" {
	bats_require_minimum_version 1.5.0
	start_vendored_module replace
	child_gitdir=$(git -C "$MODULE" rev-parse --absolute-git-dir)
	mkdir -p "$child_gitdir/info"
	printf '/cache\n' >>"$child_gitdir/info/exclude"
	printf 'keep child cache\n' >"$MODULE/cache"
	index=$(git write-tree)

	run --separate-stderr legacy_review_step next
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"would replace a submodule containing ignored working tree files: $MODULE"* ]]
	[ "$(git write-tree)" = "$index" ]
	[ "$(git config branch.review/topic.reviewstep)" = 2 ]
	[ "$(cat "$MODULE/cache")" = 'keep child cache' ]

	mv "$MODULE/cache" "$TMP/saved-cache"
	run legacy_review_step next
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/topic.reviewstep)" = 3 ]
	[ "$(cat "$MODULE")" = 'ordinary replacement' ]
	[ "$(git --git-dir="$child_gitdir" --work-tree="$TMP" show :version)" = old ]
}

# bats test_tags=legacy-git
@test "save and continue hand ordinary paths back to a retained submodule" {
	start_vendored_module
	printf 'child cache\n' >"$MODULE/cache"
	child_exclude=$(git -C "$MODULE" rev-parse --absolute-git-dir)/info/exclude
	mkdir -p "$(dirname "$child_exclude")"
	printf '/cache\n' >>"$child_exclude"
	# Model an edit with the same size and timestamp as the cached stat entry.
	git config core.trustctime false
	git update-index --refresh
	touch -r "$MODULE/version" "$TMP/file-time"
	printf 'reviewer version\n' >"$MODULE/version"
	touch -r "$TMP/file-time" "$MODULE/version" "$(git rev-parse --git-path index)"
	[ "$(git diff --name-only)" = "$MODULE/version" ]

	run git review save
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = main ]
	[ "$(cat "$MODULE/version")" = old ]
	[ "$(git -C "$MODULE" show :version)" = old ]
	[ ! -e "$MODULE/settings" ]
	[ "$(cat "$MODULE/cache")" = 'child cache' ]
	[ -z "$(git status --porcelain)" ]

	run git review continue topic
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = review/topic ]
	[ "$(git config branch.review/topic.reviewstep)" = 2 ]
	[ "$(cat "$MODULE/version")" = 'reviewer version' ]
	[ "$(git show ":$MODULE/version")" = 'vendored version' ]
	[ "$(cat "$MODULE/cache")" = 'child cache' ]
}

# bats test_tags=legacy-git
@test "a failed checkout keeps the submodule files and the saved correction" {
	start_vendored_module
	printf 'saved reviewer version\n' >"$MODULE/version"
	run git review save
	[ "$status" -eq 0 ]
	saved=$(git rev-parse refs/review-saved-edits/topic/2)
	hook=$(git rev-parse --git-path hooks/post-checkout)
	mkdir -p "$(dirname "$hook")"
	cat >"$hook" <<'EOF'
#!/bin/sh
[ "$(git symbolic-ref --quiet --short HEAD)" != review/topic ]
EOF
	chmod +x "$hook"

	run git review continue topic
	[ "$status" -eq 1 ]
	[[ "$output" == *'could not switch to review/topic'* ]]
	[ "$(git symbolic-ref --short HEAD)" = main ]
	[ "$(cat "$MODULE/version")" = old ]
	[ -z "$(git status --porcelain)" ]
	[ "$(git rev-parse refs/review-saved-edits/topic/2)" = "$saved" ]
	[ "$(git show "$saved:$MODULE/version")" = 'saved reviewer version' ]
	[ -z "$(git for-each-ref refs/heads/review/)" ]
}

assert_open_child_write_is_retained() {
	hold_temp=$1
	start_vendored_module
	run git review save
	[ "$status" -eq 0 ]
	hook=$(git rev-parse --git-path hooks/post-checkout)
	mkdir -p "$(dirname "$hook")"
	cat >"$hook" <<'EOF'
#!/bin/sh
printf 'late child write\n' >&9
EOF
	chmod +x "$hook"

	run env TMPDIR="$hold_temp" sh -c 'exec 9>>"$1"; git review continue topic' sh "$MODULE/version"
	[ "$status" -eq 0 ]
	[[ "$output" == *"kept a recoverable copy of "*"/$MODULE/version at "* ]]
	[ "$(git symbolic-ref --short HEAD)" = review/topic ]
	[ "$(cat "$MODULE/version")" = 'vendored version' ]
	[ "$(git -C "$MODULE" show :version)" = old ]
	held=$(find "$MODULE" -type f -path '*/.git-review-hold.*/file')
	[ "$(cat "$held")" = "$(printf 'old\nlate child write')" ]
	[ -z "$(git ls-files --others --exclude-standard)" ]
	git -C "$MODULE" check-ignore -q "${held#"$MODULE"/}"
}

# bats test_tags=legacy-git
@test "checkout retains writes made through an already open submodule file" {
	if command -v cygpath >/dev/null 2>&1; then skip 'open-file rename needs Unix semantics'; fi
	mkdir "$TMP/hold-temp"
	assert_open_child_write_is_retained "$TMP/hold-temp"
}

@test "checkout retains open-file writes when TMPDIR uses a separate filesystem" {
	if [ ! -w /dev/shm ] || ! stat -c %d "$TMP" /dev/shm >/dev/null 2>&1; then
		skip 'requires a writable Linux tmpfs at /dev/shm'
	fi
	if [ "$(stat -c %d "$TMP")" = "$(stat -c %d /dev/shm)" ]; then skip 'TMP is already on the tmpfs'; fi
	assert_open_child_write_is_retained /dev/shm
}

start_deep_file_handoff() {
	local child_name=${1:-version} parent_name=${2:-version}
	git config submodule.recurse false
	mkdir -p "$CHILD/lib/deep"
	printf 'original child file\n' >"$CHILD/lib/deep/$child_name"
	printf 'original sibling\n' >"$CHILD/lib/deep/other"
	git -C "$CHILD" add lib
	git -C "$CHILD" commit -qm 'add deep child file'
	git -C "$SERVER/$MODULE" pull -q --ff-only origin main
	git -C "$SERVER" commit -qam 'update base gitlink'
	git pull -q --ff-only origin main
	git submodule update -q
	child_tree=$(git -C "$MODULE" write-tree)

	git -C "$SERVER" switch -qc topic
	git -C "$SERVER" rm -qf -- "$MODULE"
	git -C "$SERVER" commit -qm 'remove gitlink'
	mkdir -p "$SERVER/$MODULE/lib/deep"
	printf 'parent file\n' >"$SERVER/$MODULE/lib/deep/$parent_name"
	printf 'parent sibling\n' >"$SERVER/$MODULE/lib/deep/other"
	git -C "$SERVER" add -- "$MODULE/lib"
	git -C "$SERVER" commit -qm 'vendor deep file'
	git -C "$SERVER" rm -qr -- "$MODULE/lib"
	git -C "$SERVER" commit -qm 'remove parent file'
	git review start --step topic
}

# bats test_tags=legacy-git
@test "save and cancel restore a child file whose parent directories Git prunes" {
	start_deep_file_handoff
	run legacy_review_step next
	[ "$status" -eq 0 ]
	[ "$(cat "$MODULE/lib/deep/version")" = 'parent file' ]
	run git review save
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = main ]
	[ "$(cat "$MODULE/lib/deep/version")" = 'original child file' ]
	[ -z "$(git status --porcelain)" ]
	run git review continue topic
	[ "$status" -eq 0 ]
	[ "$(cat "$MODULE/lib/deep/version")" = 'parent file' ]
	run git review abort
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = main ]
	[ "$(cat "$MODULE/lib/deep/version")" = 'original child file' ]
	[ "$(git -C "$MODULE" write-tree)" = "$child_tree" ]
	[ -z "$(git status --porcelain)" ]
}

# bats test_tags=legacy-git
@test "in-place checkout transfers file ownership when neither tree has a gitlink" {
	start_deep_file_handoff
	run legacy_review_step next
	[ "$status" -eq 0 ]
	[ "$(git show ":$MODULE/lib/deep/version")" = 'parent file' ]
	run legacy_review_step next
	[ "$status" -eq 0 ]
	[ "$(cat "$MODULE/lib/deep/version")" = 'original child file' ]
	[ -z "$(git ls-files -- "$MODULE")" ]
	run legacy_review_step prev
	[ "$status" -eq 0 ]
	[ "$(cat "$MODULE/lib/deep/version")" = 'parent file' ]
	run legacy_review_step prev
	[ "$status" -eq 0 ]
	[ "$(cat "$MODULE/lib/deep/version")" = 'original child file' ]
	[ "$(git -C "$MODULE" write-tree)" = "$child_tree" ]
	[ -z "$(git ls-files -- "$MODULE")" ]
}

# bats test_tags=legacy-git
@test "finish and undo hand off the file when the PR drops it at its tip" {
	start_deep_file_handoff
	run legacy_review_step next
	[ "$status" -eq 0 ]
	before=$(git write-tree)
	run git review finish
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = review-fixes/topic ]
	[ "$(cat "$MODULE/lib/deep/version")" = 'original child file' ]
	[ -z "$(git ls-files -- "$MODULE")" ]
	run git review finish --abort
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = review/topic ]
	[ "$(git config branch.review/topic.reviewstep)" = 2 ]
	[ "$(git write-tree)" = "$before" ]
	[ "$(cat "$MODULE/lib/deep/version")" = 'parent file' ]
	[ "$(git -C "$MODULE" write-tree)" = "$child_tree" ]
}

# bats test_tags=legacy-git
@test "forced checkout protects child edits hidden by assume unchanged" {
	bats_require_minimum_version 1.5.0
	start_deep_file_handoff
	git -C "$MODULE" update-index --assume-unchanged lib/deep/version
	printf 'private child edit\n' >"$MODULE/lib/deep/version"
	git -C "$MODULE" diff --quiet
	before=$(git write-tree)
	run --separate-stderr legacy_review_step next
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'would overwrite a local path in a nested Git working tree:'*'/lib/deep/version'* ]]
	[ "$(git config branch.review/topic.reviewstep)" = 1 ]
	[ "$(git write-tree)" = "$before" ]
	[ "$(cat "$MODULE/lib/deep/version")" = 'private child edit' ]
	[ "$(git -C "$MODULE" write-tree)" = "$child_tree" ]
	[ -z "$(git for-each-ref refs/review-edits/topic/)" ]
	[ "$(cat "$MODULE/lib/deep/other")" = 'original sibling' ]
}

# bats test_tags=legacy-git
@test "handoff protects and restores child files across non-ASCII case aliases" {
	bats_require_minimum_version 1.5.0
	lower=$(printf '\303\251.txt')
	upper=$(printf '\303\211.txt')
	printf 'filesystem probe\n' >"$lower"
	if [ ! -f "$upper" ]; then skip 'filesystem distinguishes these two spellings'; fi
	rm -- "$lower"
	start_deep_file_handoff "$lower" "$upper"
	path=lib/deep/$lower
	git -C "$MODULE" update-index --assume-unchanged "$path"
	printf 'private child edit\n' >"$MODULE/$path"
	git -C "$MODULE" diff --quiet
	index=$(git write-tree)
	for locale in C C.UTF-8; do
		LC_ALL="$locale" run --separate-stderr legacy_review_step next
		[ "$status" -eq 1 ]
		[[ "$stderr" == *'would overwrite a local path in a nested Git working tree:'*"/$path" ]]
		[ "$(git config branch.review/topic.reviewstep)" = 1 ]
		[ "$(git write-tree)" = "$index" ]
		[ "$(cat "$MODULE/$path")" = 'private child edit' ]
		[ "$(git -C "$MODULE" write-tree)" = "$child_tree" ]
		[ -z "$(git for-each-ref refs/review-edits/topic/)" ]
	done
	git -C "$MODULE" update-index --no-assume-unchanged "$path"
	git -C "$MODULE" checkout -- "$path"
	LC_ALL=C run legacy_review_step next
	[ "$status" -eq 0 ]
	[ "$(cat "$MODULE/$path")" = 'parent file' ]
	LC_ALL=C run legacy_review_step next
	[ "$status" -eq 0 ]
	[ "$(cat "$MODULE/$path")" = 'original child file' ]
	[ "$(git -C "$MODULE" write-tree)" = "$child_tree" ]
	[ -z "$(git ls-files -- "$MODULE")" ]
}

@test "handoff protects child files through a Windows short file alias" {
	bats_require_minimum_version 1.5.0
	command -v cygpath >/dev/null 2>&1 || skip 'requires Windows short names'
	long="Private output document's data.txt"
	printf 'filesystem probe\n' >"$long"
	short=$(cygpath -asm -- "$long")
	short=${short##*/}
	if [[ "$short" != *~[0-9]* ]] || [ ! -f "$short" ]; then skip 'short names are disabled'; fi
	rm -- "$long"
	start_deep_file_handoff "$long" "$short"
	path=lib/deep/$long
	[ -f "$MODULE/lib/deep/$short" ] || skip 'the filesystem allocated a different short name'
	git -C "$MODULE" update-index --assume-unchanged "$path"
	printf 'private child edit\n' >"$MODULE/$path"
	git -C "$MODULE" diff --quiet
	index=$(git write-tree)
	run --separate-stderr legacy_review_step next
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'would overwrite a local path in a nested Git working tree:'*"/$path" ]]
	[ "$(git config branch.review/topic.reviewstep)" = 1 ]
	[ "$(git write-tree)" = "$index" ]
	[ "$(cat "$MODULE/$path")" = 'private child edit' ]
	[ "$(git -C "$MODULE" write-tree)" = "$child_tree" ]
	[ -z "$(git for-each-ref refs/review-edits/topic/)" ]
}

# bats test_tags=legacy-git
@test "returning ownership leaves a child skip-worktree path absent" {
	start_deep_file_handoff
	git -C "$MODULE" update-index --skip-worktree lib/deep/version
	rm "$MODULE/lib/deep/version"
	run legacy_review_step next
	[ "$status" -eq 0 ]
	[ "$(cat "$MODULE/lib/deep/version")" = 'parent file' ]
	run legacy_review_step next
	[ "$status" -eq 0 ]
	[ ! -e "$MODULE/lib/deep/version" ]
	[ "$(git -C "$MODULE" ls-files -t lib/deep/version)" = 'S lib/deep/version' ]
	[ "$(git -C "$MODULE" write-tree)" = "$child_tree" ]
}

# bats test_tags=legacy-git
@test "a failing switch hook still returns the files released by the parent" {
	bats_require_minimum_version 1.5.0
	start_deep_file_handoff
	run legacy_review_step next
	[ "$status" -eq 0 ]
	hook=$(git rev-parse --git-path hooks/post-checkout)
	mkdir -p "$(dirname "$hook")"
	printf '#!/bin/sh\nexit 19\n' >"$hook"
	chmod +x "$hook"
	run --separate-stderr git review save
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'could not return to main'* ]]
	[ "$(git symbolic-ref --short HEAD)" = main ]
	[ "$(cat "$MODULE/lib/deep/version")" = 'original child file' ]
	[ "$(git -C "$MODULE" write-tree)" = "$child_tree" ]
	[ -z "$(git status --porcelain)" ]
	git show-ref --verify --quiet refs/heads/review/topic
	git show-ref --verify --quiet refs/heads/review-saved/topic
}

@test "a checkout hook can occupy a released path without being overwritten" {
	if command -v cygpath >/dev/null 2>&1; then skip 'needs a symlink enabled checkout'; fi
	start_deep_file_handoff
	run legacy_review_step next
	[ "$status" -eq 0 ]
	hook=$(git rev-parse --git-path hooks/post-checkout)
	mkdir -p "$(dirname "$hook")" "$TMP/outside"
	printf 'outside sentinel\n' >"$TMP/outside/version"
	cat >"$hook" <<'EOF'
#!/bin/sh
mkdir -p "$TEST_MODULE/lib" || exit 1
ln -s "$TEST_OUTSIDE" "$TEST_MODULE/lib/deep"
EOF
	chmod +x "$hook"
	run env TEST_MODULE="$MODULE" TEST_OUTSIDE="$TMP/outside" git review save
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = main ]
	[ -L "$MODULE/lib/deep" ]
	[ "$(cat "$TMP/outside/version")" = 'outside sentinel' ]
	[ "$(git -C "$MODULE" show :lib/deep/version)" = 'original child file' ]
	[ "$(git -C "$MODULE" write-tree)" = "$child_tree" ]
}

# bats test_tags=legacy-git
@test "a hook staging one child path does not suppress restoration of a sibling" {
	start_deep_file_handoff
	run legacy_review_step next
	[ "$status" -eq 0 ]
	hook=$(git rev-parse --git-path hooks/post-checkout)
	mkdir -p "$(dirname "$hook")"
	cat >"$hook" <<'EOF'
#!/bin/sh
mkdir -p "$TEST_MODULE/lib/deep" || exit 1
printf 'hook sibling\n' >"$TEST_MODULE/lib/deep/other" || exit 1
git -C "$TEST_MODULE" add lib/deep/other
EOF
	chmod +x "$hook"
	run env TEST_MODULE="$MODULE" git review save
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = main ]
	[ "$(cat "$MODULE/lib/deep/version")" = 'original child file' ]
	[ "$(git -C "$MODULE" show :lib/deep/version)" = 'original child file' ]
	[ "$(cat "$MODULE/lib/deep/other")" = 'hook sibling' ]
	[ "$(git -C "$MODULE" show :lib/deep/other)" = 'hook sibling' ]
}

# bats test_tags=legacy-git
@test "ordinary parent files can cross multiple retained checkout boundaries" {
	git config submodule.recurse false
	git -C "$SERVER" switch -qc topic
	git -C "$SERVER" rm -qf -- "$MODULE"
	git -C "$SERVER" commit -qm 'remove outer gitlink'
	mkdir -p "$SERVER/$MODULE/inner"
	printf 'vendored inner version\n' >"$SERVER/$MODULE/inner/version"
	git -C "$SERVER" add -- "$MODULE/inner/version"
	git -C "$SERVER" commit -qm 'vendor inner file'
	printf 'updated inner version\n' >"$SERVER/$MODULE/inner/version"
	git -C "$SERVER" commit -qam 'update inner file'
	git review start --step topic
	git clone -q --separate-git-dir "$TMP/inner-git" "$CHILD" "$MODULE/inner"
	printf 'inner cache\n' >"$MODULE/inner/cache"
	parent_exclude=$(git rev-parse --git-path info/exclude)
	child_exclude=$(git -C "$MODULE" rev-parse --absolute-git-dir)/info/exclude
	mkdir -p "$(dirname "$parent_exclude")" "$(dirname "$child_exclude")"
	printf '/%s/\n' "$MODULE" >>"$parent_exclude"
	printf '/inner/\n' >>"$child_exclude"
	git check-ignore -q "$MODULE/inner/cache"
	git -C "$MODULE" check-ignore -q inner/cache

	printf 'inner private version\n' >"$MODULE/inner/version"
	run legacy_review_step next
	[ "$status" -eq 1 ]
	[[ "$output" == *"would overwrite a local path in a nested Git working tree: $MODULE/inner/version"* ]]
	[ "$(git config branch.review/topic.reviewstep)" = 1 ]
	[ "$(cat "$MODULE/inner/version")" = 'inner private version' ]
	git -C "$MODULE/inner" checkout -- version
	run legacy_review_step next
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/topic.reviewstep)" = 2 ]
	[ "$(cat "$MODULE/inner/version")" = 'vendored inner version' ]
	run legacy_review_step next
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/topic.reviewstep)" = 3 ]
	[ "$(cat "$MODULE/inner/version")" = 'updated inner version' ]
	[ "$(cat "$MODULE/inner/cache")" = 'inner cache' ]
	[ "$(git -C "$MODULE/inner" show :version)" = old ]
	[ "$(git ls-files -- "$MODULE")" = "$MODULE/inner/version" ]
	run git review save
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = main ]
	[ "$(cat "$MODULE/inner/version")" = old ]
	run git review continue topic
	[ "$status" -eq 0 ]
	[ "$(git symbolic-ref --short HEAD)" = review/topic ]
	[ "$(git config branch.review/topic.reviewstep)" = 3 ]
	[ "$(cat "$MODULE/inner/version")" = 'updated inner version' ]
	[ "$(cat "$MODULE/inner/cache")" = 'inner cache' ]
}

@test "start preparation fetches submodule commits without checking them out" {
	git config fetch.recurseSubmodules on-demand
	advance_submodule
	remember_parent_fetch
	run git review start --prepare -- topic
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk '$1 == "start-prepared" {print $2}')
	[ -n "$token" ]
	git -C "$MODULE" cat-file -e "$CHILD_AFTER^{commit}"
	assert_still_on_main
	assert_parent_fetch_unchanged

	run git review start "--prepared=$token" --no-walk -- topic
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/topic.reviewtip)" = "$TARGET" ]
	assert_reviewed_gitlink review/topic
}

# bats test_tags=legacy-git
@test "remote compare fetches submodule commits without updating tracking refs" {
	git config fetch.recurseSubmodules on-demand
	advance_submodule
	remember_parent_fetch
	run git review compare --prepare --porcelain -- main fetch:origin:topic
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk '$1 == "comparison-prepared" {print $2}')
	[ -n "$token" ]
	git -C "$MODULE" cat-file -e "$CHILD_AFTER^{commit}"
	assert_still_on_main
	assert_parent_fetch_unchanged

	run git review compare "--prepared=$token" --no-walk -- main fetch:origin:topic
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/origin/topic.reviewreadonly)" = 1 ]
	[ "$(git config branch.review/origin/topic.reviewtip)" = "$TARGET" ]
	assert_reviewed_gitlink review/origin/topic
}

@test "offline start never fetches a missing submodule commit" {
	bats_require_minimum_version 1.5.0
	advance_submodule
	git fetch -q --no-recurse-submodules origin refs/heads/topic:refs/heads/topic
	run --separate-stderr git review start --offline --base main --no-walk topic
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'error: could not switch to review/topic'* ]]
	assert_still_on_main
	[ -z "$(git for-each-ref --format='%(refname)' refs/heads/review/topic)" ]
	[ -z "$(git -C "$MODULE" cat-file -t "$CHILD_AFTER" 2>/dev/null || true)" ]
}

@test "start honors fetch recursion disabled in Git config" {
	bats_require_minimum_version 1.5.0
	git config fetch.recurseSubmodules false
	advance_submodule
	remember_parent_fetch
	run --separate-stderr git review start topic --no-walk
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'error: could not switch to review/topic'* ]]
	assert_still_on_main
	assert_parent_fetch_unchanged
	[ -z "$(git -C "$MODULE" cat-file -t "$CHILD_AFTER" 2>/dev/null || true)" ]
}

@test "start fetches descendants of a nested initialized submodule" {
	grandchild="$TMP/grandchild"
	git init -q "$grandchild"
	git -C "$grandchild" symbolic-ref HEAD refs/heads/main
	printf 'old\n' >"$grandchild/version"
	git -C "$grandchild" add version
	git -C "$grandchild" commit -qm initial
	git -C "$CHILD" submodule add -q "$grandchild" nested
	git -C "$CHILD" commit -qm 'add nested submodule'
	git -C "$SERVER/$MODULE" pull -q --ff-only origin main
	git -C "$SERVER" commit -qam 'pin nested submodule'
	git pull -q --ff-only origin main
	git submodule update --init --recursive --quiet
	BASE=$(git rev-parse HEAD)
	CHILD_BEFORE=$(git -C "$MODULE" rev-parse HEAD)
	printf 'keep this FETCH_HEAD\n' >"$FETCH_HEAD"

	printf 'new\n' >"$grandchild/version"
	git -C "$grandchild" commit -qam advance
	grandchild_after=$(git -C "$grandchild" rev-parse HEAD)
	git -C "$CHILD/nested" pull -q --ff-only origin main
	advance_submodule
	remember_parent_fetch
	run git review start topic --no-walk
	[ "$status" -eq 0 ]
	assert_reviewed_gitlink review/topic
	[ "$(git -C "$MODULE/nested" rev-parse HEAD)" = "$grandchild_after" ]
}

@test "start fetches a submodule kept in Git after deinitialization" {
	oracle="$TMP/oracle"
	git clone -q --recurse-submodules "$SERVER" "$oracle"
	advance_submodule
	for repository in "$oracle" "$CLIENT"; do
		git -C "$repository" submodule deinit -q -- "$MODULE"
		git -C "$repository" config submodule.active "$MODULE"
		git -C "$repository" config fetch.recurseSubmodules on-demand
	done
	git -C "$oracle" fetch -q origin
	git --git-dir="$oracle/.git/modules/library" cat-file -e "$CHILD_AFTER^{commit}"
	remember_parent_fetch
	run git review start --prepare -- topic
	[ "$status" -eq 0 ]
	git --git-dir="$CLIENT/.git/modules/library" cat-file -e "$CHILD_AFTER^{commit}"
	[ ! -e "$MODULE/.git" ]
	assert_parent_fetch_unchanged
}

# bats test_tags=legacy-git
@test "start preserves global configuration scoped to each submodule" {
	mirror="$TMP/mirror"
	git clone -q --bare "$CHILD" "$mirror"
	global_fragment="$TMP/submodule-global"
	child_gitdir=$(git -C "$MODULE" rev-parse --absolute-git-dir)
	git config --file "$global_fragment" "url.$mirror.insteadOf" "$TMP/unavailable"
	git config --global "includeIf.gitdir:$child_gitdir.path" "$global_fragment"
	parent_fragment="$TMP/parent-global"
	git config --file "$parent_fragment" fetch.prune true
	git config --global "includeIf.gitdir:$(git rev-parse --absolute-git-dir).path" "$parent_fragment"
	git config --global color.ui auto
	advance_submodule
	git -C "$CHILD" push -q "$mirror" main
	# Only the submodule-specific include supplies this now-unavailable remote.
	git -C "$MODULE" config remote.origin.url "$TMP/unavailable"
	[ "$(git -C "$MODULE" ls-remote origin refs/heads/main | cut -f 1)" = "$CHILD_AFTER" ]
	remember_parent_fetch
	run git review start --prepare -- topic
	[ "$status" -eq 0 ]
	git -C "$MODULE" cat-file -e "$CHILD_AFTER^{commit}"
	assert_still_on_main
	assert_parent_fetch_unchanged
}

@test "start prepares submodules from a linked worktree" {
	git -c submodule.recurse=false worktree add -q -b linked "$TMP/linked" main
	cd "$TMP/linked"
	git submodule update --init --quiet
	FETCH_HEAD=$(git rev-parse --git-path FETCH_HEAD)
	printf 'keep this FETCH_HEAD\n' >"$FETCH_HEAD"
	advance_submodule
	remember_parent_fetch
	run git review start --prepare -- topic
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk '$1 == "start-prepared" {print $2}')
	[ -n "$token" ]
	git -C "$MODULE" cat-file -e "$CHILD_AFTER^{commit}"
	[ "$(git symbolic-ref --short HEAD)" = linked ]
	[ "$(git -C "$MODULE" rev-parse HEAD)" = "$CHILD_BEFORE" ]
	assert_parent_fetch_unchanged
	run git review start "--prepared=$token" --step -- topic
	[ "$status" -eq 0 ]
	assert_reviewed_gitlink review/topic
}

@test "start preserves conditional config for an external submodule gitdir with glob characters" {
	external="$TMP/external [child] repository"
	mv .git/modules/library "$external"
	native_worktree="$(git rev-parse --show-toplevel)/$MODULE"
	git -C "$TMP" --git-dir='external [child] repository' --work-tree="$native_worktree" config core.worktree "$native_worktree"
	native_external=$(git -C "$TMP" --git-dir='external [child] repository' rev-parse --absolute-git-dir)
	printf 'gitdir: %s\n' "$native_external" >"$MODULE/.git"
	git -C "$MODULE" switch -qc child-scope
	mirror="$TMP/mirror"
	git clone -q --bare "$CHILD" "$mirror"
	global_fragment="$TMP/submodule-global"
	git config --file "$global_fragment" "url.$mirror.insteadOf" "$TMP/unavailable"
	git config --global includeIf.onbranch:child-scope.path "$global_fragment"
	advance_submodule
	git -C "$CHILD" push -q "$mirror" main
	git -C "$MODULE" config remote.origin.url "$TMP/unavailable"
	[ "$(git -C "$MODULE" ls-remote origin refs/heads/main | cut -f 1)" = "$CHILD_AFTER" ]
	remember_parent_fetch
	run git review start --prepare -- topic
	[ "$status" -eq 0 ]
	git -C "$MODULE" cat-file -e "$CHILD_AFTER^{commit}"
	assert_still_on_main
	assert_parent_fetch_unchanged
}

# bats test_tags=legacy-git
@test "submodule fetch failure leaves no usable Start or Compare preparation" {
	bats_require_minimum_version 1.5.0
	advance_submodule
	git -C "$MODULE" config remote.origin.url "$TMP/unavailable"
	remember_parent_fetch
	for verb in start compare; do
		case "$verb" in
		start) set -- start --prepare -- topic ;;
		compare) set -- compare --prepare --porcelain -- main fetch:origin:topic ;;
		esac
		run --separate-stderr git review "$@"
		[ "$status" -eq 1 ]
		[[ "$stderr" == *"/unavailable' does not appear to be a git repository"* ]]
		[[ "$output" != *'-prepared'* ]]
		assert_still_on_main
		assert_parent_fetch_unchanged
		[ -z "$(git for-each-ref --format='%(refname)' "refs/worktree/review-$verb/pending/")" ]
		[ -z "$(git for-each-ref --format='%(refname)' refs/heads/review/)" ]
	done
}

@test "start prepares submodules alongside an index revision gitlink" {
	advance_submodule
	alternate="$TMP/alternate-index"
	cp "$(git rev-parse --git-path index)" "$alternate"
	GIT_INDEX_FILE="$alternate" git update-index --add --cacheinfo 160000,"$BASE",cutoff
	remember_parent_fetch
	mkdir nested
	cd nested
	run env GIT_INDEX_FILE=../../alternate-index git review start --prepare -- topic
	[ "$status" -eq 0 ]
	cd ..
	git -C "$MODULE" cat-file -e "$CHILD_AFTER^{commit}"
	assert_still_on_main
	assert_parent_fetch_unchanged
}

@test "start isolates its own hooks while honoring a submodule fetch guard" {
	bats_require_minimum_version 1.5.0
	hooks="$TMP/submodule-hooks"
	parent_hooks="$TMP/parent-hooks"
	mkdir "$hooks" "$parent_hooks"
	cat >"$hooks/reference-transaction" <<'EOF'
#!/bin/sh
if [ "$1" = prepared ]; then
	printf 'submodule fetch rejected\n' >&2
	exit 1
fi
EOF
	cat >"$parent_hooks/reference-transaction" <<'EOF'
#!/bin/sh
while read -r before after ref; do
	case "$ref" in
	refs/remotes/*|refs/worktree/review-start/fetched-*)
		printf 'parent hook must stay isolated\n' >&2
		exit 1
		;;
	esac
done
exit 0
EOF
	chmod +x "$hooks/reference-transaction" "$parent_hooks/reference-transaction"
	oracle="$TMP/oracle"
	git clone -q "$CHILD" "$oracle"
	git -C "$oracle" config core.hooksPath "$hooks"
	git -C "$MODULE" config core.hooksPath "$hooks"
	git config core.hooksPath "$parent_hooks"
	advance_submodule
	remember_parent_fetch
	run --separate-stderr git -C "$oracle" fetch -q origin
	[ "$status" -eq 128 ]
	[[ "$stderr" == *'submodule fetch rejected'* ]]

	run --separate-stderr git review start --prepare -- topic
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'submodule fetch rejected'* ]]
	[[ "$stderr" != *'parent hook must stay isolated'* ]]
	[[ "$output" != *'start-prepared'* ]]
	assert_still_on_main
	assert_parent_fetch_unchanged
	[ -z "$(git for-each-ref --format='%(refname)' refs/worktree/review-start/pending/)" ]
}

@test "start preserves its own and its submodules command options during recursive fetch" {
	advance_submodule
	mirror="$TMP/child-mirror.git"
	git clone -q --bare "$CHILD" "$mirror"
	parent_fragment="$TMP/parent-command.config"
	child_fragment="$TMP/child-command.config"
	parent_gitdir=$(git rev-parse --absolute-git-dir)
	child_gitdir=$(git -C "$MODULE" rev-parse --absolute-git-dir)
	hooks="$TMP/command-hooks"
	mkdir "$hooks"
	git config --file "$parent_fragment" audit.order parent
	git config --file "$child_fragment" audit.order child
	git config --file "$child_fragment" core.hooksPath "$hooks"
	git config --file "$child_fragment" "url.$mirror.insteadOf" "$TMP/unavailable"
	git -C "$MODULE" config remote.origin.url "$TMP/unavailable"
	config_git=(env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=audit.order GIT_CONFIG_VALUE_0=environment
		git -c audit.order=before
		-c "includeIf.gitdir:$parent_gitdir.path=$parent_fragment"
		-c "includeIf.gitdir:$child_gitdir.path=$child_fragment"
		-c audit.order=after)
	export REVIEW_CONFIG_EXPECTED="$TMP/expected-command"
	export REVIEW_CONFIG_ACTUAL="$TMP/actual-command"
	"${config_git[@]}" -C "$MODULE" config --show-scope --null --get-all audit.order >"$REVIEW_CONFIG_EXPECTED"
	cat >"$hooks/reference-transaction" <<'EOF'
#!/bin/sh
set -eu
if [ "$1" = prepared ]; then
	git config --show-scope --null --get-all audit.order >"$REVIEW_CONFIG_ACTUAL"
	cmp "$REVIEW_CONFIG_EXPECTED" "$REVIEW_CONFIG_ACTUAL"
fi
EOF
	chmod +x "$hooks/reference-transaction"
	remember_parent_fetch
	run "${config_git[@]}" review start --prepare -- topic
	[ "$status" -eq 0 ]
	[ -f "$REVIEW_CONFIG_ACTUAL" ]
	cmp "$REVIEW_CONFIG_EXPECTED" "$REVIEW_CONFIG_ACTUAL"
	git -C "$MODULE" cat-file -e "$CHILD_AFTER^{commit}"
	assert_still_on_main
	assert_parent_fetch_unchanged
}
