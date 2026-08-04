#!/usr/bin/env bats
#
# Tests for the `finish` porcelain record (contracts/finish-state.md): the two
# states a `git review finish` can leave unresolved once it starts a closure.
# `list --porcelain` sees both — a completed closure, whose edits sit on
# review-fixes/<src> (or the PR branch with --onto-source) while review/<src>
# keeps a pending undo point; and a closure stopped mid-conflict, seen from
# outside. The conflict seen from INSIDE the review (status --porcelain) has
# its own tests in tests/status-porcelain.bats, next to the rest of that
# verb's contract.

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
	git config reviewworkflow.base develop

	printf 'a1\n' >a.txt
	git add a.txt
	git commit --quiet -m base
	git branch -M develop
	git push --quiet -u origin develop

	git switch --quiet -c feature/x
	printf 'a1\na2\n' >a.txt
	git add a.txt
	git commit --quiet -m c1-touch-a
	git push --quiet -u origin feature/x

	git switch --quiet develop
}

teardown() {
	rm -rf "$TMP"
}

# feature/conflict: cf1 touches x.txt and a later cf3 changes the same region,
# so the edit banked at step 2 cannot replay onto the tip once finish folds
# every banked step back at the end (bin/git-review-verbs/finish:406-426) —
# the exact mechanism tests/finish-abort.bats already relies on for the same
# reason. Leaves the review on review/feature/conflict at step 3, cf2's edit
# (on cfa.txt) live in the working tree and cf1's overlapping edit (on x.txt)
# banked at ref 2, ready for a `git review finish` that stops mid-conflict.
setup_conflict_pr() {
	git switch --quiet -c feature/conflict
	printf 'X0\n' >x.txt
	printf 'A0\n' >cfa.txt
	git add x.txt cfa.txt
	git commit --quiet -m cf-base
	printf 'X0\nX1\n' >x.txt
	git add x.txt
	git commit --quiet -m cf1-touch-x
	printf 'A0\nA1\n' >cfa.txt
	git add cfa.txt
	git commit --quiet -m cf2-touch-a
	printf 'X0\nX1-CHANGED\n' >x.txt
	git add x.txt
	git commit --quiet -m cf3-change-x
	git push --quiet -u origin feature/conflict
	git switch --quiet develop

	git review start feature/conflict --step # step 1 (cf-base)
	git review next                          # step 2 (cf1, x.txt = X0\nX1)
	printf 'X0\nX1-EDITED\n' >x.txt           # edit that will overlap the tip
	git review next                          # bank step 2, now step 3 (cf2)
	printf 'A0\nA1-EDITED\n' >cfa.txt         # edit that applies cleanly onto the tip
}

# ── list --porcelain: a completed closure is pending (T039) ─────────────────

@test "list --porcelain reports a completed closure as pending with onto 0" {
	git review start feature/x >/dev/null
	printf 'a1\na2\nFIX\n' >a.txt
	run git review finish
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/x" ]

	run git review list --porcelain
	[ "$status" -eq 0 ]
	finish_line="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "finish"')"
	[ "$finish_line" = "$(printf 'finish\treview/feature/x\tpending\t0')" ]
	# the branch reported is still review/<src>, not the finish destination
	branch_line="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "branch"' | cut -f1-2)"
	[ "$branch_line" = "$(printf 'branch\treview/feature/x')" ]
}

@test "list --porcelain reports a completed --onto-source closure as pending with onto 1, branch still review/<src>" {
	git review start feature/x >/dev/null
	printf 'a1\na2\nFIX\n' >a.txt
	run git review finish --onto-source
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "feature/x" ]

	run git review list --porcelain
	[ "$status" -eq 0 ]
	finish_line="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "finish"')"
	[ "$finish_line" = "$(printf 'finish\treview/feature/x\tpending\t1')" ]
	branch_line="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "branch"' | cut -f1-2)"
	[ "$branch_line" = "$(printf 'branch\treview/feature/x')" ]
}

