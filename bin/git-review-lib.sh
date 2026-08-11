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

# ── Branch / remote candidates (git review config --porcelain) ────────────────

# candidate_remotes <effective-remote>
# Emit a "remote-candidate<TAB>name<TAB>current" row for every remote name
# `git remote` lists. current is 1 only for the name that matches the effective
# reviewworkflow.remote (origin when unset) — the pick list can put that first
# without re-deriving which remote is configured. One `git remote` call; the
# loop is shell built-ins over its output (contracts/config-porcelain.md
# "Costo"). Name is what a caller passes back to `config remote`.
candidate_remotes() {
	_cr_effective="$1"
	git remote |
		while IFS= read -r _cr_name; do
			[ -n "$_cr_name" ] || continue
			_cr_current=0
			if [ "$_cr_name" = "$_cr_effective" ]; then
				_cr_current=1
			fi
			porcelain_row remote-candidate "$_cr_name" "$_cr_current"
		done
}

# candidate_branches <remote>
# Emit a "candidate<TAB>name<TAB>origin<TAB>current" row for every branch
# eligible to start a review on: every ref in refs/heads/ and
# refs/remotes/<remote>/, minus the three product namespaces (review/,
# review-saved/, review-fixes/) and <remote>/HEAD — exactly what git review
# start refuses to review
# (bin/git-review-verbs/start:151-153), so offering them would be offering a
# guaranteed failure. name has no namespace prefix (it is what a caller passes
# back to start or to config <key>); origin is remote|local; current is 1 only
# for the local branch HEAD sits on, 0 everywhere else (including every remote
# row — a remote copy is never "current", only the local checkout can be).
#
# One for-each-ref call regardless of how many branches exist, not one process
# per branch (contracts/config-porcelain.md "Costo", same rule as status and
# list): the loop below is shell built-ins (case, parameter expansion,
# porcelain_row) over its output, so the process count stays constant.
candidate_branches() {
	_cb_remote="$1"
	_cb_cur="$(git symbolic-ref --quiet --short HEAD || true)"
	git for-each-ref --format='%(refname)' refs/heads/ "refs/remotes/$_cb_remote/" |
		while IFS= read -r _cb_ref; do
			case "$_cb_ref" in
			refs/heads/*)
				_cb_name="${_cb_ref#refs/heads/}"
				_cb_origin=local
				;;
			"refs/remotes/$_cb_remote/"*)
				_cb_name="${_cb_ref#refs/remotes/"$_cb_remote"/}"
				_cb_origin=remote
				;;
			*)
				continue
				;;
			esac
			case "$_cb_name" in
			review/* | review-saved/* | review-fixes/* | HEAD)
				continue
				;;
			esac
			_cb_current=0
			if [ "$_cb_origin" = local ] && [ "$_cb_name" = "$_cb_cur" ]; then
				_cb_current=1
			fi
			porcelain_row candidate "$_cb_name" "$_cb_origin" "$_cb_current"
		done
}

# ── Porcelain (machine-readable) output ───────────────────────────────────────
#
# porcelain_row <field> [field...]
# Print one porcelain-format line: the given fields joined by a tab, terminated
# by a newline. This is the single point that writes a porcelain line — every
# emitter (state, entry, uncovered, branch) builds its record by passing its
# fields through here instead of printf-ing tabs itself, so the separator lives
# in one place. A field the record's mode does not apply to is omitted from the
# call entirely, never passed as an empty string: omit, never blank, never a
# sentinel (contracts/status-porcelain.md, data-model.md).
porcelain_row() {
	_pr_first=1
	for _pr_field in "$@"; do
		if [ "$_pr_first" -eq 1 ]; then
			printf '%s' "$_pr_field"
			_pr_first=0
		else
			printf '\t%s' "$_pr_field"
		fi
	done
	printf '\n'
}

# show_commit <commit> <n> <total>
# Print a commit's diffstat first and its identifying header last, so the header
# stays next to the prompt instead of scrolling off the top when the diffstat is
# long for a commit that touches many files. core.quotePath=false for the same
# reason as changed_paths, one layer up: this is what the reviewer reads to know
# which files the step touches, and git's default would show it "src/caf\303\251.js"
# — an escape nobody can paste into an editor. Cosmetic here (nothing compares
# these bytes), but it keeps every path this project prints in one shape.
show_commit() {
	git --no-pager -c core.quotePath=false show --stat --format='' "$1"
	printf -- '----\n[%s/%s] %s\n%s\n\n%s\n----\nreview this commit, edit files, then run git review next\n' \
		"$2" "$3" "$(git rev-parse --short "$1")" \
		"$(git show -s --format='%an <%ae>' "$1")" \
		"$(git show -s --format='%s%n%n%b' "$1")"
}

# require_not_finish_conflict
# Refuse verbs that would bank/move/capture the working tree while a finish is
# stopped mid-conflict (reviewresume=conflict). Only finish --resume / --abort
# (and abort of the whole review) are valid exits; next/prev/save would bank
# conflict markers as "edits" or delete the review branch that holds the undo.
# Mirror of the same guard in git review preview.
require_not_finish_conflict() {
	_rnfc_cur="$(git symbolic-ref --quiet --short HEAD || true)"
	if [ "$(git config "branch.$_rnfc_cur.reviewresume" || true)" = "conflict" ]; then
		echo "error: git review finish is mid-conflict; resolve the markers and run git review finish --resume first (or git review finish --abort)" >&2
		exit 1
	fi
}

# require_not_pending_finish
# Refuse verbs that would bank/move/rename a review/* branch while a completed
# finish still holds reviewundohead on it. After finish, HEAD sits on
# review-fixes/* (or the PR) with undo live on review/*; hand-switching back and
# running next/prev/save would desync the cursor/banks and break finish --abort.
# Shared message for save/next/prev so consumers match one diagnostic.
require_not_pending_finish() {
	_rnpf_cur="$(git symbolic-ref --quiet --short HEAD || true)"
	if [ -n "$(git config "branch.$_rnpf_cur.reviewundohead" || true)" ]; then
		echo "error: a previous finish on $_rnpf_cur has not been resolved; run git review finish --abort (or git review abort) first" >&2
		exit 1
	fi
}

# require_clean_work_tree
# Refuse start/compare/continue when the worktree is dirty: tracked changes
# (diff / cached) *or* untracked non-ignored files. finish/save capture untracked
# with `git add -A` as review edits, so allowing pre-existing untracked through
# start would absorb junk as if the reviewer wrote it. Same message as before.
require_clean_work_tree() {
	if ! git diff --quiet || ! git diff --cached --quiet ||
		[ -n "$(git ls-files --others --exclude-standard)" ]; then
		echo "error: you have local changes; commit or stash them first" >&2
		exit 1
	fi
}

# apply_review_patch FROM TO [git-apply-args...]
# Diff FROM..TO and apply it, routing the patch through a temp file rather than a
# shell variable. Capturing a binary patch with command substitution drops its
# NUL bytes and trailing newline, so git apply later rejects it ("corrupt binary
# patch"). Always passes --binary to git apply (in addition to any caller args)
# so continue/finish/goto_step get the same binary safety as preview. An empty
# diff is a no-op success; returns git apply's exit status.
apply_review_patch() {
	_from="$1"
	_to="$2"
	shift 2
	_pf="$(git rev-parse --git-dir)/review-apply.$$"
	git diff --binary "$_from" "$_to" >"$_pf"
	if [ -s "$_pf" ]; then
		if git apply --binary "$@" <"$_pf"; then _rc=0; else _rc=$?; fi
	else
		_rc=0
	fi
	rm -f "$_pf"
	return "$_rc"
}

# entry_noun <count>
# "entry" or "entries" for human messages (avoids the A && B || C plural idiom).
entry_noun() {
	if [ "$1" -eq 1 ]; then
		printf '%s' "entry"
	else
		printf '%s' "entries"
	fi
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
		exit 2
		;;
	esac

	mode="$(git config "branch.$cur.reviewmode" || true)"
	[ "$mode" = "step" ] || {
		echo "error: $cur was not started with git review start --step or a walkthrough" >&2
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
		if [ -z "$src" ]; then
			echo "error: missing review metadata; was $cur created with git review start? Switch away, then delete it with 'git branch -D $cur'." >&2
		else
			echo "error: missing review metadata; was $cur created with git review start? Discard the review with 'git review abort'." >&2
		fi
		exit 1
	fi

	# Same as the walk loader: a step review does not read a walkthrough itself,
	# but its verbs share this scope with the walk readers, so the context is set
	# here too rather than left half-applied depending on the mode.
	#
	# Note the asymmetry it creates, and keep it in mind before giving step any
	# surface that shows a "why": the context is set, but nothing reports it —
	# status only emits the draft record (and the "(draft)" suffix) in walk mode,
	# because that is where a reading order exists. Today nothing reads a
	# walkthrough here (status --why refuses outside walk), so it is inert; a step
	# verb that started reading one would show the reviewer's own prose without
	# saying whose it is, which is the one thing this feature exists to prevent.
	#
	# Through the recorded name, like the walk loader: a step review of a
	# remote-tracking branch (compare --step) drafts under the branch's name too,
	# and one config read is what keeps the two loaders from disagreeing about
	# whose file it is.
	walk_use_draft "$(walk_review_draft_src "$cur")"

	commits="$(git rev-list --reverse --first-parent --no-merges "$start..$tip")"

	# Guard against a step that maps to no commit (corrupt config, hand-edited
	# metadata): otherwise goto_step's sed yields an empty commit and git rev-parse
	# '^{tree}' crashes mid-move.
	# grep -c exits 1 when the count is 0; under set -e that aborts the verb
	# without the corrupt-metadata diagnostic below. Walk uses || true for the
	# same reason.
	total="$(printf '%s\n' "$commits" | grep -c . || true)"
	case "$count" in
	*[!0-9]*)
		echo "error: corrupt review metadata: reviewcount is '$count', not a positive integer. Discard the review with 'git review abort'." >&2
		exit 1
		;;
	esac
	[ "$count" -ge 1 ] || {
		echo "error: corrupt review metadata: reviewcount is '$count', not a positive integer. Discard the review with 'git review abort'." >&2
		exit 1
	}
	case "$step" in
	'' | *[!0-9]*)
		echo "error: corrupt review metadata: reviewstep is '$step', not a positive integer. Discard the review with 'git review abort'." >&2
		exit 1
		;;
	esac
	if [ "$total" -lt 1 ]; then
		echo "error: corrupt review metadata: no commits in range $start..$tip. Discard the review with 'git review abort'." >&2
		exit 1
	fi
	if [ "$step" -lt 1 ] || [ "$step" -gt "$total" ]; then
		echo "error: review step $step out of range (1..$total) — corrupt metadata? Discard the review with 'git review abort'." >&2
		exit 1
	fi
}

# load_step_texts
# Load the subject and the author of every commit in the step sequence into the
# globals `subjects` and `authors` — one line per commit, aligned with `commits`
# by line number, so the n-th line of each list belongs to the n-th commit.
#
# Two git processes for the whole sequence, not one per commit: a --step review
# of dozens of commits has to stay instant to navigate (FR-014/SC-008), and on
# Windows, where fork() is emulated, 2N processes is the difference between
# instant and perceptible (research.md Decisión 2). The traversal flags are the
# same ones load_step_review_meta uses for `commits`, which is what makes the
# three lists line up.
#
# Lining up by line number is safe because neither format can emit an inner
# newline: %s is the first line of the message by definition, and git strips the
# newline out of the ident when it builds the commit (research.md Decisión 1,
# measured). If that ever stopped holding, the symptom would be a subject paired
# with the wrong commit, silently.
#
# Relies on the globals set by load_step_review_meta (start, tip); call it after,
# never instead of it. The step verbs that only move the cursor do not call it:
# they have no use for the text and should not pay the two extra processes.
#
# Both lists keep their trailing newline, so each holds exactly one line per
# commit and the caller can stream them with `while read` instead of indexing
# line by line. That matters: command substitution strips trailing newlines, and
# a last commit with an EMPTY subject would otherwise shorten the list and drop
# its record — which a consumer reads as "this CLI has no subjects" rather than
# "this commit has none" (FR-004). Appending an x and stripping it back off with
# ${var%x} is the usual idiom for holding on to those newlines.
load_step_texts() {
	# shellcheck disable=SC2034  # both are globals for the caller (status), like
	# the ones load_step_review_meta sets; nothing in this file consumes them.
	subjects="$(git log --reverse --first-parent --no-merges --format=%s "$start..$tip"; printf x)"
	subjects="${subjects%x}"
	# shellcheck disable=SC2034  # idem.
	authors="$(git log --reverse --first-parent --no-merges --format='%an <%ae>' "$start..$tip"; printf x)"
	authors="${authors%x}"
}

# goto_step <target>
# Move a --step review to step <target>: bank the current commit's edits, reset
# clean to the target commit, restore the target's previously banked edits (if
# any), then soft-reset so its diff is staged. Relies on the globals set by
# load_step_review_meta (cur, src, count, step, commits). On apply failure the
# working tree is rolled back to the step we left (cursor unchanged) so the
# session is not left half-moved on the target with the origin already banked.
goto_step() {
	target="$1"
	prev_step="$step"
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
		# No --3way here: it implies --index and would leave banked edits staged,
		# so git diff (unstaged) goes empty and the step UI/tests lose the edit.
		# Temp-file apply still keeps binary hunks intact.
		if ! apply_review_patch "${ref}^" "$ref"; then
			echo "error: could not restore banked edits for step $target" >&2
			# Roll back: hard-reset to the origin step and re-apply its bank.
			git reset -q --hard "$cstep"
			pref="refs/review-edits/$src/$prev_step"
			if git rev-parse --verify --quiet "$pref" >/dev/null; then
				apply_review_patch "${pref}^" "$pref" || true
			fi
			git reset -q --soft "$cstep^"
			exit 1
		fi
	fi
	git reset -q --soft "$ctarget^"
	git config "branch.$cur.reviewstep" "$target"
	show_commit "$ctarget" "$target" "$count"
}

# ── Walkthrough (walk) mode helpers ───────────────────────────────────────────
#
# A walkthrough is a curated reading order over a PR, authored as a committed
# sidecar (.review/walkthrough.md) and consumed by the reviewer. Walk mode is the
# same whole-PR review (the diff is staged and editable), plus a reading cursor
# over it. Nothing here stages, resets or banks anything — the working tree is the
# whole PR throughout, exactly as in whole mode; only a cursor config key moves.

# resolve_lower_bound <start> <baseref> <tip>
# Same fold decision as fold_lower, but never creates a commit: prints <start>
# (a commit) when nothing needs folding, or the merge-tree tree OID when base
# content must be folded into the lower bound. Read-only probes (config
# --porcelain offers) use this so they do not leave dangling commit-tree objects
# in the object DB. git diff / walk_sequence accept a tree OID as either side.
resolve_lower_bound() {
	_rlb_start="$1"
	_rlb_baseref="$2"
	_rlb_tip="$3"
	_rlb_lower="$_rlb_start"
	if [ -n "$_rlb_baseref" ]; then
		_rlb_mb="$(git merge-base "$_rlb_baseref" "$_rlb_tip" 2>/dev/null || true)"
		if [ -n "$_rlb_mb" ] && [ "$_rlb_mb" != "$_rlb_tip" ] &&
			! git merge-base --is-ancestor "$_rlb_mb" "$_rlb_start"; then
			if _rlb_tree="$(git merge-tree --write-tree "$_rlb_start" "$_rlb_mb" 2>/dev/null)"; then
				_rlb_lower="$_rlb_tree"
			else
				echo "note: could not exclude merged base content from the review diff" >&2
			fi
		fi
	fi
	printf '%s\n' "$_rlb_lower"
}

# fold_lower <start> <baseref> <tip>
# Compute a review's lower bound (exclusive). Normally it is <start>, but if the
# base branch was merged into the PR, fold that already-merged base content into
# the lower bound so base-derived changes are not shown as part of the review.
# Prints the resulting commit-ish. When folding is needed, materializes a real
# commit (commit-tree) so start can soft-reset onto it. A no-op (prints <start>)
# when there is nothing to fold, when <baseref> is empty, or on a git without
# merge-tree. Shared by start and walkthrough init/build.
fold_lower() {
	_fl_start="$1"
	_fl_baseref="$2"
	_fl_tip="$3"
	_fl_bound="$(resolve_lower_bound "$_fl_start" "$_fl_baseref" "$_fl_tip")"
	if [ "$_fl_bound" != "$_fl_start" ]; then
		_fl_lower="$(git commit-tree "$_fl_bound" -p "$_fl_start" -m 'review lower bound')"
	else
		_fl_lower="$_fl_start"
	fi
	printf '%s\n' "$_fl_lower"
}

# changed_paths <lower> <tip>
# The paths a review range changes, one per line, verbatim — the git side of every
# path comparison in this project (a walkthrough's entries, the drift check, the
# uncovered-files note). core.quotePath=false is the whole point of the helper:
# with git's default, any path holding a non-ASCII byte comes out escaped and
# quoted ("src/caf\303\251.js") while the same path written in a walkthrough is
# literal, so the two never compare equal. The walkthrough entry then drops out of
# the reading order in silence, and build reports the same file as both missing
# and extra. Same shape as a CRLF sidecar (see walk_normalize), except it hides
# from anyone whose repo is ASCII-only rather than from anyone on Windows.
# A path holding a '"' or a '\' is still quoted, with quotePath off or on; both
# are illegal on Windows and vanishingly rare elsewhere, and unquoting them here
# would mean re-implementing git's C escaping in awk.
changed_paths() {
	git -c core.quotePath=false diff --name-only "$1" "$2"
}

# range_files <tip> <lower>
# The files a review's range touches, in git's own order — the same
# changed_paths(lower, tip) call every other reader of "what does this review
# touch" already makes (walk_reading_order below, and the degraded-walkthrough
# notes in start and compare), wrapped so the argument order is not repeated
# and inverted at each call site. whole mode's file listing is this and nothing
# more: HEAD sits at the lower bound in every mode (git reset --soft in start),
# so this is the same pair of endpoints walk already reads.
#
# 2>/dev/null || true, folded in here rather than left to each caller: a range
# that will not diff (an unresolvable bound, reachable from start/compare
# before the review's tip is fixed) yields no paths, so no entry intersects and
# the caller degrades — it must never abort the review under set -eu.
range_files() {
	changed_paths "$2" "$1" 2>/dev/null || true
}

# commit_files <sha>
# Paths a single commit touches, one per line, in git's own order — the step-mode
# inventory of "what does this commit change". Name-only (no status letter, no
# patch): clients open each file's diff themselves; status only needs the list
# to draw the panel. Same path rules as changed_paths (core.quotePath=false).
# --root so an empty-tree parent still lists the commit; 2>/dev/null || true so a
# bad/unresolvable SHA yields zero paths under set -eu instead of aborting.
commit_files() {
	git -c core.quotePath=false diff-tree --no-commit-id --name-only -r --root "$1" 2>/dev/null || true
}

# walk_normalize  (stdin: text)
# Make an authored walkthrough's bytes comparable, whatever wrote it. Every reader
# below matches on whole lines — the path in "## N. <path>", the "> key" marker,
# the entry body looked up by path — so an invisible byte at either end of a line
# makes a path differ from git's, no entry intersects the range, and the reviewer
# silently loses walk mode. Two such bytes exist, both of them things a Windows
# editor adds on its own:
#
#   * a line-final carriage return (CRLF endings, an author with core.autocrlf on).
#     Only the line-final CR goes; a CR mid-line is content and stays. It bites
#     only on Linux/macOS, because the MSYS awk swallows the CR — exactly the case
#     a Windows author cannot see.
#   * a UTF-8 BOM on the first line (Notepad, PowerShell Out-File and > all write
#     one by default). It hides the "# Walkthrough" heading from walk_preamble,
#     which then prints it as if it were the author's heads-up and build bakes the
#     duplicate into the file; on a walkthrough that opens straight with an entry
#     it hides that entry from walk_parse outright.
#
# The BOM is matched as a string rather than a regex escape because \357\273\277 is
# not portable across the three awks in CI; index/substr/length agree with each
# other whether the awk counts bytes or characters, so this works in either.
walk_normalize() {
	awk -v bom="$(printf '\357\273\277')" '
		NR == 1 && index($0, bom) == 1 { $0 = substr($0, length(bom) + 1) }
		{ sub(/\r$/, ""); print }
	'
}

# walk_gitdir_init
# Resolve the working tree's gitdir once for the life of the process, into
# _walk_gitdir. Every draft path below derives from it.
#
# It has to be resolved in the caller's own shell, not lazily inside the path
# helpers: those are called as "$(walk_draft_path ...)", and an assignment made
# inside a command substitution dies with its subshell, so a cache written there
# would never be read and every walk_read would pay another git process. That is
# not hypothetical — walk_read consults the draft on every read, so a plain
# status in walk mode called this four times, on the path whose process count the
# panel's latency is measured in.
#
# walk_use_draft calls this, which covers every verb with an active review; the
# verbs that build a draft path without setting a draft context (list, save,
# continue, forget) call it themselves.
#
# Caching is safe because no verb in this suite ever changes directory: the value
# may be relative (".git", from the top level of the work tree), which a chdir
# would silently invalidate.
walk_gitdir_init() {
	[ -n "${_walk_gitdir:-}" ] || _walk_gitdir="$(git rev-parse --git-dir)"
}

# walk_draft_path <src>
# Where the reviewer's own walkthrough for <src> lives while it is in play.
#
# Inside the working tree's gitdir, deliberately: it is a real file any editor or
# agent can open and save, it never shows up in git status, start never sees a
# dirty tree because of it, and finish cannot carry it into review-fixes/ — the
# three walls that made a reviewer-written walkthrough impossible. Same idiom git
# uses for COMMIT_EDITMSG and MERGE_MSG. A branch name holding '/' becomes a
# subdirectory, exactly as it does under refs/; callers that write must mkdir -p.
#
# --git-dir (not --git-common-dir) so each git worktree keeps its own draft: a
# review is per working tree, and so is its reading order.
walk_draft_path() {
	walk_gitdir_init
	printf '%s/review-walkthrough/%s.md' "$_walk_gitdir" "$1"
}

# walk_saved_draft_path <src>
# The same draft once git review save has put it aside with the paused review.
# Mirrors refs/review-saved-edits/ exactly: paused work travels with the review
# it belongs to, and the reviewer learns one rule instead of two.
walk_saved_draft_path() {
	walk_gitdir_init
	printf '%s/review-saved-walkthrough/%s.md' "$_walk_gitdir" "$1"
}

# walk_draft_list
# Every draft in the active namespace, as its <src> (a branch name), one per
# line. Nothing at all when the namespace does not exist. Used by
# git review forget --draft --all, the one command that has to enumerate them.
#
# Recursion over globs rather than find: a branch name holding '/' is a
# subdirectory here, so a single-level glob would miss every namespaced branch,
# and find(1) has no other user in this suite — its -empty/-delete are outside
# POSIX, and under Git Bash a stray PATH resolves it to Windows' own find.exe.
walk_draft_list() {
	walk_gitdir_init
	_wdl_root="$_walk_gitdir/review-walkthrough"
	[ -d "$_wdl_root" ] || return 0
	_walk_draft_list_dir "$_wdl_root" ""
}

# walk_saved_draft_list
# The same enumeration over the archived namespace, as <src> names. Its only
# caller is forget --draft --all, and only for the ones no paused review claims:
# an archive entry normally belongs to a review-saved/<src> branch and is returned
# by git review continue, but the branch can be deleted by hand, and then the file
# it left behind was reachable from nothing — forget --saved refused without the
# ref, forget --draft --all looked only at the active namespace, and clean is
# hands-off in there by design.
walk_saved_draft_list() {
	walk_gitdir_init
	_wdl_root="$_walk_gitdir/review-saved-walkthrough"
	[ -d "$_wdl_root" ] || return 0
	_walk_draft_list_dir "$_wdl_root" ""
}

# _walk_draft_list_dir <dir> <prefix>  (walk_draft_list's recursion)
# The loop variables are reused by the nested call on purpose: each is reassigned
# at the top of every iteration and never read across the recursive call, while
# <dir>/<prefix> are positional parameters, which each call frame keeps its own.
_walk_draft_list_dir() {
	for _wdl_entry in "$1"/*; do
		# An unmatched glob stays literal in POSIX sh; -e is what tells the two
		# apart, and it also skips a dangling symlink.
		[ -e "$_wdl_entry" ] || continue
		_wdl_name="${_wdl_entry##*/}"
		if [ -d "$_wdl_entry" ]; then
			_walk_draft_list_dir "$_wdl_entry" "$2$_wdl_name/"
		elif [ -f "$_wdl_entry" ]; then
			case "$_wdl_name" in
			*.md) printf '%s%s\n' "$2" "${_wdl_name%.md}" ;;
			esac
		fi
	done
}

