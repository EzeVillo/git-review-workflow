#!/usr/bin/env sh
#
# git-review-lib.sh — helpers shared by the git review step commands.
#
# This file is *sourced, never run*. The verbs that need the helpers below
# (start, next, prev, continue, compare) load it as
# "${GIT_REVIEW_LIBEXEC:?}/git-review-lib.sh" — GIT_REVIEW_LIBEXEC is exported by
# the git-review dispatcher before it execs the verb, and points at the real
# directory where the dispatcher, this lib and the git-review-verbs/ directory
# live together (installed as libexec, not on PATH). It only defines functions,
# so sourcing it has no side effects.

# show_commit <commit> <n> <total>
# Print a commit's diffstat first and its identifying header last, so the header
# stays next to the prompt instead of scrolling off the top when the diffstat is
# long for a commit that touches many files.
show_commit() {
	git --no-pager show --stat --format='' "$1"
	printf -- '----\n[%s/%s] %s\n%s\n\n%s\n----\nreview this commit, edit files, then run git review next\n' \
		"$2" "$3" "$(git rev-parse --short "$1")" \
		"$(git show -s --format='%an <%ae>' "$1")" \
		"$(git show -s --format='%s%n%n%b' "$1")"
}

# load_step_review_meta
# Confirm HEAD is on a review/* branch started with --step and load its metadata
# into the globals the caller and goto_step rely on: cur, src, tip, start, count,
# step, commits and total. Exits with a diagnostic on any inconsistency (wrong
# branch, wrong mode, or missing/corrupt metadata).
load_step_review_meta() {
	cur="$(git symbolic-ref --quiet --short HEAD || true)"
	[ -n "$cur" ] || {
		echo "error: not on a branch" >&2
		exit 1
	}
	case "$cur" in
	review/*) ;;
	*)
		echo "error: not on a review/* branch (HEAD is $cur)" >&2
		exit 1
		;;
	esac

	mode="$(git config "branch.$cur.reviewmode" || true)"
	[ "$mode" = "step" ] || {
		echo "error: $cur was not started with git review start --step" >&2
		exit 1
	}

	src="$(git config "branch.$cur.reviewsource" || true)"
	tip="$(git config "branch.$cur.reviewtip" || true)"
	start="$(git config "branch.$cur.reviewstart" || true)"
	count="$(git config "branch.$cur.reviewcount" || true)"
	step="$(git config "branch.$cur.reviewstep" || true)"

	# A key deleted by a hand-edit (while reviewmode stays "step") would otherwise
	# let set -e kill us silently mid-script; read with || true and report it.
	if [ -z "$src" ] || [ -z "$tip" ] || [ -z "$start" ] || [ -z "$count" ]; then
		echo "error: missing review metadata; was $cur created with git review start?" >&2
		exit 1
	fi

	commits="$(git rev-list --reverse --first-parent --no-merges "$start..$tip")"

	# Guard against a step that maps to no commit (corrupt config, hand-edited
	# metadata): otherwise goto_step's sed yields an empty commit and git rev-parse
	# '^{tree}' crashes mid-move.
	total="$(printf '%s\n' "$commits" | grep -c .)"
	case "$count" in
	*[!0-9]*)
		echo "error: corrupt review metadata: reviewcount is '$count', not a positive integer" >&2
		exit 1
		;;
	esac
	[ "$count" -ge 1 ] || {
		echo "error: corrupt review metadata: reviewcount is '$count', not a positive integer" >&2
		exit 1
	}
	case "$step" in
	'' | *[!0-9]*)
		echo "error: corrupt review metadata: reviewstep is '$step', not a positive integer" >&2
		exit 1
		;;
	esac
	if [ "$step" -lt 1 ] || [ "$step" -gt "$total" ]; then
		echo "error: review step $step out of range (1..$total) — corrupt metadata?" >&2
		exit 1
	fi
}

# goto_step <target>
# Move a --step review to step <target>: bank the current commit's edits, reset
# clean to the target commit, restore the target's previously banked edits (if
# any), then soft-reset so its diff is staged. Relies on the globals set by
# load_step_review_meta (cur, src, count, step, commits).
goto_step() {
	target="$1"
	cstep="$(printf '%s\n' "$commits" | sed -n "${step}p")"
	git add -A
	tree="$(git write-tree)"
	if [ "$tree" != "$(git rev-parse "$cstep^{tree}")" ]; then
		edit="$(git commit-tree "$tree" -p "$cstep" -m "review edits step $step")"
		git update-ref "refs/review-edits/$src/$step" "$edit"
	else
		# Reverting the step back to a clean tree must clear any edits we banked
		# earlier, or they resurrect on the next visit / at git review finish.
		git update-ref -d "refs/review-edits/$src/$step" 2>/dev/null || true
	fi
	ctarget="$(printf '%s\n' "$commits" | sed -n "${target}p")"
	git reset -q --hard "$ctarget"
	ref="refs/review-edits/$src/$target"
	if git rev-parse --verify --quiet "$ref" >/dev/null; then
		git diff --binary "${ref}^" "$ref" | git apply || {
			echo "error: could not restore banked edits for step $target" >&2
			exit 1
		}
	fi
	git reset -q --soft "$ctarget^"
	git config "branch.$cur.reviewstep" "$target"
	show_commit "$ctarget" "$target" "$count"
}
