#!/usr/bin/env bats

setup() {
	ROOT="$BATS_TEST_TMPDIR"
	export HOME="$ROOT/home"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"
	mkdir "$HOME"
	git config --global user.email tester@example.com
	git config --global user.name tester
	git config --global core.autocrlf false
	git init -q "$ROOT/source"
	cd "$ROOT/source"
	printf '*.tmp\n' >.gitignore
	printf 'a base\n' >a.txt
	git add .
	git commit -qm base
	BASE=$(git rev-parse HEAD)
	git branch -M main
	git switch -qc topic
	printf 'a topic\n' >a.txt
	git commit -qam 'first step'
	FIRST=$(git rev-parse HEAD)
	printf 'tracked by the next step\n' >build.tmp
	git add -f build.tmp
	git commit -qm 'second step'
	TIP=$(git rev-parse HEAD)
	git switch -q main
	printf 'existing local edit\n' >a.txt
	printf 'existing ignored file\n' >build.tmp
}

@test "workspace opens a staged review outside the source checkout" {
	before=$(git write-tree)
	run git review workspace open "$ROOT/review folder" -- main topic
	[ "$status" -eq 0 ]
	[ "$(git -C "$ROOT/review folder" rev-parse HEAD)" = "$BASE" ]
	[ "$(git -C "$ROOT/review folder" write-tree)" = "$(git rev-parse "$TIP^{tree}")" ]
	git -C "$ROOT/review folder" diff --quiet
	[ "$(git symbolic-ref --short HEAD)" = main ]
	[ "$(git write-tree)" = "$before" ]
	[ "$(cat build.tmp)" = 'existing ignored file' ]
	[ "$(cat a.txt)" = 'existing local edit' ]
	[ ! -e "$ROOT/review folder/.git/objects/info/alternates" ]
}

@test "workspace navigation reads commits without touching either checkout" {
	review="$ROOT/review"
	git review workspace open --step "$review" -- main topic
	printf 'generated while reviewing\n' >"$review/build.tmp"
	printf 'reviewer changes\n' >"$review/a.txt"
	index=$(git -C "$review" write-tree)

	run git -C "$review" review workspace next
	[ "$status" -eq 0 ]
	[[ "$output" == *'[2/2]'*'second step'* ]]
	run git -C "$review" review workspace diff
	[ "$status" -eq 0 ]
	[[ "$output" == *'+tracked by the next step'* ]]
	[ "$(git -C "$review" rev-parse HEAD)" = "$BASE" ]
	[ "$(git -C "$review" write-tree)" = "$index" ]
	[ "$(cat "$review/build.tmp")" = 'generated while reviewing' ]
	[ "$(cat "$review/a.txt")" = 'reviewer changes' ]

	run git -C "$review" review workspace checkout "$ROOT/second"
	[ "$status" -eq 0 ]
	[ "$(git -C "$ROOT/second" rev-parse HEAD)" = "$FIRST" ]
	[ "$(git -C "$ROOT/second" diff --cached --name-only)" = build.tmp ]
	[ "$(cat "$ROOT/second/build.tmp")" = 'tracked by the next step' ]
	run git -C "$review" review workspace prev
	[ "$status" -eq 0 ]
	[[ "$output" == *'[1/2]'*'first step'* ]]
	[ "$(cat "$review/build.tmp")" = 'generated while reviewing' ]
	[ "$(cat build.tmp)" = 'existing ignored file' ]
}

@test "workspace finish applies edits from the materialized step to the tip" {
	review="$ROOT/review"
	git review workspace open --step "$review" -- main topic
	printf 'review comment in code\n' >>"$review/a.txt"
	printf 'private build results\n' >"$review/build.tmp"
	old_index=$(git -C "$review" write-tree)
	git -C "$review" review workspace next
	run git -C "$review" review workspace finish "$ROOT/fixes"
	[ "$status" -eq 0 ]
	[ "$(git -C "$ROOT/fixes" rev-parse HEAD)" = "$TIP" ]
	[ "$(git -C "$ROOT/fixes" diff --cached --name-only)" = a.txt ]
	[ "$(cat "$ROOT/fixes/build.tmp")" = 'tracked by the next step' ]
	[ "$(tail -n 1 "$ROOT/fixes/a.txt")" = 'review comment in code' ]
	[ "$(tail -n 1 "$review/a.txt")" = 'review comment in code' ]
	[ "$(cat "$review/build.tmp")" = 'private build results' ]
	[ "$(git -C "$review" write-tree)" = "$old_index" ]
}

