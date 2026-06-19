# Bash completion for git-review-workflow.
#
# Requires git's own bash completion to be loaded first (it provides the
# __gitcomp* helpers and the $cur variable). Source this file after it:
#
#     source /path/to/completions/git-review-workflow.bash
#
# zsh users: run `autoload -U +X bashcompinit && bashcompinit` first, then
# source this file.

_git_review_pr() {
	case "$cur" in
	--*)
		__gitcomp "--delta --from --step --version --help"
		;;
	*)
		__gitcomp_nl "$(__git_refs)"
		;;
	esac
}

_git_review_next() {
	__gitcomp "--version --help"
}

_git_review_prev() {
	__gitcomp "--version --help"
}

_git_review_status() {
	__gitcomp "--version --help"
}

_git_review_abort() {
	__gitcomp "--version --help"
}

_git_finish_review() {
	__gitcomp "--onto-source --push --resume --version --help"
}

_git_clean_review() {
	case "$cur" in
	--*)
		__gitcomp "--forget --version --help"
		;;
	*)
		__gitcomp_nl "$(__git_heads | sed -n 's#^review/##p')"
		;;
	esac
}