# walk_use_draft <src>
# Point the walkthrough readers at <src>'s local draft, if it has one.
#
# The context travels in a variable rather than as an argument because walk_read
# takes a commit-ish, not a branch, and neither do the eleven readers stacked on
# top of it — threading a second parameter would mean changing every one of those
# signatures and their call sites. load_walk_review_meta and load_step_review_meta
# call this themselves, so every verb with an active review inherits the context
# without touching it; only the readers that resolve a source outside a review
# (start, compare, emit_reading_offers, walkthrough draft) call it directly.
walk_use_draft() {
	walk_draft_src="$1"
	# Here rather than in walk_draft_path: this runs in the verb's own shell,
	# where the resolved gitdir survives to be reused (see walk_gitdir_init).
	walk_gitdir_init
}

# walk_review_draft_src <review-branch>
# The name the draft of the review on <review-branch> lives under, as recorded by
# the verb that created the review (branch.<rb>.reviewdraft).
#
# The name is *recorded*, never re-derived, and this is the only function that
# reads it — the point being that one review cannot have two names for its own
# draft. It is not always the review's source: a compare of a remote-tracking
# branch reviews "origin/feature/x" and drafts for "feature/x", because the draft
# belongs to the branch, not to the ref you happened to name it by. When both a
# creator and a reader derived that separately, they disagreed — the draft was
# written under one name and looked up under the other, so a later git review
# start read the author's order and reported no draft at all, over prose the
# reviewer had just written.
#
# The source is the fallback for reviews created before the key existed; for
# those, deriving it is what the readers did anyway, so they keep behaving
# exactly as they did.
walk_review_draft_src() {
	_wrds_name="$(git config "branch.$1.reviewdraft" || true)"
	if [ -z "$_wrds_name" ]; then
		_wrds_name="$(git config "branch.$1.reviewsource" || true)"
	fi
	printf '%s' "$_wrds_name"
}

