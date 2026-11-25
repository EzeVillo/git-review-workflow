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

@test "workspace finish collects registered step checkouts without changing either index" {
	git checkout -- a.txt
	git review start --offline --step topic main
	printf 'first correction\n' >>a.txt
	git review next
	second="$ROOT/second"
	git review workspace checkout "$second"
	printf 'second correction\n' >>"$second/build.tmp"
	index=$(git write-tree)
	second_index=$(git -C "$second" write-tree)
	refs=$(git for-each-ref --format='%(objectname) %(refname)')
	output_dir="$ROOT/fixes"

	run git review workspace finish "$output_dir"
	[ "$status" -eq 0 ]
	[ "$(git -C "$output_dir" rev-parse HEAD)" = "$TIP" ]
	[ "$(git -C "$output_dir" show :a.txt)" = "$(printf 'a topic\nfirst correction')" ]
	[ "$(git -C "$output_dir" show :build.tmp)" = "$(printf 'tracked by the next step\nsecond correction')" ]
	[ "$(git symbolic-ref --short HEAD)" = review/topic ]
	[ "$(git config branch.review/topic.reviewreadstep)" = 2 ]
	[ "$(git write-tree)" = "$index" ]
	[ "$(git -C "$second" write-tree)" = "$second_index" ]
	[ "$(git for-each-ref --format='%(objectname) %(refname)')" = "$refs" ]
	[ "$(cat build.tmp)" = 'existing ignored file' ]
	[ "$(tail -n 1 a.txt)" = 'first correction' ]
	[ "$(tail -n 1 "$second/build.tmp")" = 'second correction' ]
}

@test "workspace finish exports edits from an ordinary whole review without closing it" {
	git checkout -- a.txt
	mv build.tmp "$ROOT/local-build"
	git review start --offline --no-walk topic main
	printf 'review correction\n' >>a.txt
	printf 'private build artifact\n' >local.tmp
	index=$(git write-tree)
	output_dir="$ROOT/fixes"

	run git review workspace finish "$output_dir"
	[ "$status" -eq 0 ]
	[ "$(git -C "$output_dir" rev-parse HEAD)" = "$TIP" ]
	[ "$(git -C "$output_dir" diff --cached --name-only)" = a.txt ]
	[ "$(git -C "$output_dir" show :a.txt)" = "$(printf 'a topic\nreview correction')" ]
	[ ! -e "$output_dir/local.tmp" ]
	[ "$(git symbolic-ref --short HEAD)" = review/topic ]
	[ "$(git write-tree)" = "$index" ]
	[ "$(cat local.tmp)" = 'private build artifact' ]
	[ "$(tail -n 1 a.txt)" = 'review correction' ]
}

@test "workspace finish leaves an ordinary walkthrough review at its reading position" {
	git checkout -- a.txt
	mv build.tmp "$ROOT/local-build"
	git switch -q topic
	mkdir -p .review
	printf '# Walkthrough\n\n## 1. a.txt\nRead the change.\n' >.review/walkthrough.md
	git add .review/walkthrough.md
	git commit -qm walkthrough
	tip=$(git rev-parse HEAD)
	git switch -q main
	git review start --offline topic main
	git review next
	printf 'review correction\n' >>a.txt
	status_before=$(git review status --porcelain)
	[[ "$status_before" == *$'\twalk\t'* ]]
	output_dir="$ROOT/fixes"

	run git review workspace finish "$output_dir"
	[ "$status" -eq 0 ]
	[ "$(git -C "$output_dir" rev-parse HEAD)" = "$tip" ]
	[ "$(git -C "$output_dir" diff --cached --name-only)" = a.txt ]
	[ "$(git -C "$output_dir" show :a.txt)" = "$(printf 'a topic\nreview correction')" ]
	[ "$(git review status --porcelain)" = "$status_before" ]
}

@test "workspace finish refuses an ordinary read-only comparison" {
	bats_require_minimum_version 1.5.0
	git checkout -- a.txt
	mv build.tmp "$ROOT/local-build"
	git review compare main topic --no-walk
	index=$(git write-tree)

	run --separate-stderr git review workspace finish "$ROOT/fixes"
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: this review is a read-only comparison' ]
	[ ! -e "$ROOT/fixes" ]
	[ "$(git symbolic-ref --short HEAD)" = review/topic ]
	[ "$(git write-tree)" = "$index" ]
}

