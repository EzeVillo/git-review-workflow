#!/usr/bin/env bats
#
# Tests for git review compare: a read-only review that stages the diff between
# two commit-ish (tags, branches, commits), with optional --step walking, and on
# which git review finish refuses because there is no writable source branch.
#
# The history below tags three points so compare can diff between them:
#   v1.0  (base)            app.txt = a\nb\nc
#   c1    touches app.txt   app.txt = a\nB\nc\nd
#   v2.0  touches more.txt  more.txt added
# So v1.0..v2.0 spans two commits (c1, then the v2.0 commit).

@test "prepared compare fetches exactly the selected history and pins it for the session" {
	remote="$BATS_TEST_TMPDIR/remote.git"
	git init -q --bare "$remote"
	git remote add isolated "$remote"
	git push -q isolated 'v1.0^{commit}:refs/heads/topic' 'v1.0^{commit}:refs/heads/other'
	git fetch -q isolated
	# Advance the server from a separate worktree, like another contributor.
	git clone -q --branch topic "$remote" "$BATS_TEST_TMPDIR/author"
	printf 'a\nB from server\nc\n' > "$BATS_TEST_TMPDIR/author/app.txt"
	git -C "$BATS_TEST_TMPDIR/author" commit -qam 'server update'
	new_tip=$(git -C "$BATS_TEST_TMPDIR/author" rev-parse HEAD)
	git -C "$BATS_TEST_TMPDIR/author" push -q origin HEAD:refs/heads/topic HEAD:refs/heads/other
	! git cat-file -e "$new_tip^{commit}" 2>/dev/null
	before=$(git rev-parse refs/remotes/isolated/topic)
	local_tip=$(git rev-parse develop)
	run git review compare --sources --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *$'compare-source\ttopic\tremote\tisolated\tfetch:isolated:topic'* ]]
	[[ "$output" == *$'compare-source\ttopic\tcached\tisolated\trefs/remotes/isolated/topic'* ]]
	run git review compare --prepare --porcelain -- refs/remotes/isolated/topic fetch:isolated:topic
	[ "$status" -eq 0 ]
	token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comparison-prepared" {print $2}')
	[ -n "$token" ]
	[ "$(git rev-parse refs/remotes/isolated/topic)" = "$before" ]
	[ "$(git rev-parse refs/remotes/isolated/other)" = "$before" ]
	[ "$(git rev-parse develop)" = "$local_tip" ]
	[ "$(git for-each-ref --format='%(refname)' refs/worktree/review-compare/pending/)" = "refs/worktree/review-compare/pending/$token" ]
	run git review compare "--prepared=$token" --no-walk -- refs/remotes/isolated/topic fetch:isolated:other
	[ "$status" -eq 1 ]
	[[ "$output" == *'prepared comparison does not match'* ]]
	[ "$(git branch --show-current)" = develop ]
	run git review compare "--prepared=$token" --no-walk -- refs/remotes/isolated/topic fetch:isolated:topic
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/isolated/topic.reviewtip)" = "$new_tip" ]
	[ "$(git rev-parse HEAD)" = "$before" ]
	run git review compare --release -- "$token"
	[ "$status" -eq 0 ]
	! git show-ref --verify --quiet "refs/worktree/review-compare/pending/$token"
	git show-ref --verify --quiet refs/worktree/review-compare/session/isolated/topic
	run git review save
	[ "$status" -eq 0 ]
	git show-ref --verify --quiet refs/worktree/review-compare/session/isolated/topic
	run git review continue isolated/topic
	[ "$status" -eq 0 ]
	run git review comments add --document local --path app.txt --side head --start-line 2 --end-line 2 --text 'Keep this range.'
	[ "$status" -eq 0 ]
	run git review abort
	[ "$status" -eq 0 ]
	! git show-ref --verify --quiet refs/worktree/review-compare/session/isolated/topic
	[ "$(git rev-parse refs/remotes/isolated/topic)" = "$before" ]
	[ "$(git rev-parse refs/remotes/isolated/other)" = "$before" ]
	git reflog expire --expire=now --expire-unreachable=now --all
	git gc --prune=now
	git cat-file -e "$new_tip^{commit}"
	retained=$(git for-each-ref --format='%(refname)' refs/worktree/review-compare/comments/)
	[ -n "$retained" ]
	context=${retained##*/}
	run git review comments diff --document local --context "$context" --entry 1 --porcelain
	[ "$status" -eq 0 ]
	[[ "$output" == *$'comment-blob\tapp.txt\thead\tpresent\t'* ]]
	run git review comments delete --document local --context "$context" --entry 1
	[ "$status" -eq 0 ]
	! git show-ref --verify --quiet "$retained"
	git gc --prune=now
	! git cat-file -e "$new_tip^{commit}" 2>/dev/null
}