# walk_saved_draft_claims
# Every paused review that owns an archived draft, as "<src><TAB><review-branch>",
# one per line. The <src> is the name the review recorded, which is the name its
# draft is filed under in review-saved-walkthrough/.
#
# It exists because that name and the branch's own are not the same string: a
# compare of a remote-tracking branch is paused as review-saved/origin/feature/x
# and its draft is feature/x's. Asking "is there a refs/heads/review-saved/<file
# name>?" therefore answers no for exactly those reviews, and the two callers here
# both act destructively on that answer — forget --draft --all swept the archived
# draft of a live paused review, announcing that no paused review was left to
# restore it, and save overwrote it. Ask each paused review what it claims instead;
# it is the same question walk_review_draft_src answers everywhere else.
walk_saved_draft_claims() {
	git for-each-ref --format='%(refname:short)' refs/heads/review-saved/ |
		while IFS= read -r _wsc_rb; do
			[ -n "$_wsc_rb" ] || continue
			_wsc_name="$(walk_review_draft_src "$_wsc_rb")"
			[ -n "$_wsc_name" ] || continue
			printf '%s\t%s\n' "$_wsc_name" "$_wsc_rb"
		done
}

# walk_draft_body <src>
# Print <src>'s draft, normalised, or nothing (non-zero rc) when <src> has no
# draft in force. "In force" and "the file exists" are not the same thing: a draft
# that is empty, or holds nothing but whitespace, has no reading order in it and
# must behave exactly as an absent one. It used to be answered by the file test
# alone, and an empty file then shadowed the author's walkthrough while telling
# every caller a walkthrough existed — start landed in whole with no note at all,
# and --keys reported the PR carried none, on a PR that carried one.
#
# The single place that rule is written down, so that walk_read's precedence and
# walk_is_draft's badge cannot drift apart and disagree about the same file.
#
# -s before reading: zero bytes is the ordinary shape of this (an editor opened
# and closed, a redirect, an interrupted write), and ruling it out costs nothing.
walk_draft_body() {
	_wdb_path="$(walk_draft_path "$1")"
	[ -f "$_wdb_path" ] || return 1
	[ -s "$_wdb_path" ] || return 1
	# Redirection, not git show: one process fewer than the sidecar path below.
	_wdb_body="$(walk_normalize <"$_wdb_path")"
	case "$_wdb_body" in
	*[![:space:]]*)
		printf '%s\n' "$_wdb_body"
		return 0
		;;
	esac
	return 1
}

