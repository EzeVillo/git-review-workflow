# Bash completion for git-review-workflow.
#
# Requires git's own bash completion to be loaded first (it provides the
# __gitcomp* helpers and the $cur variable). Source this file after it:
#
#     source /path/to/completions/git-review-workflow.bash
#
# zsh users: run `autoload -U +X bashcompinit && bashcompinit` first, then
# source this file.

_git_review() {
	__gitcomp "--h --version"
}

_git_review_pr() {
	case "$cur" in
	--*)
		__gitcomp "--this --delta --from --step --local --h"
		;;
	*)
		__gitcomp_nl "$(__git_refs)"
		;;
	esac
}

_git_review_next() {
	__gitcomp "--h"
}

_git_review_prev() {
	__gitcomp "--h"
}

_git_review_status() {
	__gitcomp "--h"
}

_git_review_preview() {
	__gitcomp "--stat --h"
}

_git_review_list() {
	__gitcomp "--h"
}

_git_review_save() {
	__gitcomp "--h"
}

# Source branches with a saved review (review-saved/*), for review-continue and
# review-forget-saved.
__grw_saved_branches() {
	git for-each-ref --format='%(refname:short)' refs/heads/review-saved/ 2>/dev/null |
		sed -n 's#^review-saved/##p'
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

_git_review_abort() {
	__gitcomp "--h"
}

_git_finish_review() {
	__gitcomp "--onto-source --resume --abort --h"
}

_git_clean_review() {
	case "$cur" in
	--*)
		__gitcomp "--h"
		;;
	*)
		__gitcomp_nl "$(__git_heads | sed -n 's#^review/##p')"
		;;
	esac
}

# Source branches that have a recorded --delta marker. These outlive the
# review/* branches, so they — not local heads — are what review-forget-delta acts on.
__grw_marked_branches() {
	# Both marker sections, reviewworkflow.* (remote) and reviewworkflowlocal.*
	# (--local). A branch reviewed both ways collapses to one entry via sort -u, so
	# it is offered once by its plain name (review-forget-delta <branch> clears both).
	{
		git config --get-regexp '^reviewworkflow\..*\.reviewed$' 2>/dev/null
		git config --get-regexp '^reviewworkflowlocal\..*\.reviewed$' 2>/dev/null
	} | sed -n -e 's/^reviewworkflowlocal\.//' -e 's/^reviewworkflow\.//' \
		-e 's/\.reviewed .*//p' | sort -u
}

_git_review_forget_delta() {
	case "$cur" in
	--*)
		__gitcomp "--all --stale --dry-run --h"
		;;
	*)
		__gitcomp_nl "$(__grw_marked_branches)"
		;;
	esac
}

_git_review_forget_saved() {
	case "$cur" in
	--*)
		__gitcomp "--all --h"
		;;
	*)
		__gitcomp_nl "$(__grw_saved_branches)"
		;;
	esac
}
