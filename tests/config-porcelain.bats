#!/usr/bin/env bats
#
# Tests for git review config --porcelain: the effective config, the candidate
# branches, and the delta marker a caller needs *before* a review exists —
# contracts/config-porcelain.md. The human and read/write/unset forms are
# covered in tests/config.bats.

setup() {
	TMP="$(mktemp -d)"
	export HOME="$TMP/home"
	mkdir -p "$HOME"
	export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"

	git config --global user.email t@example.com
	git config --global user.name tester
	git config --global init.defaultBranch develop

	ORIGIN="$TMP/origin.git"
	WORK="$TMP/work"
	git init --quiet --bare "$ORIGIN"
	git init --quiet "$WORK"
	cd "$WORK"
	git remote add origin "$ORIGIN"

	printf 'base\n' >base.txt
	git add base.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop
}

teardown() {
	rm -rf "$TMP"
}

# The single candidate/config/remote-candidate line tagged <tag> for <name>
# (candidate: also filtered by <origin>), from the last run's output.
row() {
	if [ "$1" = candidate ]; then
		printf '%s\n' "$output" | awk -F'\t' -v n="$2" -v o="$3" '$1=="candidate" && $2==n && $3==o'
	elif [ "$1" = "remote-candidate" ]; then
		printf '%s\n' "$output" | awk -F'\t' -v n="$2" '$1=="remote-candidate" && $2==n'
	else
		printf '%s\n' "$output" | awk -F'\t' -v t="$1" -v n="$2" '$1==t && $2==n'
	fi
}