# walk_is_draft <src>
# True when <src>'s review is reading the reviewer's own draft rather than the
# author's committed walkthrough — the question behind the "(draft)" suffix in
# status and the draft record in status --porcelain.
#
# Answered by walk_draft_body, which is to say by the same rule walk_read applies
# when it picks one over the other. It costs the one process that reads the file
# where it used to be a bare file test; the alternative was a status line that
# said "walk (draft)" over the author's prose, which is the confusion the suffix
# exists to prevent. list and the start assistant deliberately keep asking the
# cheaper question — for them a draft file that exists is a draft they are
# responsible for, empty or not, because they report custody, not what is being
# read.
walk_is_draft() {
	walk_draft_body "$1" >/dev/null
}

# walk_has_draft_file <src>
# Whether a draft file exists for <src> at all — custody, not what is being read.
# The two questions came apart the moment an empty draft stopped counting as a
# reading order: list has to badge a file it is responsible for handing to
# forget --saved, the start assistant has to offer to reopen one, and start has to
# be able to say "yours is empty" about a file walk_is_draft now denies. A file
# test and no process of its own, which is what keeps it usable on those paths.
walk_has_draft_file() {
	[ -f "$(walk_draft_path "$1")" ]
}

# walk_read <tip>
# Print the walkthrough in force, or nothing (non-zero rc) if there is none.
# Never aborts the caller: used in conditions and command substitutions.
#
# Precedence: the reviewer's own draft for the source branch first, the
# walkthrough committed at <tip> second. This is the single point where
# walkthrough content enters the readers — which is why line-ending
# normalisation lives here, and why putting precedence here means next, prev,
# status --why, compare, --keys and the panel all read a draft with no change of
# their own. A draft is only consulted when a caller has named the source with
# walk_use_draft; unset, this behaves exactly as it always did, which is what
# keeps the author's flow untouched.
walk_read() {
	if [ -n "${walk_draft_src:-}" ] && _wr_body="$(walk_draft_body "$walk_draft_src")"; then
		printf '%s\n' "$_wr_body"
		return 0
	fi
	_wr_content="$(git show "$1:.review/walkthrough.md" 2>/dev/null)" || return 1
	printf '%s' "$_wr_content" | walk_normalize
}

# walk_parse  (stdin: walkthrough content)
# Emit one "order<TAB>path" line per numbered entry ("## N. path"), in file order.
# The intro heading ("# Walkthrough"), skeleton entries ("## ?. path") and any
# other line are ignored. Leniency is deliberate: at runtime the file was already
# validated by "git review walkthrough build", and a stray line must degrade the
# review, never crash it.
#
# Trailing whitespace is trimmed off the path for the same reason walk_normalize
# drops the CR: one space typed after the filename is invisible in every editor
# and makes the entry compare unequal to git's path — the entry vanishes from the
# reading order, or build names the identical file on both sides of a drift error.
# It costs the ability to annotate a file whose name really ends in a space (legal
# on Linux, unwritable on Windows); the same trade walk_normalize already makes
# for a name ending in a CR.
walk_parse() {
	awk '
		/^## / {
			line = $0
			sub(/^## /, "", line)
			if (match(line, /^[0-9]+\. /)) {
				ord = substr(line, 1, RLENGTH - 2)
				path = substr(line, RLENGTH + 1)
				sub(/[ \t]+$/, "", path)
				# A heading with a number but no path ("## 1. ") is not an entry;
				# emitting it would put an empty path into the drift comparison.
				if (path != "") printf "%s\t%s\n", ord, path
			}
		}
	'
}

# walk_body <path>  (stdin: walkthrough content)
# Print the body of the entry whose path is <path> verbatim — every line after
# its "## N. <path>" (or "## ?. <path>") header, up to the next "## " header or
# EOF. Empty when the path has no entry. The header's path is trimmed exactly as
# walk_parse trims it, so a <path> that came from walk_parse still finds its body.
walk_body() {
	awk -v want="$1" '
		/^## / {
			line = $0
			sub(/^## /, "", line)
			if (sub(/^[0-9]+\. /, "", line) || sub(/^\?\. /, "", line)) {
				sub(/[ \t]+$/, "", line)
				cur = (line == want)
			} else {
				cur = 0
			}
			next
		}
		cur { print }
	'
}

