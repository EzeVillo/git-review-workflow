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

# ── Walkthrough (walk) mode helpers ───────────────────────────────────────────
#
# A walkthrough is a curated reading order over a PR, authored as a committed
# sidecar (.review/walkthrough.md) and consumed by the reviewer. Walk mode is the
# same whole-PR review (the diff is staged and editable), plus a reading cursor
# over it. Nothing here stages, resets or banks anything — the working tree is the
# whole PR throughout, exactly as in whole mode; only a cursor config key moves.

# fold_lower <start> <baseref> <tip>
# Compute a review's lower bound (exclusive). Normally it is <start>, but if the
# base branch was merged into the PR, fold that already-merged base content into
# the lower bound so base-derived changes are not shown as part of the review.
# Prints the resulting commit-ish. A no-op (prints <start>) when there is nothing
# to fold, when <baseref> is empty, or on a git without merge-tree. This is the
# logic git review start applies to its staged diff, shared so walkthrough
# init/build compute the exact same bound a reviewer will see.
fold_lower() {
	_fl_start="$1"
	_fl_baseref="$2"
	_fl_tip="$3"
	_fl_lower="$_fl_start"
	if [ -n "$_fl_baseref" ]; then
		_fl_mb="$(git merge-base "$_fl_baseref" "$_fl_tip" 2>/dev/null || true)"
		if [ -n "$_fl_mb" ] && [ "$_fl_mb" != "$_fl_tip" ] &&
			! git merge-base --is-ancestor "$_fl_mb" "$_fl_start"; then
			if _fl_tree="$(git merge-tree --write-tree "$_fl_start" "$_fl_mb" 2>/dev/null)"; then
				_fl_lower="$(git commit-tree "$_fl_tree" -p "$_fl_start" -m 'review lower bound')"
			else
				echo "note: could not exclude merged base content from the review diff" >&2
			fi
		fi
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

# walk_read <tip>
# Print the walkthrough committed at <tip>, or nothing (non-zero rc) if there is
# none. Never aborts the caller: used in conditions and command substitutions.
# This is the single point where committed content enters the readers, so it is
# also where line endings are normalised.
walk_read() {
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
# How many of the given entries carry the "> key" marker. Reads the walkthrough
# once rather than per path, so a long reading order costs one git show.
walk_count_keys() {
	_wck_content="$(walk_read "$1" || true)"
	_wck_n=0
	while IFS= read -r _wck_p; do
		[ -n "$_wck_p" ] || continue
		if printf '%s\n' "$_wck_content" | walk_body "$_wck_p" |
			grep -q '^> key[[:space:]]*$'; then
			_wck_n=$((_wck_n + 1))
		fi
	done
	printf '%s\n' "$_wck_n"
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
# file walk_reading_order appended because it has none). Reads the walkthrough
# at <tip> once (extends the walk_count_keys one-read pattern) so a long
# reading order costs one git show per --porcelain invocation, not one per
# entry — the O(1) performance goal of the porcelain contract. Fields only, not
# a porcelain line: the caller passes each field through porcelain_row.
walk_entry_fields() {
	_we_content="$(walk_read "$1" || true)"
	_we_annotated="$(printf '%s\n' "$_we_content" | walk_parse | cut -f2-)"
	_we_n=0
	while IFS= read -r _we_p; do
		[ -n "$_we_p" ] || continue
		_we_n=$((_we_n + 1))
		_we_ess=0
		if printf '%s\n' "$_we_content" | walk_body "$_we_p" |
			grep -q '^> key[[:space:]]*$'; then
			_we_ess=1
		fi
		_we_ann=0
		if printf '%s\n' "$_we_annotated" | grep -Fxq "$_we_p"; then
			_we_ann=1
		fi
		printf '%s\t%s\t%s\t%s\n' "$_we_n" "$_we_p" "$_we_ess" "$_we_ann"
	done
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
# and one git diff live there, and this adds one more diff to find the paths
# the curated sequence left out. Still O(1) per --porcelain invocation — no
# call scales with the number of entries.
walk_reading_order() {
	_wro_seq="$(walk_sequence "$1" "$2")"
	[ -n "$_wro_seq" ] || return 0
	printf '%s\n' "$_wro_seq"
	range_files "$1" "$2" | while IFS= read -r _wro_p; do
		printf '%s\n' "$_wro_seq" | grep -Fxq "$_wro_p" || printf '%s\n' "$_wro_p"
	done
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
walk_range_error() {
	_wre_step="$1"
	_wre_total="$2"
	_wre_count="$3"
	case "$_wre_count" in
	'' | *[!0-9]*) _wre_count=0 ;;
	esac
	if [ "$_wre_step" -ge 1 ] && [ "$_wre_count" -ge 1 ] && [ "$_wre_total" -lt "$_wre_count" ]; then
		echo "error: HEAD has moved off this review's base — the walkthrough cursor is at entry $_wre_step but only $_wre_total of $_wre_count entr$([ "$_wre_count" -eq 1 ] && echo y || echo ies) remain in range. Walk mode keeps the whole-PR diff staged with HEAD at the base; you now have commit(s) on top (did you run git commit?). Undo them with 'git reset --soft' to restage the diff, or 'git review abort' to discard the review, then retry." >&2
		exit 3
	fi
	echo "error: review entry $_wre_step out of range (1..$_wre_total) — corrupt metadata?" >&2
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
		echo "error: missing review metadata; was $cur created with git review start?" >&2
		exit 1
	fi

	walkpaths="$(walk_reading_order "$tip" "$(git rev-parse HEAD)")"
	# grep -c returns 1 (aborting under set -e in POSIX sh) when walkpaths is empty;
	# guard it so a lost sequence reaches the range check below as total=0.
	total="$(printf '%s\n' "$walkpaths" | grep -c . || true)"

	case "$walkcount" in
	'' | *[!0-9]*)
		echo "error: corrupt review metadata: reviewwalkcount is '$walkcount', not a positive integer" >&2
		exit 1
		;;
	esac
	[ "$walkcount" -ge 1 ] || {
		echo "error: corrupt review metadata: reviewwalkcount is '$walkcount', not a positive integer" >&2
		exit 1
	}
	case "$walkstep" in
	'' | *[!0-9]*)
		echo "error: corrupt review metadata: reviewwalkstep is '$walkstep', not a positive integer" >&2
		exit 1
		;;
	esac
	if [ "$walkstep" -lt 1 ] || [ "$walkstep" -gt "$total" ]; then
		walk_range_error "$walkstep" "$total" "$walkcount"
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