# delta_row <name> [origin] — origin optional; without it any delta for name.
delta_row() {
	if [ $# -ge 2 ]; then
		printf '%s\n' "$output" | awk -F'\t' -v n="$1" -v o="$2" '$1=="delta" && $2==n && $4==o'
	else
		printf '%s\n' "$output" | awk -F'\t' -v n="$1" '$1=="delta" && $2==n'
	fi
}

# ── config record: base omitted unset, remote always present ─────────────────

@test "porcelain on a freshly cloned, unconfigured repo emits only remote, no base" {
	run git review config --porcelain
	[ "$status" -eq 0 ]
	n="$(printf '%s\n' "$output" | grep -c '^config' || true)"
	[ "$n" -eq 1 ]
	[ "$(row config remote)" = "$(printf 'config\tremote\torigin')" ]
}

@test "porcelain with base configured emits both config lines" {
	git config reviewworkflow.base develop
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[ "$(row config base)" = "$(printf 'config\tbase\tdevelop')" ]
	[ "$(row config remote)" = "$(printf 'config\tremote\torigin')" ]
}

# ── remote-candidate: remotes of the repo for config remote ───────────────────

@test "porcelain emits a remote-candidate per remote, marking the effective one current" {
	git remote add upstream "$ORIGIN"
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[ "$(row remote-candidate origin)" = "$(printf 'remote-candidate\torigin\t1')" ]
	[ "$(row remote-candidate upstream)" = "$(printf 'remote-candidate\tupstream\t0')" ]
}

@test "porcelain marks remote-candidate current for a configured non-origin remote" {
	git remote add upstream "$ORIGIN"
	git config reviewworkflow.remote upstream
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[ "$(row config remote)" = "$(printf 'config\tremote\tupstream')" ]
	[ "$(row remote-candidate origin)" = "$(printf 'remote-candidate\torigin\t0')" ]
	[ "$(row remote-candidate upstream)" = "$(printf 'remote-candidate\tupstream\t1')" ]
}

# ── candidate branches: per-namespace, origin, current ────────────────────────

@test "porcelain emits a candidate per branch in both namespaces, marking origin and current correctly" {
	git switch --quiet -c feature/checkout
	printf 'a\n' >a.txt
	git add a.txt
	git commit --quiet -m c1
	git push --quiet -u origin feature/checkout
	git switch --quiet develop

	run git review config --porcelain
	[ "$status" -eq 0 ]
	[ "$(row candidate develop local)" = "$(printf 'candidate\tdevelop\tlocal\t1')" ]
	[ "$(row candidate develop remote)" = "$(printf 'candidate\tdevelop\tremote\t0')" ]
	[ "$(row candidate feature/checkout local)" = "$(printf 'candidate\tfeature/checkout\tlocal\t0')" ]
	[ "$(row candidate feature/checkout remote)" = "$(printf 'candidate\tfeature/checkout\tremote\t0')" ]
}

@test "porcelain excludes review, review-saved, review-fixes and <remote>/HEAD from candidates" {
	git branch review/ghost develop
	git branch review-saved/ghost develop
	git branch review-fixes/ghost develop
	git push --quiet origin develop:refs/heads/review/ghost
	git fetch --quiet origin

	run git review config --porcelain
	[ "$status" -eq 0 ]
	[ -z "$(row candidate review/ghost local)" ]
	[ -z "$(row candidate review-saved/ghost local)" ]
	[ -z "$(row candidate review-fixes/ghost local)" ]
	[ -z "$(row candidate review/ghost remote)" ]
	n="$(printf '%s\n' "$output" | awk -F'\t' '$1=="candidate" && $2=="HEAD"' | grep -c . || true)"
	[ "$n" -eq 0 ]
}

@test "porcelain marks current=1 only on the local branch HEAD is on, and none with HEAD detached" {
	run git review config --porcelain
	[ "$status" -eq 0 ]
	[ "$(row candidate develop local)" = "$(printf 'candidate\tdevelop\tlocal\t1')" ]

	git switch --quiet --detach develop
	run git review config --porcelain
	[ "$status" -eq 0 ]
	n="$(printf '%s\n' "$output" | awk -F'\t' '$1=="candidate" && $4=="1"' | grep -c . || true)"
	[ "$n" -eq 0 ]
}

@test "porcelain -- <branch> treats a branch named like an option as the delta argument, not a flag" {
	# git branch itself refuses a dash-leading name; update-ref does not, and it
	# is exactly the case the -- idiom exists for: a legal branch name that a
	# naive parser would read as an option.
	git update-ref refs/heads/-weird develop
	git config "reviewworkflow.-weird.reviewed" "$(git rev-parse develop)"
	run git review config --porcelain -- -weird
	[ "$status" -eq 0 ]
	[ "$(row candidate -weird local)" = "$(printf 'candidate\t-weird\tlocal\t0')" ]
	[ "$(delta_row -weird remote)" = "$(printf 'delta\t-weird\t%s\tremote' "$(git rev-parse develop)")" ]
}

# ── bytes and cost (Decision 2 of 001/003, applied here) ──────────────────────

@test "a branch name with accents comes out byte for byte, unquoted, like a path" {
	accented="feature/a$(printf '\303\261')adir-caf$(printf '\303\251')"
	git switch --quiet -c "$accented"
	git switch --quiet develop

	run git review config --porcelain
	[ "$status" -eq 0 ]
	[ "$(row candidate "$accented" local)" = "$(printf 'candidate\t%s\tlocal\t0' "$accented")" ]
}

@test "porcelain candidate listing stays cheap with 30 extra branches (regression guard, not a strict benchmark)" {
	i=1
	while [ "$i" -le 5 ]; do
		git branch "extra/warmup-$i" develop
		i=$((i + 1))
	done
	start_ns="$(date +%s%N)"
	run git review config --porcelain
	end_ns="$(date +%s%N)"
	[ "$status" -eq 0 ]
	baseline_ms=$(( (end_ns - start_ns) / 1000000 ))

	i=1
	while [ "$i" -le 30 ]; do
		git branch "extra/more-$i" develop
		i=$((i + 1))
	done
	start_ns="$(date +%s%N)"
	run git review config --porcelain
	end_ns="$(date +%s%N)"
	[ "$status" -eq 0 ]
	loaded_ms=$(( (end_ns - start_ns) / 1000000 ))

	# A per-branch process (the bug this guards against) would make loaded_ms
	# grow roughly linearly with the extra 30 branches; one for-each-ref call
	# keeps it close to baseline_ms regardless of branch count. Generous
	# multiplier — a regression guard, not a tight benchmark — to avoid flaking
	# on a loaded CI box.
	[ "$loaded_ms" -le $((baseline_ms * 5 + 500)) ]
}

# ── delta marker: only with a named branch, only when it was reviewed before ──

@test "porcelain without a branch argument never emits delta" {
	git config "reviewworkflow.feature/checkout.reviewed" "$(git rev-parse develop)"
	run git review config --porcelain
	[ "$status" -eq 0 ]
	n="$(printf '%s\n' "$output" | grep -c '^delta' || true)"
	[ "$n" -eq 0 ]
}

@test "porcelain <branch> emits delta only when a previous review tip is recorded" {
	git switch --quiet -c feature/checkout
	printf 'a\n' >a.txt
	git add a.txt
	git commit --quiet -m c1
	git push --quiet -u origin feature/checkout
	git switch --quiet develop
	tip="$(git rev-parse feature/checkout)"
	git config "reviewworkflow.feature/checkout.reviewed" "$tip"

	run git review config --porcelain feature/checkout
	[ "$status" -eq 0 ]
	[ "$(delta_row feature/checkout remote)" = "$(printf 'delta\tfeature/checkout\t%s\tremote' "$tip")" ]
	[ -z "$(delta_row feature/checkout local)" ]
}

@test "porcelain <branch> emits no delta when that branch was never reviewed" {
	git switch --quiet -c feature/new
	git switch --quiet develop
	run git review config --porcelain feature/new
	[ "$status" -eq 0 ]
	[ -z "$(delta_row feature/new)" ]
}

@test "porcelain <branch> also reads the local delta marker (reviewworkflowlocal.<branch>.reviewed)" {
	git switch --quiet -c feature/local-only
	printf 'a\n' >a.txt
	git add a.txt
	git commit --quiet -m c1
	git switch --quiet develop
	tip="$(git rev-parse feature/local-only)"
	git config "reviewworkflowlocal.feature/local-only.reviewed" "$tip"

	run git review config --porcelain feature/local-only
	[ "$status" -eq 0 ]
	[ "$(delta_row feature/local-only local)" = "$(printf 'delta\tfeature/local-only\t%s\tlocal' "$tip")" ]
	[ -z "$(delta_row feature/local-only remote)" ]
}

@test "porcelain <branch> emits remote and local delta rows separately when both markers exist" {
	git switch --quiet -c feature/both
	printf 'a\n' >a.txt
	git add a.txt
	git commit --quiet -m c1
	git push --quiet -u origin feature/both
	printf 'b\n' >b.txt
	git add b.txt
	git commit --quiet -m c2
	git switch --quiet develop
	remote_tip="$(git rev-parse origin/feature/both)"
	local_tip="$(git rev-parse feature/both)"
	git config "reviewworkflow.feature/both.reviewed" "$remote_tip"
	git config "reviewworkflowlocal.feature/both.reviewed" "$local_tip"

	run git review config --porcelain feature/both
	[ "$status" -eq 0 ]
	[ "$(delta_row feature/both remote)" = "$(printf 'delta\tfeature/both\t%s\tremote' "$remote_tip")" ]
	[ "$(delta_row feature/both local)" = "$(printf 'delta\tfeature/both\t%s\tlocal' "$local_tip")" ]
	n="$(printf '%s\n' "$output" | grep -c '^delta' || true)"
	[ "$n" -eq 2 ]
	# Stable order: remote first, then local — never a collapsed OR tip.
	first="$(printf '%s\n' "$output" | awk -F'\t' '$1=="delta"{print $4; exit}')"
	[ "$first" = "remote" ]
}