# walk_preamble  (stdin: walkthrough content)
# Print the author's preamble: everything between the "# Walkthrough" heading and
# the first entry, with HTML comments stripped and leading/trailing blank lines
# trimmed. This is where the "## Heads-up" note lives — what is delicate in this
# PR, read before the first file. Comments are dropped because the init skeleton
# writes its instructions as one, and those are scaffolding, not content. Prints
# nothing when what remains is empty or headings only (an author who deleted the
# placeholder without writing anything leaves a bare "## Heads-up" behind).
walk_preamble() {
	awk '
		/^## / {
			line = $0
			sub(/^## /, "", line)
			if (line ~ /^([0-9]+|\?)\. /) exit
		}
		{
			if (skip) { if (index($0, "-->")) skip = 0; next }
			if (index($0, "<!--")) { if (index($0, "-->") == 0) skip = 1; next }
			if ($0 ~ /^# /) next
			buf[++n] = $0
			if ($0 !~ /^#/ && $0 !~ /^[ \t]*$/) prose = 1
		}
		END {
			if (!prose) exit
			s = 1; while (s <= n && buf[s] ~ /^[ \t]*$/) s++
			e = n; while (e >= s && buf[e] ~ /^[ \t]*$/) e--
			for (k = s; k <= e; k++) print buf[k]
		}
	'
}

# walk_is_key <tip> <path>
# True when the entry for <path> carries the reserved "> key" marker: the author
# flagging it as one of the few files that carry the change, the ones a reviewer
# must not skim. Absence is the default — the marker only means something while
# it stays selective, so it is never written on every entry.
walk_is_key() {
	walk_read "$1" | walk_body "$2" | grep -q '^> key[[:space:]]*$'
}

# walk_count_keys <tip>  (stdin: paths, one per line)
# How many of the given entries carry the "> key" marker. A count over
# walk_entry_fields' essential column rather than its own marker parsing: one
# definition of what "> key" means, and a constant number of processes for a
# reading order of any length (see the note there). Always prints a number —
# `n + 0` so an empty path list is 0, not the empty string a bare `print n`
# would give and a caller would then compare numerically under set -eu.
walk_count_keys() {
	walk_entry_fields "$1" | awk -F'\t' '$3 == "1" { n++ } END { print n + 0 }'
}

# walk_is_annotated <tip> <path>
# True when <path> has an entry in the walkthrough at <tip> — regardless of
# whether that entry's path is in range. Used to tell a curated entry apart
# from a file the reading order only carries because it changed in the review
# range (see walk_reading_order). Goes through the same two normalization
# points as every other path comparison here: walk_normalize via walk_read,
# the trim in walk_parse.
walk_is_annotated() {
	walk_read "$1" | walk_parse | cut -f2- | grep -Fxq "$2"
}

# walk_entry_fields <tip>  (stdin: paths, one per line, in order)
# Emit "position<TAB>path<TAB>essential<TAB>annotated" for each path on stdin,
# 1-based position in the order given, essential 1/0 for the "> key" marker,
# annotated 1/0 for whether the path has a walkthrough entry at all (0 for a
# file walk_reading_order appended because it has none). Fields only, not a
# porcelain line: the caller passes each field through porcelain_row. This is
# also the one place that decides those two flags — walk_count_keys and
# walk_keys_order are filters over this output rather than three near-copies of
# the same marker parsing.
#
# ONE awk for the whole list, not one process per path. Reading the walkthrough
# once (a single git show) was never the expensive part: the loop this replaced
# spawned a walk_body awk plus two greps per entry, so a 184-entry reading order
# cost ~900 processes and 27s under Git Bash on Windows, where fork() is
# emulated — enough for the VS Code panel to hit its 15s read timeout on every
# refresh. That is the actual O(1)-per-invocation goal of the porcelain
# contract; one git show with an O(N) loop around it does not meet it.
#
# The two streams go into that single awk back to back and are told apart by a
# sentinel line holding one tab, with the PATHS FIRST: a path can never be a
# lone tab (git quotes control characters unconditionally, the same property
# walk_sequence relies on to tell its two streams apart), whereas a walkthrough
# body is arbitrary prose that may well contain a tab-only line. Feeding the
# content first and the paths second would let the author's own text end the
# first phase early. The paths are buffered and printed at END so the caller's
# order — the reading order — survives, and so a path that appears twice gets
# the same flags both times.
#
# The content cannot travel as `awk -v` either, for two independent reasons: -v
# processes escape sequences, so a why containing a literal \n or \t would be
# silently rewritten, and BSD awk refuses a -v value containing a newline
# outright (see walk_reading_order). Anything arbitrary goes in as a stream.
walk_entry_fields() {
	_we_content="$(walk_read "$1" || true)"
	{
		cat
		printf '\t\n'
		printf '%s\n' "$_we_content"
	} | awk '
		# Phase 1: the caller path list, up to the lone-tab sentinel.
		!tail {
			if ($0 == "\t") { tail = 1; next }
			if ($0 != "") { n++; p[n] = $0 }
			next
		}
		# Phase 2: the walkthrough. Entry headers are recognised exactly as
		# walk_body does it (numbered AND skeleton "?." entries carry a body),
		# while "annotated" follows walk_parse instead (numbered entries only,
		# empty path skipped) — the two differ on purpose and the flags must
		# keep differing the same way. A "## " heading that is not an entry
		# (## Heads-up) closes the current body, as it does there.
		/^## / {
			line = substr($0, 4)
			if (sub(/^[0-9]+\. /, "", line)) {
				sub(/[ \t]+$/, "", line)
				cur = line
				if (line != "") ann[line] = 1
			} else if (sub(/^\?\. /, "", line)) {
				sub(/[ \t]+$/, "", line)
				cur = line
			} else {
				cur = ""
			}
			next
		}
		cur != "" && /^> key[[:space:]]*$/ { key[cur] = 1 }
		END {
			for (i = 1; i <= n; i++)
				printf "%s\t%s\t%s\t%s\n", i, p[i], \
					(p[i] in key) ? 1 : 0, (p[i] in ann) ? 1 : 0
		}
	'
}

# walk_why <tip> <path>
# The "why" prose a reviewer sees for <path>: the entry body from the walkthrough
# at <tip>, with the reserved marker lines ("> key", and the "> at:" anchor of v2)
# dropped and leading/trailing blank lines trimmed.
walk_why() {
	walk_read "$1" | walk_body "$2" |
		grep -v -e '^> at: ' -e '^> key[[:space:]]*$' | awk '
		{ buf[NR] = $0 }
		END {
			s = 1; while (s <= NR && buf[s] ~ /^[ \t]*$/) s++
			e = NR; while (e >= s && buf[e] ~ /^[ \t]*$/) e--
			for (i = s; i <= e; i++) print buf[i]
		}
	'
}

# walk_sequence <tip> <lower>
# Derive the ordered, range-filtered reading sequence for a review whose tip is
# <tip> and lower bound is <lower>: parse the walkthrough at <tip>, keep only
# entries whose path is actually in the review range (changed_paths <lower>
# <tip>), order them by the author's number and print the paths, one per line, in
# reading order. Empty output means no walkthrough, or none of its entries
# intersect the range — callers degrade to a plain whole review.
#
# The two sides are fed to one awk as a single stream, range first, and told apart
# by the tab that walk_parse puts in front of every entry path: git quotes control
# characters in a path unconditionally, so a line from changed_paths can never
# hold a literal tab. That is what lets this run without the scratch file it used
# to need — one less thing to leave behind in .git when a step fails under set -e.
walk_sequence() {
	_ws_content="$(walk_read "$1")" || return 0
	[ -n "$_ws_content" ] || return 0
	{
		# A range that will not diff (an unresolvable bound) yields no paths, so no
		# entry intersects and the caller degrades — it never aborts the review.
		changed_paths "$2" "$1" 2>/dev/null || true
		printf '%s\n' "$_ws_content" | walk_parse
	} | awk '
		{
			tab = index($0, "\t")
			if (tab == 0) { inrange[$0] = 1; next }
			ord = substr($0, 1, tab - 1) + 0
			path = substr($0, tab + 1)
			if (path in inrange) printf "%s\t%s\n", ord, path
		}
	' | LC_ALL=C sort -k1,1n | cut -f2-
}

# walk_reading_order <tip> <lower>
# The full reading order for a walk review: the curated sequence from
# walk_sequence, followed by any file range_files reports in range but that has
# no walkthrough entry — including the sidecar itself, if the PR touches it: a
# committed walkthrough is content the PR adds like any other file, and it used
# to be the one file no review ever showed a reviewer (the sole exception left
# is the walkthrough's own entry proposal in git-review-verbs/walkthrough,
# which still filters it — annotating the file where you write your annotations
# would be circular). In the order git reports them. Empty output means
# walk_sequence is empty — no curated entry intersects the range — and the
# caller degrades to whole, exactly as before: this function only ever adds a
# tail to a non-empty curated sequence, never turns an empty one into something
# walk mode would run on.
#
# Built on top of walk_sequence rather than duplicating its awk: one git show
# and one git diff live there, and this adds one more diff plus a single awk pass
# over range paths (set membership of the curated sequence — not one grep
# process per path).
walk_reading_order() {
	_wro_seq="$(walk_sequence "$1" "$2")"
	[ -n "$_wro_seq" ] || return 0
	printf '%s\n' "$_wro_seq"
	# One awk: load curated paths into a set, emit range paths not in it (git order).
	#
	# The sequence arrives as a stream, not as `awk -v`: BSD awk (the one true
	# awk, which is what macOS ships) refuses a newline inside a -v value —
	# "awk: newline in string <value>... at source line 1", exit 2 — while
	# gawk and mawk accept it. A multi-line -v therefore aborts every walk
	# review on macOS and nowhere else. Same two-stream, lone-tab-sentinel
	# shape as walk_entry_fields, and safe for the same reason: git quotes
	# control characters in a path unconditionally, so neither stream can
	# produce a line that is just a tab.
	{
		printf '%s\n' "$_wro_seq"
		printf '\t\n'
		range_files "$1" "$2"
	} | awk '
		# Phase 1: the curated sequence, up to the lone-tab sentinel.
		!tail {
			if ($0 == "\t") { tail = 1; next }
			if ($0 != "") seen[$0] = 1
			next
		}
		$0 != "" && !($0 in seen) { print }
	'
}

# walk_keys_order <tip> <lower>
# Curated walk_sequence paths that carry the reserved "> key" marker, in
# walkthrough order. Uncovered paths never appear — walk_sequence only yields
# curated entries, so the annotated column is 1 throughout and filtering on
# essential alone is enough. A filter over walk_entry_fields for the same reason
# walk_count_keys is one: a single definition of the "> key" marker, and a
# constant number of processes for a reading order of any length. Empty output
# means no essential entry intersects the range — callers that asked for --keys
# fail before opening a review rather than materializing an empty sequence.
walk_keys_order() {
	walk_sequence "$1" "$2" | walk_entry_fields "$1" |
		awk -F'\t' '$3 == "1" { print $2 }'
}

# emit_reading_offers <branch> <remote> <source_mode> <delta>
# Print offer rows for config --porcelain (008-start-layout-offers). source_mode
# is remote|local|offline; delta is 0|1. Never fetches. Dies on unresolvable tip
# or on --delta without a marker for that origin. Lower bound mirrors start
# (merge-base / previous tip + fold_lower) without creating a review branch.
emit_reading_offers() {
	_ero_branch="$1"
	_ero_remote="$2"
	_ero_source="$3"
	_ero_delta="$4"

	_ero_base="$(git config reviewworkflow.base || true)"
	_ero_offline=0
	_ero_local=0
	case "$_ero_source" in
	offline) _ero_offline=1; _ero_local=1 ;;
	local) _ero_local=1 ;;
	remote) ;;
	*)
		echo "error: internal: unknown offer source $_ero_source" >&2
		return 1
		;;
	esac

	if [ "$_ero_local" -eq 1 ]; then
		_ero_srcref="refs/heads/$_ero_branch"
		_ero_srclabel="$_ero_branch"
		_ero_markerkey="reviewworkflowlocal.$_ero_branch.reviewed"
	else
		_ero_srcref="refs/remotes/$_ero_remote/$_ero_branch"
		_ero_srclabel="$_ero_remote/$_ero_branch"
		_ero_markerkey="reviewworkflow.$_ero_branch.reviewed"
	fi

	# Tip missing: hard error for every origin (remote default, local, offline,
	# delta). Soft-skip used to return 0 with zero offer rows for a missing
	# remote tracking ref; that looks like a pre-008 CLI to consumers
	# (synthetic whole+step fallback) instead of "no remote tip". Local-only
	# branches must use --local.
	if ! git rev-parse --verify --quiet "$_ero_srcref^{commit}" >/dev/null; then
		echo "error: $_ero_srclabel not found" >&2
		return 1
	fi
	_ero_tip="$(git rev-parse "$_ero_srcref")"

	_ero_baseref=""
	if [ -n "$_ero_base" ]; then
		if [ "$_ero_offline" -eq 1 ]; then
			if git rev-parse --verify --quiet "refs/heads/$_ero_base^{commit}" >/dev/null; then
				_ero_baseref="refs/heads/$_ero_base"
			fi
		else
			if git rev-parse --verify --quiet "refs/remotes/$_ero_remote/$_ero_base^{commit}" >/dev/null; then
				_ero_baseref="refs/remotes/$_ero_remote/$_ero_base"
			fi
		fi
		if [ -z "$_ero_baseref" ]; then
			_ero_bcommit="$(git rev-parse --verify --quiet "$_ero_base^{commit}" || true)"
			if [ -n "$_ero_bcommit" ]; then
				_ero_baseref="$_ero_bcommit"
			fi
		fi
	fi

	_ero_prev="$(git config "$_ero_markerkey" || true)"
	if [ "$_ero_delta" -eq 1 ]; then
		[ -n "$_ero_prev" ] || {
			echo "error: no previous review of $_ero_branch recorded for this origin; run a full review first" >&2
			return 1
		}
		[ "$_ero_prev" != "$_ero_tip" ] || {
			echo "error: no new commits since your last review of $_ero_branch" >&2
			return 1
		}
		git merge-base --is-ancestor "$_ero_prev" "$_ero_tip" || {
			echo "error: $_ero_branch was force-pushed since your last review; run a full review instead" >&2
			return 1
		}
		_ero_start="$_ero_prev"
	else
		# Full range needs a base; without it, skip offers (delta rows may still
		# have been emitted above by the caller). Not a hard error: config
		# porcelain is also used only for candidates/deltas before base is set.
		if [ -z "$_ero_base" ] || [ -z "$_ero_baseref" ]; then
			return 0
		fi
		_ero_start="$(git merge-base "$_ero_baseref" "$_ero_srcref")" || return 0
		[ "$_ero_start" != "$_ero_tip" ] || return 0
	fi

	# Tree-only lower bound: offers must not commit-tree dangling "review lower
	# bound" objects into the DB on every porcelain probe.
	_ero_lower="$(resolve_lower_bound "$_ero_start" "$_ero_baseref" "$_ero_tip")"

	# The reviewer's own draft counts as the walkthrough in force here too, so
	# the offers describe the review that start would actually create.
	walk_use_draft "$_ero_branch"

	_ero_walk=0
	if wtcontent="$(walk_read "$_ero_tip")" && [ -n "$wtcontent" ]; then
		_ero_curated="$(walk_sequence "$_ero_tip" "$_ero_lower")"
		_ero_n="$(printf '%s\n' "$_ero_curated" | grep -c . || true)"
		if [ "$_ero_n" -ge 1 ]; then
			_ero_walk=1
		fi
	fi

	if [ "$_ero_walk" -eq 1 ]; then
		porcelain_row offer walk recommended
		_ero_keys="$(walk_keys_order "$_ero_tip" "$_ero_lower")"
		_ero_kn="$(printf '%s\n' "$_ero_keys" | grep -c . || true)"
		if [ "$_ero_kn" -ge 1 ]; then
			porcelain_row offer keys available
		fi
	fi
	# Drafting the reading order yourself, as a reading offer of its own: the
	# assistant asks "how do you want to read this?" exactly when the reviewer
	# finds out nobody wrote an order, so that is where the answer belongs.
	#
	# Exactly one of the two, and never `draft` on top of a usable walkthrough:
	# replacing the author's order is a deliberate act, available from the
	# terminal, not something the assistant proposes. `draft-resume` *is* offered
	# alongside walk, because that walk is the reviewer's own half-written draft
	# and finishing it is the obvious next move.
	#
	# A file test, no process: walk_use_draft above already resolved the gitdir
	# the path is built from. This runs on every open of the start assistant.
	if walk_has_draft_file "$_ero_branch"; then
		porcelain_row offer draft-resume available
	elif [ "$_ero_walk" -eq 0 ]; then
		porcelain_row offer draft available
	fi
	porcelain_row offer step available
	porcelain_row offer whole available
	return 0
}