@test "compare clean only drops the refs owned by the removed session" {
	for target in c1 v2.0; do
		if [ "$target" = c1 ]; then git tag c1 v2.0^; fi
		run git review compare --prepare --porcelain -- v1.0 "$target"
		[ "$status" -eq 0 ]
		token=$(printf '%s\n' "$output" | awk -F '\t' '$1=="comparison-prepared" {print $2}')
		run git review compare "--prepared=$token" --no-walk -- v1.0 "$target"
		[ "$status" -eq 0 ]
		run git review compare --release -- "$token"
		[ "$status" -eq 0 ]
		if [ "$target" = c1 ]; then git switch --quiet --discard-changes develop; fi
	done
	git branch -D review/c1
	run git review clean --keep-fixes
	[ "$status" -eq 0 ]
	! git show-ref --verify --quiet refs/worktree/review-compare/session/c1
	git show-ref --verify --quiet refs/worktree/review-compare/session/v2.0
	[ "$(git branch --show-current)" = review/v2.0 ]
}

setup() {
	bats_require_minimum_version 1.5.0
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"

	git config --global user.email t@example.com
	git config --global user.name tester
	git config --global core.autocrlf false
	git config --global init.defaultBranch develop

	WORK="$TMP/work"
	git init --quiet "$WORK"
	cd "$WORK"

	printf 'a\nb\nc\n' >app.txt
	git add app.txt
	git commit --quiet -m base
	git tag v1.0

	printf 'a\nB\nc\nd\n' >app.txt
	git add app.txt
	git commit --quiet -m c1-touch-app

	printf 'more\n' >more.txt
	git add more.txt
	git commit --quiet -m c2-add-more
	git tag v2.0

	# Land back on a normal branch so compare records a return point.
	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

@test "compare stages the diff between two tags, read-only, clean working tree" {
	run git review compare v1.0 v2.0
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/v2.0" ]
	[[ "$output" == *"read-only"* ]]

	# The staged diff is exactly v1.0..v2.0: both files changed since v1.0.
	run git diff --cached --name-only
	[[ "$output" == *"app.txt"* ]]
	[[ "$output" == *"more.txt"* ]]
	# Working tree is clean — nothing unstaged.
	run git diff --name-only
	[ -z "$output" ]
	# HEAD sits at the lower bound; the index holds the upper bound's tree.
	[ "$(git rev-parse HEAD)" = "$(git rev-parse v1.0^{commit})" ]

	# The read-only marker is recorded on the review branch.
	[ "$(git config branch.review/v2.0.reviewreadonly)" = "1" ]
}

@test "compare resolves arbitrary commit-ish and falls back to a short-hash branch name" {
	# <b> = HEAD~1 is not a valid ref component, so the branch is named after its
	# short hash instead of the literal "HEAD~1".
	short="$(git rev-parse --short "v2.0~1^{commit}")"
	run git review compare v1.0 HEAD~1
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/$short" ]
	# Only app.txt changed between v1.0 and the c1 commit.
	run git diff --cached --name-only
	[ "$output" = "app.txt" ]
}

@test "git review finish refuses on a read-only compare" {
	git review compare v1.0 v2.0
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"read-only"* ]]
	[[ "$output" == *"nothing to write back"* ]]
	# It refused before producing anything: no review-fixes branch was created.
	run git rev-parse --verify --quiet refs/heads/review-fixes/v2.0
	[ "$status" -ne 0 ]
	# Still on the review branch, untouched.
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/v2.0" ]
}

