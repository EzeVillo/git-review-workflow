#!/usr/bin/env bats

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

@test "start preserves global configuration scoped to each submodule" {
	mirror="$TMP/mirror"
	git clone -q --bare "$CHILD" "$mirror"
	global_fragment="$TMP/submodule-global"
	child_gitdir=$(git -C "$MODULE" rev-parse --absolute-git-dir)
	git config --file "$global_fragment" "url.$mirror.insteadOf" "$TMP/unavailable"
	git config --global "includeIf.gitdir:$child_gitdir.path" "$global_fragment"
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
		[[ "$stderr" == *'Errors during submodule fetch:'* ]]
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