@test "clean keeps the reviewed tip and isolated output after a workspace finish" {
	git checkout -- a.txt
	mv build.tmp "$ROOT/local-build"
	git review start --offline --no-walk topic main
	output_dir="$ROOT/fixes"
	run git review finish --workspace "$output_dir"
	[ "$status" -eq 0 ]
	[ "$(git config reviewworkflowlocal.topic.reviewed)" = "$TIP" ]
	git switch -q topic
	index=$(git write-tree)

	run git review clean --keep-fixes topic
	[ "$status" -eq 0 ]
	[ "$(git config reviewworkflowlocal.topic.reviewed)" = "$TIP" ]
	[ "$(git write-tree)" = "$index" ]
	[ "$(git -C "$output_dir" rev-parse HEAD)" = "$TIP" ]
	! git show-ref --verify --quiet refs/heads/review/topic
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

@test "a conflicted isolated finish preserves the output and resumes its frozen corrections" {
	bats_require_minimum_version 1.5.0
	git worktree add -q -b conflict "$ROOT/pr" "$TIP"
	printf 'conflicting tip content\n' >"$ROOT/pr/a.txt"
	git -C "$ROOT/pr" commit -qam 'change the same line'
	git review workspace open --step "$ROOT/review" -- main conflict
	printf 'reviewer content\n' >"$ROOT/review/a.txt"
	before=$(git -C "$ROOT/review" write-tree)
	git -C "$ROOT/review" review workspace next
	git -C "$ROOT/review" review workspace checkout "$ROOT/second"
	printf 'independent correction\n' >>"$ROOT/second/build.tmp"
	run --separate-stderr git -C "$ROOT/review" review workspace finish "$ROOT/conflicted" "$ROOT/second"
	[ "$status" -eq 1 ]
	[[ "$stderr" == *'workspace files retained at '*'/conflicted'* ]]
	[ "$(cat "$ROOT/review/a.txt")" = 'reviewer content' ]
	[ "$(git -C "$ROOT/review" write-tree)" = "$before" ]
	[ -n "$(git -C "$ROOT/conflicted" ls-files --unmerged -- a.txt)" ]
	run --separate-stderr git -C "$ROOT/conflicted" review workspace resume "$ROOT/resolved"
	[ "$status" -eq 1 ]
	[ "$stderr" = 'error: resolve and stage all conflicts before resuming' ]
	[ ! -e "$ROOT/resolved" ]

	printf 'resolution\n' >"$ROOT/conflicted/a.txt"
	git -C "$ROOT/conflicted" add a.txt
	printf 'later edit outside the delivery\n' >>"$ROOT/second/build.tmp"
	partial=$(git -C "$ROOT/conflicted" write-tree)
	run git -C "$ROOT/conflicted" review workspace resume "$ROOT/resolved"
	[ "$status" -eq 0 ]
	[ "$(git -C "$ROOT/resolved" rev-parse HEAD)" = "$(git rev-parse conflict)" ]
	[ "$(git -C "$ROOT/resolved" diff --cached --name-only)" = $'a.txt\nbuild.tmp' ]
	[ "$(cat "$ROOT/resolved/a.txt")" = 'resolution' ]
	[ "$(tail -n 1 "$ROOT/resolved/build.tmp")" = 'independent correction' ]
	[ "$(tail -n 1 "$ROOT/second/build.tmp")" = 'later edit outside the delivery' ]
	[ "$(git -C "$ROOT/conflicted" write-tree)" = "$partial" ]
	[ "$(cat a.txt)" = 'existing local edit' ]
}

@test "workspace verifies that every indexed path exists with its exact spelling" {
	bats_require_minimum_version 1.5.0
	printf 'filesystem probe\n' >"$ROOT/case-probe"
	aliases=0
	if [ -f "$ROOT/CASE-PROBE" ]; then aliases=1; fi
	upper=$(printf 'uppercase\n' | git hash-object -w --stdin)
	lower=$(printf 'lowercase\n' | git hash-object -w --stdin)
	GIT_INDEX_FILE="$ROOT/collision-index" git read-tree "$BASE"
	for blob in "$lower" "$upper"; do
		printf '100644 %s\tREADME.txt\n100644 %s\treadme.txt\n' "$upper" "$blob" |
			GIT_INDEX_FILE="$ROOT/collision-index" git update-index --index-info
		tree=$(GIT_INDEX_FILE="$ROOT/collision-index" git write-tree)
		commit=$(git commit-tree "$tree" -p "$BASE" -m 'case variants')
		target="$ROOT/workspace-$blob"
		run --separate-stderr git review workspace open "$target" -- "$BASE" "$commit"
		if [ "$aliases" -eq 1 ]; then
			[ "$status" -eq 1 ]
			[[ "$stderr" == *'the filesystem could not represent the checkout exactly'* ]]
			[ -z "$output" ]
			run git -C "$target" show-ref --verify --quiet refs/review-workspace/materialized
			[ "$status" -eq 1 ]
		else
			[ "$status" -eq 0 ]
			[ "$(git -C "$target" hash-object README.txt)" = "$upper" ]
			[ "$(git -C "$target" hash-object readme.txt)" = "$blob" ]
		fi
	done
	[ "$(cat build.tmp)" = 'existing ignored file' ]
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