@test "status --porcelain emits a readonly record on a compare review" {
	git review compare v1.0 v2.0
	run git review status --porcelain
	[ "$status" -eq 0 ]
	# Presence of the tag line (no fields): omit when not a compare, never blank.
	printf '%s\n' "$output" | grep -qx 'readonly'
}

@test "save and continue keep the readonly marker of a compare" {
	git review compare v1.0 v2.0
	run git review save
	[ "$status" -eq 0 ]
	[ "$(git config branch.review-saved/v2.0.reviewreadonly)" = "1" ]
	run git review continue v2.0
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/v2.0.reviewreadonly)" = "1" ]
	run git review status --porcelain
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -qx 'readonly'
}

@test "compare --step starts on the first commit of the range" {
	run git review compare v1.0 v2.0 --step
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/v2.0" ]
	[[ "$output" == *"[1/2]"* ]]
	[[ "$output" == *"c1-touch-app"* ]]
	[ "$(git config branch.review/v2.0.reviewreadonly)" = "1" ]
	# First step stages c1's diff (app.txt); working tree clean.
	run git diff --cached --name-only
	[ "$output" = "app.txt" ]
	run git diff --name-only
	[ -z "$output" ]
}

@test "compare --step walks forward with git review next to the end" {
	git review compare v1.0 v2.0 --step
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/2]"* ]]
	[[ "$output" == *"c2-add-more"* ]]
	run git diff --cached --name-only
	[ "$output" = "more.txt" ]

	# Past the last commit, next reports the end (no writeback hint differs, but the
	# end-of-walk message is the same one start --step uses).
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"no more commits"* ]]
}

@test "compare --step walks back with git review prev" {
	git review compare v1.0 v2.0 --step
	git review next
	run git review prev
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1/2]"* ]]
	[[ "$output" == *"c1-touch-app"* ]]
	run git diff --cached --name-only
	[ "$output" = "app.txt" ]
}

@test "git review finish refuses on a --step compare too" {
	git review compare v1.0 v2.0 --step
	run git review finish
	[ "$status" -ne 0 ]
	[[ "$output" == *"read-only"* ]]
	# No banked edits were extracted into a fixes branch.
	run git rev-parse --verify --quiet refs/heads/review-fixes/v2.0
	[ "$status" -ne 0 ]
}

@test "compare needs two commit-ish" {
	run git review compare v1.0
	[ "$status" -ne 0 ]
	[[ "$output" == *"two commit-ish"* ]]
	run git review compare
	[ "$status" -ne 0 ]
	[[ "$output" == *"two commit-ish"* ]]
}

@test "compare rejects an unknown commit-ish" {
	run git review compare v1.0 nope-no-such
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown commit: nope-no-such"* ]]
	# Nothing was created.
	run git rev-parse --verify --quiet refs/heads/review/nope-no-such
	[ "$status" -ne 0 ]
}

@test "compare refuses identical commit-ish" {
	run git review compare v2.0 v2.0
	[ "$status" -ne 0 ]
	[[ "$output" == *"same commit"* ]]
}

@test "compare refuses when a review branch already exists" {
	git review compare v1.0 v2.0
	git switch --quiet develop
	run git review compare v1.0 v2.0
	[ "$status" -ne 0 ]
	[[ "$output" == *"already exists"* ]]
}

@test "compare -h prints usage and exits 0" {
	run git review compare -h
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage: git review compare"* ]]
}

@test "compare accepts -- as the end-of-options separator" {
	run git review compare -- v1.0 v2.0
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review/v2.0" ]
}

