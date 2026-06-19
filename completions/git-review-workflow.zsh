#compdef -value-,GIT_REVIEW_WORKFLOW,-default-
#
# Native zsh completion for git-review-workflow.
#
# zsh's git completion dispatches `git <subcommand>` to a function named
# `_git-<subcommand>` if one is defined. This file defines those functions and
# reuses zsh's own git completion helpers (__git_branch_names, __git_commits).
#
# Install: put this file on your $fpath (or source it after compinit), e.g.
#
#     fpath=(/path/to/git-review-workflow/completions $fpath)
#     autoload -Uz compinit && compinit
#
# or simply:
#
#     source /path/to/git-review-workflow/completions/git-review-workflow.zsh

_git-review() {
	_arguments \
		'(-h --help)'{-h,--help}'[list all available commands]' \
		'(-V --version)'{-V,--version}'[print the installed version]'
}

_git-review-pr() {
	_arguments -S \
		'(-h --help)'{-h,--help}'[show help]' \
		'(--from)--delta[review only the commits added since your last review]' \
		'(--delta)--from[review only the commits after <commit>]:commit:__git_commits' \
		'--step[review one commit at a time]' \
		'1:branch:__git_branch_names' \
		'2:base branch:__git_branch_names'
}

_git-review-next() {
	_arguments '(-h --help)'{-h,--help}'[show help]'
}

_git-review-prev() {
	_arguments '(-h --help)'{-h,--help}'[show help]'
}

_git-review-status() {
	_arguments '(-h --help)'{-h,--help}'[show help]'
}

_git-review-list() {
	_arguments '(-h --help)'{-h,--help}'[show help]'
}

_git-review-abort() {
	_arguments '(-h --help)'{-h,--help}'[show help]'
}

_git-finish-review() {
	_arguments -S \
		'(-h --help)'{-h,--help}'[show help]' \
		'--onto-source[add your edits as a commit on the PR branch itself]' \
		'--push[push the resulting branch to origin]' \
		'--resume[continue after resolving replay conflicts]'
}

_git-clean-review() {
	_arguments -S \
		'(-h --help)'{-h,--help}'[show help]' \
		'--forget[also discard the recorded last-reviewed tip]' \
		'1:review branch:->reviewbranches'

	if [ "$state" = reviewbranches ]; then
		local -a names
		names=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads/review/ 2>/dev/null | sed 's#^review/##')"})
		_describe 'review branch' names
	fi
}