@test "list --porcelain emits no finish record without any closure pending" {
	git review start feature/x >/dev/null
	run git review list --porcelain
	[ "$status" -eq 0 ]
	n="$(printf '%s\n' "$output" | grep -c '^finish' || true)"
	[ "$n" -eq 0 ]
}

# ── list --porcelain: the conflict state, seen from outside (T039) ─────────

@test "list --porcelain reports a stopped finish as conflict with onto 0, from another branch" {
	setup_conflict_pr
	run git review finish
	[ "$status" -ne 0 ]
	[ "$(git config branch.review/feature/conflict.reviewresume || true)" = "conflict" ]
	git switch --quiet --discard-changes develop

	run git review list --porcelain
	[ "$status" -eq 0 ]
	finish_line="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "finish"')"
	[ "$finish_line" = "$(printf 'finish\treview/feature/conflict\tconflict\t0')" ]
}

@test "list --porcelain reports a stopped --onto-source finish as conflict with onto 1" {
	setup_conflict_pr
	run git review finish --onto-source
	[ "$status" -ne 0 ]
	[ "$(git config branch.review/feature/conflict.reviewresume || true)" = "conflict" ]
	git switch --quiet --discard-changes develop

	run git review list --porcelain
	[ "$status" -eq 0 ]
	finish_line="$(printf '%s\n' "$output" | awk -F'\t' '$1 == "finish"')"
	[ "$finish_line" = "$(printf 'finish\treview/feature/conflict\tconflict\t1')" ]
}

# ── the record disappears once the closure resolves (T040) ─────────────────

@test "the finish conflict record leaves status --porcelain once --resume completes the closure" {
	setup_conflict_pr
	run git review finish
	[ "$status" -ne 0 ]

	printf 'X0\nX1-RESOLVED\n' >x.txt
	git add x.txt
	run git review finish --resume
	[ "$status" -eq 0 ]
	[ "$(git rev-parse --abbrev-ref HEAD)" = "review-fixes/feature/conflict" ]

	# review/feature/conflict still exists — finish never deletes it — so
	# switching back and reading status --porcelain there confirms the CONFLICT
	# record is really gone, not merely out of sight because HEAD moved: the
	# closure completed, so what remains behind is a pending undo point, which
	# status --porcelain never reports (only list does, per contract).
	git switch --quiet review/feature/conflict
	run git review status --porcelain
	[ "$status" -eq 0 ]
	n="$(printf '%s\n' "$output" | grep -c '^finish' || true)"
	[ "$n" -eq 0 ]
	[ -n "$(git config branch.review/feature/conflict.reviewundohead || true)" ]
}

@test "the finish pending record leaves list --porcelain once --abort undoes the closure" {
	git review start feature/x >/dev/null
	printf 'a1\na2\nFIX\n' >a.txt
	run git review finish
	[ "$status" -eq 0 ]

	run git review finish --abort
	[ "$status" -eq 0 ]

	run git review list --porcelain
	[ "$status" -eq 0 ]
	n="$(printf '%s\n' "$output" | grep -c '^finish' || true)"
	[ "$n" -eq 0 ]
	[ -z "$(git config branch.review/feature/x.reviewundohead || true)" ]
}

# ── additivity: no closure means the old output is untouched (T041) ────────

@test "status --porcelain and list --porcelain are unchanged when no closure is in progress" {
	tip="$(git rev-parse origin/feature/x)"
	run git review start feature/x
	[ "$status" -eq 0 ]

	run git review status --porcelain
	[ "$status" -eq 0 ]
	expected="$(printf 'state\treview/feature/x\tfeature/x\t%s\twhole\tnone\nentry\t1\ta.txt\nbase\tdevelop' "$tip")"
	[ "$output" = "$expected" ]

	git switch --quiet --discard-changes develop

	run git review list --porcelain
	[ "$status" -eq 0 ]
	expected_list="$(printf 'branch\treview/feature/x\t0\t0\t0\twhole')"
	[ "$output" = "$expected_list" ]
}