@test "compare enters walk mode and its total includes files the walkthrough does not annotate" {
	# Its own fixture, on a throwaway branch off v2.0, so the shared setup() and
	# its other (exact-equality) assertions stay untouched: the walkthrough
	# covers app.txt but not more.txt, so more.txt is appended, unannotated, to
	# the end of the reading order instead of being reported separately.
	git switch --quiet -c wt-fixture v2.0
	mkdir -p .review
	cat >.review/walkthrough.md <<'EOF'
# Walkthrough

## 1. app.txt
covered
EOF
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough

	run git review compare v1.0 wt-fixture
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/wt-fixture.reviewmode)" = "walk" ]
	# app.txt (guided) + the walkthrough sidecar itself and more.txt (both
	# unannotated, appended in git's own order — ".review/" sorts before "m").
	[ "$(git config branch.review/wt-fixture.reviewwalkcount)" = "3" ]
	[[ "$output" == *"[1/3] app.txt"* ]]
	[[ "$output" == *"not in the walkthrough are added to the end of the reading order: .review/walkthrough.md more.txt"* ]]

	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[2/3] .review/walkthrough.md  (uncovered)"* ]]
	run git review next
	[ "$status" -eq 0 ]
	[[ "$output" == *"[3/3] more.txt  (uncovered)"* ]]
}

@test "compare uses exact candidate refs when local remote and tag tips differ" {
    git switch --quiet -c feature v1.0
    printf 'local\n' >local.txt
    git add local.txt
    git commit --quiet -m local
    localtip="$(git rev-parse HEAD)"
    git tag feature v2.0
    git update-ref refs/remotes/upstream/feature v2.0
    git remote add upstream "$TMP/unused.git"
    git config reviewworkflow.remote upstream
    git switch --quiet develop

    run git review config --porcelain
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | awk -F'\t' '$1=="candidate-ref" && $2=="feature" && $3=="remote"')" = "$(printf 'candidate-ref\tfeature\tremote\trefs/remotes/upstream/feature')" ]
    [ "$(printf '%s\n' "$output" | awk -F'\t' '$1=="candidate-ref" && $2=="feature" && $3=="local"')" = "$(printf 'candidate-ref\tfeature\tlocal\trefs/heads/feature')" ]
    run git review compare --no-walk -- v1.0 refs/remotes/upstream/feature
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = review/upstream/feature ]
    [ "$(git config branch.review/upstream/feature.reviewtip)" = "$(git rev-parse v2.0)" ]
    [ "$(git config branch.review/upstream/feature.reviewdraft)" = feature ]
    [ "$(git write-tree)" = "$(git rev-parse 'v2.0^{tree}')" ]
    git review abort
    run git review compare --no-walk -- v1.0 refs/heads/feature
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = review/feature ]
    [ "$(git config branch.review/feature.reviewtip)" = "$localtip" ]
    [ "$(git write-tree)" = "$(git rev-parse 'refs/heads/feature^{tree}')" ]
}

@test "compare accepts the exact ref of a remote-only candidate" {
    git remote add origin "$TMP/unused.git"
    git update-ref refs/remotes/origin/remote-only v2.0
    run git review config --porcelain
    [ "$status" -eq 0 ]
    ref="$(printf '%s\n' "$output" | awk -F'\t' '$1=="candidate-ref" && $2=="remote-only" {print $4}')"
    [ "$ref" = refs/remotes/origin/remote-only ]
    run git review compare --step -- v1.0 "$ref"
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = review/origin/remote-only ]
    [ "$(git config branch.review/origin/remote-only.reviewdraft)" = remote-only ]
    [ "$(git config branch.review/origin/remote-only.reviewtip)" = "$(git rev-parse v2.0)" ]
    [ "$(git diff --cached --name-only)" = app.txt ]
}