# walk_at_base
# True when HEAD still sits where start pinned it, false when it moved, and
# non-zero-with-no-answer when the review predates the key that records it.
#
# Walk mode keeps HEAD at the review's lower bound for the review's whole life, so
# "did the reviewer run git commit?" is a question git can answer outright. It used
# to be inferred instead, from the reading sequence having got shorter — which was
# the only shrinking cause back when every walkthrough was the author's, frozen in
# the tip. A reviewer's draft is a file they are invited to edit, so that inference
# now has two causes and picks the wrong one: editing your own draft told you HEAD
# had moved and to run git reset --soft.
#
# Three states, not two: a review created before reviewwalkbase existed has no
# recorded base, and guessing for it would be the same mistake in the other
# direction. Callers fall back to the old inference there.
walk_at_base() {
	_wab_base="$(git config "branch.$cur.reviewwalkbase" || true)"
	[ -n "$_wab_base" ] || return 2
	[ "$(git rev-parse HEAD)" = "$_wab_base" ]
}

# walk_recover_cursor
# Re-seat a cursor that the reviewer's own draft got shorter under, or fail (and
# leave walk_range_error to explain). True only when all of it holds: the cursor
# ran off the end (not off the front, which no edit can cause), entries remain,
# HEAD is provably still at the base, and the walkthrough in force is a draft that
# still exists.
#
# Clamping rather than erroring, because every one of those conditions says the
# state is intact and the reading position is the only thing that went stale — and
# the position is not precious: the sequence behind it is re-derived on every
# command by design. The alternative was a dead end. There is no verb that moves
# the cursor without loading this metadata first, so an out-of-range cursor made
# next, prev and status all abort with the same message, leaving `git review abort`
# — discard the review — as the only way out of having edited your own prose.
#
# reviewwalkcount moves with it: it is the baseline a later genuine range change is
# measured against, so leaving it at the old value would re-report this shrink for
# the rest of the review.
walk_recover_cursor() {
	[ "$walkstep" -gt "$total" ] || return 1
	[ "$total" -ge 1 ] || return 1
	walk_at_base || return 1
	# walk_draft_src, not the reviewwalkfromdraft flag: the flag is only raised when
	# start/compare open *on* a draft, and the case this function exists for is a
	# draft written mid-review — a review that by definition never had one. Reading
	# the flag here made the recovery unreachable on its own motivating path, the
	# one the recorded name exists to support. Whether that name has a draft in
	# force is the next line's question, so widening this one costs nothing.
	_wrc_draft="${walk_draft_src:-}"
	[ -n "$_wrc_draft" ] || return 1
	walk_is_draft "$_wrc_draft" || return 1

	echo "note: your walkthrough draft for $_wrc_draft now has $total $(entry_noun "$total") in this review's range; the cursor was at $walkstep and moved to $total." >&2
	# Best-effort on purpose: this is the one place the read path writes config, so
	# it also runs from `git review status` — on every panel refresh and every
	# watcher beat. A config write can fail for reasons that have nothing to do with
	# the review: another process holding .git/config.lock (git takes it with no
	# retry and exits 255), a read-only gitdir. None of that is worth killing the
	# command over. The clamp below is already in force for this invocation, the
	# whole thing is idempotent, and the next one re-derives and retries.
	#
	# Not redundant with the caller being an AND-OR list. It is today — POSIX
	# suppresses -e inside a function run as the non-final command of one — but that
	# is an invariant living in another function, and one refactor away from turning
	# a lost lock into an aborted status.
	git config "branch.$cur.reviewwalkstep" "$total" || true
	git config "branch.$cur.reviewwalkcount" "$total" || true
	walkstep="$total"
	walkcount="$total"
	return 0
}