@test "workspace refuses a destination that already exists or is inside a checkout" {
	bats_require_minimum_version 1.5.0
	mkdir "$ROOT/existing"
	printf 'private file\n' >"$ROOT/existing/build.tmp"
	run --separate-stderr git review workspace open "$ROOT/existing" -- main topic
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'error: workspace destination must be a new directory'* ]]
	[ "$(cat "$ROOT/existing/build.tmp")" = 'private file' ]
	[ ! -e "$ROOT/existing/.git" ]
	run --separate-stderr git review workspace open inside -- main topic
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: choose a directory outside existing Git repositories' ]
	[ ! -e inside ]
}

@test "start and compare can open isolated workspaces from a dirty checkout" {
	bats_require_minimum_version 1.5.0
	git config reviewworkflow.base main
	git branch review/topic "$BASE"
	run git review start --offline --step --workspace "$ROOT/start" topic
	[ "$status" -eq 0 ]
	[ "$(git -C "$ROOT/start" rev-parse refs/review-workspace/cursor)" = "$FIRST" ]
	[ "$(git rev-parse review/topic)" = "$BASE" ]

	run git review compare --step --workspace "$ROOT/compare" main topic
	[ "$status" -eq 0 ]
	git -C "$ROOT/compare" review workspace next
	git -C "$ROOT/compare" review workspace checkout "$ROOT/compare-step"
	run --separate-stderr git -C "$ROOT/compare-step" review workspace finish "$ROOT/fixes"
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: this workspace is a read-only comparison' ]
	[ ! -e "$ROOT/fixes" ]
	[ "$(git symbolic-ref --short HEAD)" = main ]
	[ "$(cat build.tmp)" = 'existing ignored file' ]
	[ "$(cat a.txt)" = 'existing local edit' ]
}

@test "workspace finish combines edits from separately materialized steps" {
	first="$ROOT/first"
	second="$ROOT/second"
	git review start --offline --step --workspace "$first" topic --base main
	printf 'first correction\n' >>"$first/a.txt"
	git -C "$first" review workspace next
	git -C "$first" review workspace checkout "$second"
	printf 'second correction\n' >>"$second/build.tmp"
	run git -C "$first" review workspace finish "$ROOT/fixes" "$second"
	[ "$status" -eq 0 ]
	[ "$(git -C "$ROOT/fixes" rev-parse HEAD)" = "$TIP" ]
	[ "$(git -C "$ROOT/fixes" diff --cached --name-only)" = $'a.txt\nbuild.tmp' ]
	[ "$(tail -n 1 "$ROOT/fixes/a.txt")" = 'first correction' ]
	[ "$(tail -n 1 "$ROOT/fixes/build.tmp")" = 'second correction' ]
	[ "$(tail -n 1 "$first/a.txt")" = 'first correction' ]
	[ "$(tail -n 1 "$second/build.tmp")" = 'second correction' ]
}

@test "a conflicted isolated finish preserves the editable workspace and output" {
	bats_require_minimum_version 1.5.0
	git worktree add -q -b conflict "$ROOT/pr" "$TIP"
	printf 'conflicting tip content\n' >"$ROOT/pr/a.txt"
	git -C "$ROOT/pr" commit -qam 'change the same line'
	git review workspace open --step "$ROOT/review" -- main conflict
	printf 'reviewer content\n' >"$ROOT/review/a.txt"
	before=$(git -C "$ROOT/review" write-tree)
	run --separate-stderr git -C "$ROOT/review" review workspace finish "$ROOT/conflicted"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'workspace files retained at '*'/conflicted'* ]]
	[ "$(cat "$ROOT/review/a.txt")" = 'reviewer content' ]
	[ "$(git -C "$ROOT/review" write-tree)" = "$before" ]
	[ -n "$(git -C "$ROOT/conflicted" ls-files --unmerged -- a.txt)" ]
	[ "$(cat a.txt)" = 'existing local edit' ]
}