check_comparison_context() {
    target="$1"
    shift
    git branch chosen-base v1.0
    lower="$(git rev-parse chosen-base)"
    upper="$(git rev-parse "$target")"
    run --separate-stderr git review compare "$@" -- chosen-base "$target"
    [ "$status" -eq 0 ]
    git update-ref refs/heads/chosen-base "$upper"
    expected="$(printf 'comparison\t%s\t%s\ncomparison-base\tchosen-base\ncomparison-target\t%s' "$lower" "$upper" "$target")"
    run --separate-stderr git review status --porcelain
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
    [ "$(printf '%s\n' "$output" | awk -F'\t' '$1 ~ /^comparison/')" = "$expected" ]
    run --separate-stderr git review status
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | sed -n '/^  from /p; /^  to /p')" = "$(printf '  from    chosen-base (%s)\n  to      %s (%s)' "$lower" "$target" "$upper")" ]
    run --separate-stderr git review save
    [ "$status" -eq 0 ]
    [ "$(git config "branch.review-saved/$target.reviewcomparebase")" = "$lower" ]
    run --separate-stderr git review continue "$target"
    [ "$status" -eq 0 ]
    [ "$(git config "branch.review/$target.reviewcomparebase")" = "$lower" ]
    run --separate-stderr git review status --porcelain
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | awk -F'\t' '$1 ~ /^comparison/')" = "$expected" ]
    [ "$(git branch --show-current)" = "review/$target" ]
}

@test "compare whole retains its original endpoints after refs move and save continue" {
    check_comparison_context v2.0 --no-walk
}

@test "compare step retains its original endpoints after refs move and save continue" {
    check_comparison_context v2.0 --step
    run --separate-stderr git review next
    [ "$status" -eq 0 ]
    [ "$(git config branch.review/v2.0.reviewstep)" = 2 ]
    run --separate-stderr git review status --porcelain
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | awk -F'\t' '$1 ~ /^comparison/')" = "$expected" ]
}

@test "compare walk retains its original endpoints after refs move and save continue" {
    git switch --quiet -c walk-context v2.0
    mkdir -p .review
    printf '# Walkthrough\n\n## 1. app.txt\nwhy\n' >.review/walkthrough.md
    git add .review/walkthrough.md
    git commit --quiet -m walkthrough
    git switch --quiet develop
    check_comparison_context walk-context
    [ "$(git config branch.review/walk-context.reviewmode)" = walk ]
}

# Fill a generated comparison draft without removing its pinned context.
fill_compare_draft() {
	_draft="$(find .git/review-walkthrough/compare -name '*.md')"
	awk '/^## Heads-up/ { exit } { print }' "$_draft" >"$_draft.filled"
	printf '## Heads-up\n\nRead the app first.\n\n## 1. app.txt\n> key\nApplication change.\n\n## 2. more.txt\nSupporting file.\n' >>"$_draft.filled"
	mv "$_draft.filled" "$_draft"
	DRAFT_ID="${_draft#.git/review-walkthrough/}"
	DRAFT_ID="${DRAFT_ID%.md}"
}

@test "compare offers are resolved for exact endpoints without configured base or writes" {
	before="$(git count-objects -v)"
	run git review config --porcelain --compare -- v1.0 v2.0
	[ "$status" -eq 0 ]
	[[ "$output" == *$'offer\tdraft\tavailable'* ]]
	[[ "$output" == *$'offer\tstep\tavailable'* ]]
	[[ "$output" != *$'offer\tkeys\t'* ]]
	[ ! -e .git/review-walkthrough ]
	[ "$(git count-objects -v)" = "$before" ]
	[ -z "$(git status --porcelain)" ]
	[ "$(git branch --show-current)" = develop ]
}

@test "compare draft creates resumes builds and starts the pinned comparison" {
	run git review walkthrough draft --compare -- v1.0 v2.0
	[ "$status" -eq 0 ]
	[ -z "$(git status --porcelain)" ]
	run git review config --porcelain --compare -- v1.0 v2.0
	[ "$status" -eq 0 ]
	[[ "$output" == *$'offer\tdraft-resume\tavailable'* ]]
	[[ "$output" == *$'\tcompare\tfull\tfresh'* ]]
	fill_compare_draft
	run git review walkthrough draft --build --compare -- "$DRAFT_ID"
	[ "$status" -eq 0 ]
	run git review config --porcelain --compare -- "$DRAFT_ID"
	[ "$status" -eq 0 ]
	[[ "$output" == *$'offer\twalk\trecommended'* ]]
	[[ "$output" == *$'offer\tkeys\tavailable'* ]]
	[[ "$output" != *$'offer\tdraft-resume\t'* ]]
	base_oid="$(git rev-parse v1.0)"
	target_oid="$(git rev-parse v2.0)"
	git tag -f v2.0 v1.0
	run git review compare --draft -- "$DRAFT_ID"
	[ "$status" -eq 0 ]
	[ "$(git config branch.review/v2.0.reviewreadonly)" = 1 ]
	[ "$(git config branch.review/v2.0.reviewcomparebase)" = "$base_oid" ]
	[ "$(git config branch.review/v2.0.reviewtip)" = "$target_oid" ]
	[ "$(git config branch.review/v2.0.reviewdraft)" = "$DRAFT_ID" ]
	[ "$(git config branch.review/v2.0.reviewmode)" = walk ]
}