# walk_range_error <walkstep> <total> <walkcount>
# Emit the right diagnostic for a walk cursor that fell outside the live reading
# range, then exit 1. A walk review's tip and its committed walkthrough are frozen,
# so the derived sequence only shrinks when HEAD moves off the review's base —
# almost always a stray `git commit` that folded the staged whole-PR diff into HEAD.
# When the live <total> dropped below the <walkcount> recorded at start, name that
# recoverable cause and its fix, instead of blaming "corrupt metadata" for a
# self-inflicted, undoable state. A cursor out of range while the range is intact
# (total still == walkcount, or a non-numeric/absent walkcount) is genuine
# corruption — a hand-edited key — and keeps the original diagnostic.
#
# The reviewer's draft adds two causes that are neither, and each gets its own
# message: the draft is gone (deleted or emptied), and the draft is there but
# contributes no entry to this range. Both are states of a file the reviewer owns
# and can fix in place, so both name the command that fixes it. "Corrupt
# metadata" is the last resort, not the catch-all.
walk_range_error() {
	_wre_step="$1"
	_wre_total="$2"
	_wre_count="$3"
	case "$_wre_count" in
	'' | *[!0-9]*) _wre_count=0 ;;
	esac
	# A reviewer's draft, unlike a committed walkthrough, can be deleted out from
	# under a live review — its tip is frozen, the draft is a file. When that
	# happens the sequence changes shape under the cursor exactly as it does after
	# a stray commit, and without this the reviewer gets told HEAD moved and to run
	# git reset --soft, which is both wrong and destructive-sounding. Name the real
	# cause instead.
	#
	# Decided on whether this review's reading order came from the draft
	# (reviewwalkfromdraft, recorded at creation), not on "there is no walkthrough
	# left": when the PR carries one of its own, deleting the draft makes the
	# review fall back to the author's order, so walk_read still succeeds and the
	# range can still have collapsed — the exact case that got the HEAD message
	# wrong. A flag and not the name, because the name is recorded separately and
	# unconditionally (walk_review_draft_src): whether a draft *was* being read is
	# the one thing that cannot be recomputed once the file is gone. The old
	# total==0 test stays as the fallback for a review started before the flag.
	_wre_draft=""
	if [ "$(git config "branch.$cur.reviewwalkfromdraft" || true)" = "1" ]; then
		_wre_draft="${walk_draft_src:-$src}"
	elif [ -n "${walk_draft_src:-}" ] && walk_is_draft "$walk_draft_src"; then
		# A draft written mid-review carries no flag: at creation there was nothing
		# to record. It is adopted from the context the loader resolved instead —
		# but only once walk_is_draft confirms a draft is actually in force. That
		# confirmation is the whole of it: walk_draft_src falls back to the review's
		# own source name, so taking it unconditionally would make every draft-less
		# walk review look like one whose draft went missing, and answer a stray
		# commit with "your draft is gone" instead of the HEAD message below.
		_wre_draft="$walk_draft_src"
	fi
	_wre_gone=0
	if [ -n "$_wre_draft" ]; then
		if ! walk_is_draft "$_wre_draft"; then
			_wre_gone=1
		fi
	elif [ "$_wre_total" -eq 0 ] && ! walk_read "$tip" >/dev/null 2>&1; then
		_wre_draft="$src"
		_wre_gone=1
	fi
	if [ "$_wre_gone" -eq 1 ]; then
		# Deleted and emptied are the same thing to walk_read and two different
		# things to the reviewer, who most likely has the file open. Reported with
		# walk_has_draft_file — the custody question — precisely because
		# walk_is_draft just answered the other one. It also decides the fix: the
		# draft verb refuses to overwrite a file that exists, so telling someone
		# with an empty draft to "write it again" without --force sends them to a
		# second error.
		if walk_has_draft_file "$_wre_draft"; then
			_wre_what="the file is now empty"
			_wre_fix="git review walkthrough draft --force $_wre_draft"
		else
			_wre_what="the file no longer exists"
			_wre_fix="git review walkthrough draft $_wre_draft"
		fi
		echo "error: the walkthrough this review was reading is gone — it was $_wre_draft's draft, and $_wre_what. Write it again with '$_wre_fix', or discard the review with 'git review abort'." >&2
		exit 1
	fi
	# The shrink is only evidence of a stray commit while nothing else can shrink
	# the sequence. When the base is recorded and HEAD is still on it, this message
	# would be provably false — the reviewer would be sent to git reset --soft over
	# a range that never moved — so it is skipped and the generic diagnostic below
	# takes over. walk_recover_cursor has already handled the one shape of that
	# which is recoverable (their own draft, still there, cursor past the end).
	if [ "$_wre_step" -ge 1 ] && [ "$_wre_count" -ge 1 ] && [ "$_wre_total" -lt "$_wre_count" ] &&
		! walk_at_base; then
		echo "error: HEAD has moved off this review's base — the walkthrough cursor is at entry $_wre_step but only $_wre_total of $_wre_count $(entry_noun "$_wre_count") remain in range. Walk mode keeps the whole-PR diff staged with HEAD at the base; you now have commit(s) on top (did you run git commit?). Undo them with 'git reset --soft' to restage the diff, or 'git review abort' to discard the review, then retry." >&2
		exit 3
	fi
	# A draft that is in force and yields no entry at all in this range. That is a
	# state of the draft, not corruption: the reviewer either rewrote it down to
	# the skeleton — "## ?." headings are not entries until they carry a number —
	# or wrote one whose paths do not meet the range. walk_recover_cursor cannot
	# clamp it because there is nothing to clamp to, and without this branch the
	# reviewer who follows the "gone" message above, drafts the skeleton it asked
	# for and runs the next command is answered with "corrupt metadata": untrue,
	# and the only exit it names is discarding the review.
	#
	# Deliberately below the HEAD check and not above it. A stray commit empties
	# the sequence too, and that state is about HEAD, not about the draft: ordering
	# this first told a reviewer who had just committed over the staged diff to go
	# number their entries, and dropped the exit code the clients read as
	# out-of-range from 3 to 1.
	if [ -n "$_wre_draft" ] && [ "$_wre_total" -eq 0 ]; then
		echo "error: your walkthrough draft for $_wre_draft has no entries in this review's range; the cursor is at entry $_wre_step. Number the entries and run 'git review walkthrough draft --build $_wre_draft', or discard the review with 'git review abort'." >&2
		exit 1
	fi
	echo "error: review entry $_wre_step out of range (1..$_wre_total) — corrupt metadata? Discard the review with 'git review abort'." >&2
	exit 1
}

