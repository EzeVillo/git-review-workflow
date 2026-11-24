#!/usr/bin/env bats

setup() {
	TMP=$(mktemp -d)
	if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -am "$TMP"); fi
	export HOME="$TMP/home"
	mkdir -p "$HOME" "$TMP/clients"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"
	git config --global user.email t@example.com
	git config --global user.name tester
	git config --global core.autocrlf false
	git config --global init.defaultBranch main
	ORIGIN="$TMP/origin.git"
	git init -q --bare "$ORIGIN"
	git init -q "$TMP/author"
	cd "$TMP/author"
	printf 'base\n' >base.txt
	git add .
	git commit -qm base
	git branch -M main
	BASE=$(git rev-parse HEAD)
	git remote add origin "$ORIGIN"
	git push -q origin main
	git switch -qc topic
	printf 'one\n' >one.txt
	git add .
	git commit -qm one
	FIRST=$(git rev-parse HEAD)
	git branch checkpoint
	printf 'two\n' >two.txt
	git add .
	git commit -qm two
	TIP=$(git rev-parse HEAD)
	git push -q origin topic checkpoint
	READER="$TMP/clients/reader"
	ORACLE="$TMP/clients/oracle"
	for repo in "$READER" "$ORACLE"; do
		git clone -q --branch main "$ORIGIN" "$repo"
		git -C "$repo" config reviewworkflow.base main
		git -C "$repo" config remote.origin.fetch '+refs/heads/main:refs/remotes/origin/main'
	done
	git push -q --force origin "$BASE:refs/heads/checkpoint"
	FRAGMENT="$TMP/fetch.config"
	git config --file "$FRAGMENT" --add remote.origin.fetch '+refs/heads/topic:refs/remotes/origin/topic'
	git config --file "$FRAGMENT" --add remote.origin.fetch '+refs/heads/checkpoint:refs/remotes/origin/checkpoint'
	# Git for Windows can expand a short TEMP path into its long spelling.
	client_gitdir=$(git -C "$READER" rev-parse --absolute-git-dir)
	CONDITION="includeIf.gitdir:${client_gitdir%/reader/.git}/**.path"
	cd "$READER"
}

teardown() {
	rm -rf "$TMP"
}

# The ordinary fetch in a separate clone is the oracle. Start must choose its
# endpoints and staged paths without changing the reader's refs or FETCH_HEAD.
assert_configured_start_matches_git() {
	"${CONFIG_GIT[@]}" -C "$ORACLE" fetch -q origin
	[ "$(git -C "$ORACLE" rev-parse origin/checkpoint)" = "$BASE" ]
	local refs logs expected token option selector entry
	refs=$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes/)
	logs=$(git reflog show --format='%H %gs' refs/remotes/origin/checkpoint)
	printf 'preserve FETCH_HEAD\n' >.git/FETCH_HEAD
	expected=$(git -C "$ORACLE" diff --name-only origin/checkpoint origin/topic)
	[ "$expected" = $'one.txt\ntwo.txt' ]
	for option in --from --base; do
		selector=origin/checkpoint
		if [ "$option" = --base ]; then selector=checkpoint; fi
		for entry in direct prepared; do
			local args=()
			if [ "$entry" = prepared ]; then
				run "${CONFIG_GIT[@]}" review start --prepare "$option" "$selector" -- topic
				[ "$status" -eq 0 ]
				token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
				[ -n "$token" ]
				args=("--prepared=$token")
			fi
			run "${CONFIG_GIT[@]}" review start ${args[@]+"${args[@]}"} "$option" "$selector" --no-walk -- topic
			[ "$status" -eq 0 ]
			[ "$(git rev-parse HEAD)" = "$BASE" ]
			[ "$(git config branch.review/topic.reviewtip)" = "$TIP" ]
			[ "$(git diff --cached --name-only)" = "$expected" ]
			[ "$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes/)" = "$refs" ]
			[ "$(git reflog show --format='%H %gs' refs/remotes/origin/checkpoint)" = "$logs" ]
			[ "$(cat .git/FETCH_HEAD)" = 'preserve FETCH_HEAD' ]
			git review abort >/dev/null
			if [ "$entry" = prepared ]; then git review start --release -- "$token"; fi
		done
	done
}

@test "start keeps command gitdir includes for direct and prepared ranges" {
	CONFIG_GIT=(git -c "$CONDITION=$FRAGMENT")
	assert_configured_start_matches_git
}

@test "start accepts an interleaved global conditional identity" {
	identity="$TMP/identity.config"
	git config --file "$identity" user.email work@example.com
	git config --global "$CONDITION" "$identity"
	git config --global fetch.prune false
	[ "$(git config user.email)" = work@example.com ]
	CONFIG_GIT=(git -c "include.path=$FRAGMENT")
	assert_configured_start_matches_git
}

@test "start replays trailing global conditional fetch options" {
	git config --global "$CONDITION" "$FRAGMENT"
	CONFIG_GIT=(git)
	assert_configured_start_matches_git
}

@test "start keeps nested conditional includes supplied at command scope" {
	outer="$TMP/outer.config"
	git config --file "$outer" "$CONDITION" fetch.config
	CONFIG_GIT=(git -c "include.path=$outer")
	assert_configured_start_matches_git
}