@test "compare draft round trips pinned SHA256 endpoints and the exact staged diff" {
	git init --quiet --object-format=sha256 "$TMP/sha256"
	cd "$TMP/sha256"
	printf 'base\n' >app.txt
	git add app.txt
	git commit --quiet -m base
	git tag v1.0
	printf 'target\n' >app.txt
	printf 'more\n' >more.txt
	git add more.txt
	git commit --quiet -am target
	git tag v2.0
	local base_oid target_oid
	base_oid=$(git rev-parse v1.0)
	target_oid=$(git rev-parse v2.0)
	git diff --binary "$base_oid" "$target_oid" >"$TMP/expected"

	run git review walkthrough draft --compare -- v1.0 v2.0
	[ "$status" -eq 0 ]
	fill_compare_draft
	run git review walkthrough draft --build --compare -- "$DRAFT_ID"
	[ "$status" -eq 0 ]
	run git review config --porcelain --compare -- v1.0 v2.0
	[ "$status" -eq 0 ]
	[[ "$output" == *$'offer\twalk\trecommended'* ]]
	[[ "$output" != *$'offer\tdraft-update\t'* ]]
	git tag -f v2.0 v1.0
	run git review compare --draft -- "$DRAFT_ID"
	[ "$status" -eq 0 ]
	[ "$(git rev-parse HEAD)" = "$base_oid" ]
	[ "$(git config branch.review/v2.0.reviewtip)" = "$target_oid" ]
	git diff --cached --binary >"$TMP/staged"
	cmp "$TMP/expected" "$TMP/staged"
	git diff --quiet
}

@test "compare draft updates when either endpoint moves without touching branch drafts" {
	git branch target v2.0
	git branch from v1.0
	mkdir -p .git/review-walkthrough
	printf 'private branch order\n' >.git/review-walkthrough/target.md
	run git review walkthrough draft --compare -- from target
	[ "$status" -eq 0 ]
	fill_compare_draft
	git branch -f from v1.0~0
	git branch -f from v2.0~1
	run git review config --porcelain --compare -- from target
	[ "$status" -eq 0 ]
	[[ "$output" == *$'offer\tdraft-update\tavailable'* ]]
	run git review walkthrough draft --compare -- from target
	[ "$status" -eq 0 ]
	[ "$(cat .git/review-walkthrough/target.md)" = 'private branch order' ]
	[[ "$(cat "$_draft")" == *'Supporting file.'* ]]
	[[ "$(cat "$_draft")" != *'## 1. app.txt'* ]]
	run git review config --porcelain --compare -- target from
	[ "$status" -eq 0 ]
	[[ "$output" != *$'offer\tstep\t'* ]]
	[ "$(git branch --show-current)" = develop ]
}

@test "invalid compare probes and draft contexts fail without changing git state" {
	run git review config --porcelain --compare -- v1.0 missing
	[ "$status" -ne 0 ]
	[[ "$output" == *'error: unknown commit: missing'* ]]
	run git review walkthrough draft --compare --local -- v1.0 v2.0
	[ "$status" -ne 0 ]
	[[ "$output" == *'--compare cannot be combined'* ]]
	run git review compare --draft -- ../outside
	[ "$status" -ne 0 ]
	[[ "$output" == *'not a comparison draft'* ]]
	[ ! -e .git/review-walkthrough ]
	[ -z "$(git status --porcelain)" ]
	[ "$(git branch --show-current)" = develop ]
}