# load_walk_review_meta
# Confirm HEAD is on a review/* branch in walk mode and load its metadata into the
# globals the caller and goto_walk_entry rely on: cur, src, tip, walkstep,
# walkcount, walkpaths and total. The sequence is re-derived (not persisted), the
# way the step commands re-derive commits with rev-list; HEAD is pinned at the
# lower bound for a walk review's life, so the derivation is stable across edits.
# Exits with a diagnostic on any inconsistency.
load_walk_review_meta() {
	cur="$(git symbolic-ref --quiet --short HEAD || true)"
	[ -n "$cur" ] || {
		echo "error: not on a branch" >&2
		exit 1
	}
	case "$cur" in
	review/*) ;;
	*)
		echo "error: not on a review/* branch (HEAD is $cur)" >&2
		exit 2
		;;
	esac

	mode="$(git config "branch.$cur.reviewmode" || true)"
	[ "$mode" = "walk" ] || {
		echo "error: $cur was not started with a walkthrough" >&2
		exit 1
	}

	src="$(git config "branch.$cur.reviewsource" || true)"
	tip="$(git config "branch.$cur.reviewtip" || true)"
	walkstep="$(git config "branch.$cur.reviewwalkstep" || true)"
	walkcount="$(git config "branch.$cur.reviewwalkcount" || true)"

	if [ -z "$src" ] || [ -z "$tip" ]; then
		if [ -z "$src" ]; then
			echo "error: missing review metadata; was $cur created with git review start? Switch away, then delete it with 'git branch -D $cur'." >&2
		else
			echo "error: missing review metadata; was $cur created with git review start? Discard the review with 'git review abort'." >&2
		fi
		exit 1
	fi

	# Point the readers at the draft this review is reading, if any. It has to
	# happen before the sequence below, which is the first thing here to go
	# through walk_read. Doing it in the context loader rather than in each verb
	# is what guarantees every surface of one review — next, prev, status --why,
	# preview — reads the same walkthrough.
	#
	# walk_review_draft_src is the one place that answers "under what name?", and
	# it answers it from what the review recorded rather than from reviewsource —
	# a compare of a remote-tracking branch reviews "origin/feature/x" while its
	# draft is "feature/x"'s. The name is recorded whether or not a draft existed
	# at creation, so a draft written mid-review is picked up under the same name
	# git review walkthrough draft wrote it to.
	walk_use_draft "$(walk_review_draft_src "$cur")"

	# Keys-only submode (start/compare --keys): sequence is curated ∩ keys, not
	# the full reading order. The flag lives on the branch; absence is full walk.
	if [ "$(git config "branch.$cur.reviewwalkkeys" || true)" = "1" ]; then
		walkpaths="$(walk_keys_order "$tip" "$(git rev-parse HEAD)")"
	else
		walkpaths="$(walk_reading_order "$tip" "$(git rev-parse HEAD)")"
	fi
	# grep -c returns 1 (aborting under set -e in POSIX sh) when walkpaths is empty;
	# guard it so a lost sequence reaches the range check below as total=0.
	total="$(printf '%s\n' "$walkpaths" | grep -c . || true)"

	case "$walkcount" in
	'' | *[!0-9]*)
		echo "error: corrupt review metadata: reviewwalkcount is '$walkcount', not a positive integer. Discard the review with 'git review abort'." >&2
		exit 1
		;;
	esac
	[ "$walkcount" -ge 1 ] || {
		echo "error: corrupt review metadata: reviewwalkcount is '$walkcount', not a positive integer. Discard the review with 'git review abort'." >&2
		exit 1
	}
	case "$walkstep" in
	'' | *[!0-9]*)
		echo "error: corrupt review metadata: reviewwalkstep is '$walkstep', not a positive integer. Discard the review with 'git review abort'." >&2
		exit 1
		;;
	esac
	if [ "$walkstep" -lt 1 ] || [ "$walkstep" -gt "$total" ]; then
		# Recovery before diagnosis: the one cause that leaves the review intact is
		# the reviewer editing their own draft, and that one is repaired rather than
		# reported. Everything else still gets the message it earned.
		walk_recover_cursor || walk_range_error "$walkstep" "$total" "$walkcount"
	fi
}

# show_walk_entry <k>
# Print the k-th entry of the reading order: a rule, the "[k/N] <path>" header,
# either the author's "why" prose or, for a file the walkthrough does not
# annotate, a fixed line saying so, another rule and the prompt. An entry the
# author marked "> key" is labelled as such in the header — the reading order
# says what to read when, the marker says which ones not to skim; an
# unannotated entry is labelled "(uncovered)" instead, since it has no marker
# to carry. The path carries no line number on purpose — clicking it in an IDE
# terminal just opens the file at the top; a hunk line only ever pointed at the
# first change and went stale the moment you edited.
# Relies on the globals set by load_walk_review_meta (tip, total, walkpaths).
show_walk_entry() {
	_swe_path="$(printf '%s\n' "$walkpaths" | sed -n "${1}p")"
	if walk_is_annotated "$tip" "$_swe_path"; then
		_swe_mark=""
		if walk_is_key "$tip" "$_swe_path"; then
			_swe_mark="  (key)"
		fi
		_swe_body="$(walk_why "$tip" "$_swe_path")"
	else
		_swe_mark="  (uncovered)"
		_swe_body="this file changes in the review and the walkthrough does not annotate it"
	fi
	printf -- '----\n[%s/%s] %s%s\n%s\n----\nread this file, edit if needed, then run git review next\n' \
		"$1" "$total" "$_swe_path" "$_swe_mark" "$_swe_body"
}

# goto_walk_entry <k>
# Move the walk cursor to entry <k> and show it. Unlike goto_step this touches
# nothing but the cursor key: walk never stages or resets, so working tree and
# index are left exactly as they were.
goto_walk_entry() {
	git config "branch.$cur.reviewwalkstep" "$1"
	walkstep="$1"
	show_walk_entry "$1"
}