@test "workspace copies a fetched tip that is absent from local tracking refs" {
	git init --bare -q "$ROOT/server.git"
	git remote add origin "$ROOT/server.git"
	git push -q origin main
	git --git-dir="$ROOT/server.git" fetch -q --no-tags "$ROOT/source" topic:refs/heads/topic
	before=$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes/)
	run git review start --step --workspace "$ROOT/fetched" topic --base main
	[ "$status" -eq 0 ]
	[ "$(git -C "$ROOT/fetched" rev-parse refs/review-workspace/tip)" = "$TIP" ]
	[ "$(git -C "$ROOT/fetched" rev-parse refs/review-workspace/cursor)" = "$FIRST" ]
	[ "$(git for-each-ref --format='%(refname) %(objectname)' refs/remotes/)" = "$before" ]
	[ "$(cat a.txt)" = 'existing local edit' ]
}

@test "workspace leaves submodule files in the checkout where they were created" {
	git init -q "$ROOT/child"
	printf 'tracked child data\n' >"$ROOT/child/tracked"
	git -C "$ROOT/child" add .
	git -C "$ROOT/child" commit -qm child
	git init --bare -q "$ROOT/server.git"
	git remote add origin "$ROOT/server.git"
	git worktree add -q -b nesting "$ROOT/pr" "$BASE"
	git -C "$ROOT/pr" -c protocol.file.allow=always submodule add -q ../child nested
	git -C "$ROOT/pr" commit -qm 'add child'
	git -C "$ROOT/pr" rm -fq nested
	mkdir "$ROOT/pr/nested"
	printf 'new parent data\n' >"$ROOT/pr/nested/tracked"
	git -C "$ROOT/pr" add nested
	git -C "$ROOT/pr" commit -qm 'replace child'

	git review workspace open --step "$ROOT/review" -- main nesting
	git -C "$ROOT/review" -c protocol.file.allow=always submodule update --init --recursive
	printf 'private child edit\n' >"$ROOT/review/nested/tracked"
	git -C "$ROOT/review" review workspace next
	run git -C "$ROOT/review" review workspace checkout "$ROOT/second"
	[ "$status" -eq 0 ]
	[ "$(cat "$ROOT/review/nested/tracked")" = 'private child edit' ]
	[ "$(cat "$ROOT/second/nested/tracked")" = 'new parent data' ]
	[ -f "$ROOT/review/nested/.git" ]
	[ ! -e "$ROOT/second/nested/.git" ]
}

@test "workspace preserves ignored non-ASCII aliases under the C locale" {
	lower=$(printf '\303\251.tmp')
	upper=$(printf '\303\211.tmp')
	git worktree add -q -b aliases "$ROOT/pr" "$FIRST"
	printf 'PR content\n' >"$ROOT/pr/$upper"
	git -C "$ROOT/pr" add -f -- "$upper"
	git -C "$ROOT/pr" commit -qm 'track upper-case name'
	git review workspace open --step "$ROOT/review" -- main aliases
	printf 'local ignored data\n' >"$ROOT/review/$lower"

	run env LC_ALL=C git -C "$ROOT/review" review workspace next
	[ "$status" -eq 0 ]
	[[ "$output" == *'[2/2]'* ]]
	run env LC_ALL=C git -C "$ROOT/review" review workspace checkout "$ROOT/second"
	[ "$status" -eq 0 ]
	[ "$(cat "$ROOT/review/$lower")" = 'local ignored data' ]
	[ "$(cat "$ROOT/second/$upper")" = 'PR content' ]
}