@test "compare draft survives save continue and CRLF without false update offers" {
	git review walkthrough draft --compare -- v1.0 v2.0
	fill_compare_draft
	git review walkthrough draft --build --compare -- "$DRAFT_ID"
	awk '{ printf "%s\r\n", $0 }' "$_draft" >"$_draft.crlf"
	mv "$_draft.crlf" "$_draft"
	run git review config --porcelain --compare -- v1.0 v2.0
	[ "$status" -eq 0 ]
	[[ "$output" == *$'draft-title\t'"$DRAFT_ID"$'\tv1.0 → v2.0'* ]]
	[[ "$output" != *$'offer\tdraft-update\t'* ]]
	run git review compare --draft -- "$DRAFT_ID"
	[ "$status" -eq 0 ]
	run git review walkthrough draft --local
	[ "$status" -ne 0 ]
	[[ "$output" == *'--compare cannot be combined'* ]]
	run git review walkthrough draft --build
	[ "$status" -eq 0 ]
	run git review save
	[ "$status" -eq 0 ]
	[ ! -e "$_draft" ]
	[ -f ".git/review-saved-walkthrough/$DRAFT_ID.md" ]
	run git review continue v2.0
	[ "$status" -eq 0 ]
	[ -f "$_draft" ]
	[ "$(git config branch.review/v2.0.reviewdraft)" = "$DRAFT_ID" ]
	[ "$(git config branch.review/v2.0.reviewmode)" = walk ]
}

@test "compare offers use exact base file set and author keys in that range only" {
	mkdir .review
	printf '# Walkthrough\n\n## 1. app.txt\n> key\nApp.\n' >.review/walkthrough.md
	git add .review/walkthrough.md
	git commit --quiet -m walkthrough
	git tag guided
	run git review config --porcelain --compare -- v1.0 guided
	[ "$status" -eq 0 ]
	[[ "$output" == *$'offer\tkeys\tavailable'* ]]
	[[ "$output" != *$'offer\tdraft\t'* ]]
	run git review config --porcelain --compare -- v2.0~1 guided
	[ "$status" -eq 0 ]
	[[ "$output" != *$'offer\tkeys\t'* ]]
	[[ "$output" != *$'offer\twalk\t'* ]]
	[[ "$output" == *$'offer\tdraft\tavailable'* ]]
	[ -z "$(git status --porcelain)" ]
	[ ! -e .git/review-walkthrough ]
}


@test "compare prepares an independent copy of an unfinished branch reading order" {
	git branch target v2.0
	mkdir -p .git/review-walkthrough
	printf '# Walkthrough\n\n## 1. app.txt\nMy existing why.\n\n## ?. more.txt\n<!-- why -->\n' >.git/review-walkthrough/target.md
	original="$(cat .git/review-walkthrough/target.md)"
	run git review config --porcelain --compare -- v1.0 target
	[ "$status" -eq 0 ]
	[[ "$output" == *$'offer\twalk\trecommended'* ]]
	[[ "$output" == *$'offer\tdraft\tavailable'* ]]
	run git review walkthrough draft --compare -- v1.0 target
	[ "$status" -eq 0 ]
	[ "$(cat .git/review-walkthrough/target.md)" = "$original" ]
	copied="$(find .git/review-walkthrough/compare -name '*.md')"
	[[ "$(cat "$copied")" == *'My existing why.'* ]]
	[[ "$(cat "$copied")" == *'## ?. more.txt'* ]]
	run git review config --porcelain --compare -- v1.0 target
	[ "$status" -eq 0 ]
	[[ "$output" == *$'offer\tdraft-resume\tavailable'* ]]
	[ -z "$(git status --porcelain)" ]
}


@test "compare does not offer a draft for an empty content difference" {
	git commit --quiet --allow-empty -m same-content
	git tag same-content
	run git review config --porcelain --compare -- v2.0 same-content
	[ "$status" -eq 0 ]
	[[ "$output" != *$'offer\tdraft'* ]]
	[[ "$output" == *$'offer\twhole\tavailable'* ]]
	[ ! -e .git/review-walkthrough ]
	[ -z "$(git status --porcelain)" ]
}