@test "start keeps conditional includes supplied through config count" {
	if ! env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=audit.probe GIT_CONFIG_VALUE_0=present git config --get audit.probe >/dev/null; then
		skip 'Git config count is unavailable'
	fi
	CONFIG_GIT=(env GIT_CONFIG_COUNT=1 "GIT_CONFIG_KEY_0=$CONDITION" "GIT_CONFIG_VALUE_0=$FRAGMENT" git)
	assert_configured_start_matches_git
}

@test "command conditional ancestry options choose the same revisions as Git" {
	git config --file "$FRAGMENT" core.useReplaceRefs false
	CONFIG_GIT=(git -c "$CONDITION=$FRAGMENT")
	for repo in "$READER" "$ORACLE"; do
		replacement=$(git -C "$repo" commit-tree "$TIP^{tree}" -p "$BASE" -m replacement)
		git -C "$repo" replace "$TIP" "$replacement"
		[ "$(git -C "$repo" rev-parse origin/topic^)" = "$BASE" ]
	done
	if [ "$(git -c core.useReplaceRefs=false -C "$ORACLE" rev-parse origin/topic^)" != "$FIRST" ]; then
		skip 'Git core.useReplaceRefs is unavailable'
	fi
	"${CONFIG_GIT[@]}" -C "$ORACLE" fetch -q origin
	cutoff=$("${CONFIG_GIT[@]}" -C "$ORACLE" rev-parse origin/topic^)
	[ "$cutoff" = "$FIRST" ]
	expected=$("${CONFIG_GIT[@]}" -C "$ORACLE" diff --name-only "$cutoff" origin/topic)
	[ "$expected" = two.txt ]
	for option in --base --from; do
		for entry in direct prepared; do
			args=()
			if [ "$entry" = prepared ]; then
				run "${CONFIG_GIT[@]}" review start --prepare "$option" origin/topic^ -- topic
				[ "$status" -eq 0 ]
				token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="start-prepared" {print $2}')
				[ -n "$token" ]
				args=("--prepared=$token")
			fi
			run "${CONFIG_GIT[@]}" review start ${args[@]+"${args[@]}"} "$option" origin/topic^ --no-walk -- topic
			[ "$status" -eq 0 ]
			[ "$(git rev-parse HEAD)" = "$cutoff" ]
			[ "$(git diff --cached --name-only)" = "$expected" ]
			"${CONFIG_GIT[@]}" review abort >/dev/null
			if [ "$entry" = prepared ]; then git review start --release -- "$token"; fi
		done
	done
}

make_config_probe() {
	export REVIEW_TEST_LIBRARY="$BATS_TEST_DIRNAME/../bin/git-review-lib.sh"
	export REVIEW_TEST_SCRIPT="$TMP/config-probe.sh"
	cat >"$REVIEW_TEST_SCRIPT" <<'EOF'
#!/bin/sh
set -eu
. "$REVIEW_TEST_LIBRARY"
view=$(mktemp -d)
trap 'rm -rf "$view"' 0
if [ "${REVIEW_TEST_LEGACY:-0}" = 1 ]; then
	# Exercise the path used by Git before GIT_CONFIG_GLOBAL was supported.
	git() {
		if [ "$*" = 'config --global --get reviewview.probe' ]; then return 1; fi
		command git "$@"
	}
fi
set --
if git config -h | grep -q -- --show-scope; then set -- --show-scope; fi
git config "$@" --null --get-regexp '^audit\.' >"$view/expected"
review_view_open "$view"
review_view_git config "$@" --null --get-regexp '^audit\.' >"$view/actual"
if ! cmp "$view/expected" "$view/actual"; then
	printf 'expected:\n'
	tr '\000' '\n' <"$view/expected"
	printf 'actual:\n'
	tr '\000' '\n' <"$view/actual"
	exit 1
fi
printf 'configuration and scopes match Git\n'
EOF
}

@test "temporary config keeps command order scopes empty values and exact bytes" {
	make_config_probe
	git config --global --add audit.order global
	git config --add audit.order local
	git config --file "$FRAGMENT" --add audit.order included
	git config --file "$FRAGMENT" audit.bytes $'line one\nline two\t"quoted" \\end\rñ'
	[ "$(git -c "$CONDITION=$FRAGMENT" config audit.bytes)" = "$(git config --file "$FRAGMENT" audit.bytes)" ]
	for legacy in 0 1; do
		run env REVIEW_TEST_LEGACY="$legacy" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=audit.order GIT_CONFIG_VALUE_0=environment \
			git -c audit.order=before -c "$CONDITION=$FRAGMENT" -c audit.order= -c audit.order=after -c audit.valueless \
			-c 'alias.config-probe=!sh "$REVIEW_TEST_SCRIPT"' config-probe
		[ "$status" -eq 0 ]
		[ "$output" = 'configuration and scopes match Git' ]
	done
}

@test "temporary config keeps hasconfig includes at command scope" {
	git config --file "$FRAGMENT" audit.hasconfig included
	if ! git -c "includeIf.hasconfig:remote.*.url:**.path=$FRAGMENT" config --get audit.hasconfig >/dev/null; then
		skip 'Git hasconfig includes are unavailable'
	fi
	make_config_probe
	run git -c "includeIf.hasconfig:remote.*.url:**.path=$FRAGMENT" \
		-c 'alias.config-probe=!sh "$REVIEW_TEST_SCRIPT"' config-probe
	[ "$status" -eq 0 ]
	[ "$output" = 'configuration and scopes match Git' ]
}
