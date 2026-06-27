# Bash completion for git-review-workflow.
#
# All commands live under the `git review <verb>` dispatcher, so a single
# `_git_review` completer drives them: it offers the verbs, then dispatches to a
# per-verb helper for that verb's options and arguments.
#
# Requires git's own bash completion to be loaded first (it provides the
# __gitcomp* / __git_* helpers and the $cur variable). Source this file after it:
#
#     source /path/to/completions/git-review-workflow.bash
#
# zsh users: run `autoload -U +X bashcompinit && bashcompinit` first, then
# source this file.

# Source branches with a saved review (review-saved/*), for `continue` and
# `forget --saved`.
__grw_saved_branches() {
	git for-each-ref --format='%(refname:short)' refs/heads/review-saved/ 2>/dev/null |
		sed -n 's#^review-saved/##p'
}

# review/* branches with the prefix stripped, for `clean`.
__grw_review_branches() {
	git for-each-ref --format='%(refname:short)' refs/heads/review/ 2>/dev/null |
		sed -n 's#^review/##p'
}

# Source branches that have a recorded --delta marker. These outlive the
# review/* branches, so they — not local heads — are what `forget --delta` acts on.
__grw_marked_branches() {
	# Both marker sections, reviewworkflow.* (remote) and reviewworkflowlocal.*
	# (--local). A branch reviewed both ways collapses to one entry via sort -u, so
	# it is offered once by its plain name (`forget --delta <branch>` clears both).
	{
		git config --get-regexp '^reviewworkflow\..*\.reviewed$' 2>/dev/null
		git config --get-regexp '^reviewworkflowlocal\..*\.reviewed$' 2>/dev/null
	} | sed -n -e 's/^reviewworkflowlocal\.//' -e 's/^reviewworkflow\.//' \
		-e 's/\.reviewed .*//p' | sort -u
}

_git_review_start() {
	case "$cur" in
	--*)
		__gitcomp "--base --delta --from --step --local --h"
		;;
	*)
		__gitcomp_nl "$(__git_refs)"
		;;
	esac
}

_git_review_compare() {
	case "$cur" in
	--*)
		__gitcomp "--step --h"
		;;
	*)
		__gitcomp_nl "$(__git_refs)"
		;;
	esac
}

_git_review_finish() {
	__gitcomp "--onto-source --resume --abort --force --h"
}

_git_review_preview() {
	__gitcomp "--stat --h"
}

_git_review_continue() {
	case "$cur" in
	--*)
		__gitcomp "--h"
		;;
	*)
		__gitcomp_nl "$(__grw_saved_branches)"
		;;
	esac
}

_git_review_clean() {
	case "$cur" in
	--*)
		__gitcomp "--h"
		;;
	*)
		__gitcomp_nl "$(__grw_review_branches)"
		;;
	esac
}

# forget has two modes: --delta (acts on the recorded markers) and --saved
# (acts on review-saved/* branches). Offer the relevant flags and candidates once a
# mode word is on the line; before that, just the two modes.
_git_review_forget() {
	case " ${COMP_WORDS[*]} " in
	*" --saved "*)
		case "$cur" in
		--*) __gitcomp "--all --dry-run --h" ;;
		*) __gitcomp_nl "$(__grw_saved_branches)" ;;
		esac
		;;
	*" --delta "*)
		case "$cur" in
		--*) __gitcomp "--all --stale --dry-run --h" ;;
		*) __gitcomp_nl "$(__grw_marked_branches)" ;;
		esac
		;;
	*)
		__gitcomp "--delta --saved --h"
		;;
	esac
}

# Entry point: git's bash completion calls this for `git review ...`. Find the
# verb already on the line; if none yet, complete the verb list (or the
# dispatcher's own -h/--version). Otherwise dispatch to the verb's helper —
# verbs with no options beyond --h fall through to the default.
_git_review() {
	local subcommands="start compare next prev status list preview finish save continue abort clean forget"
	local subcommand
	subcommand="$(__git_find_on_cmdline "$subcommands")"

	if [ -z "$subcommand" ]; then
		case "$cur" in
		-*) __gitcomp "--h --version" ;;
		*) __gitcomp "$subcommands" ;;
		esac
		return
	fi

	case "$subcommand" in
	start) _git_review_start ;;
	compare) _git_review_compare ;;
	finish) _git_review_finish ;;
	preview) _git_review_preview ;;
	continue) _git_review_continue ;;
	clean) _git_review_clean ;;
	forget) _git_review_forget ;;
	*) __gitcomp "--h" ;;
	esac
}
