#compdef -value-,GIT_REVIEW_WORKFLOW,-default-
#
# Native zsh completion for git-review-workflow.
#
# Every command lives under the `git review <verb>` dispatcher, so zsh's git
# completion only ever dispatches `git review` to `_git-review`; this file makes
# that one function offer the verbs and then complete each verb's own options and
# arguments (the `git bisect` idiom).
#
# Install: put this file on your $fpath (or source it after compinit), e.g.
#
#     fpath=(/path/to/git-review-workflow/completions $fpath)
#     autoload -Uz compinit && compinit
#
# or simply:
#
#     source /path/to/git-review-workflow/completions/git-review-workflow.zsh

# Helpers per verb. Named with underscores (not `_git-review-<verb>`) so zsh's
# git dispatcher never mistakes one for the completer of a `git review-<verb>`
# subcommand — there is no such subcommand any more.

_git_review_start() {
	_arguments -S \
		'(-h --h)'{-h,--h}'[show help]' \
		'--base[base to diff against when the branch is omitted]:base:__git_revisions' \
		'(--from)--delta[review only the commits added since your last review]' \
		'(--delta)--from[review only the commits after <commit>]:commit:__git_commits' \
		'(--no-walk)--step[review one commit at a time]' \
		'(--step)--no-walk[ignore any walkthrough on the PR]' \
		'--local[review your local branches directly, without fetching]' \
		'*: :__git_revisions'
}

_git_review_compare() {
	_arguments -S \
		'(-h --h)'{-h,--h}'[show help]' \
		'(--no-walk)--step[review one commit at a time]' \
		'(--step)--no-walk[ignore any walkthrough on <b>]' \
		'*:commit-ish:__git_revisions'
}

_git_review_walkthrough() {
	local state line
	_arguments -S \
		'(-h --h)'{-h,--h}'[show help]' \
		': :->wtsub' \
		'*:: :->wtargs'

	case "$state" in
	wtsub)
		local -a wtsubs
		wtsubs=(
			'init:write a skeleton listing every changed file'
			'build:validate, order and renumber the entries'
		)
		_describe -t wtsubs 'walkthrough subcommand' wtsubs
		;;
	wtargs)
		case "$line[1]" in
		init)
			_arguments -S \
				'(-h --h)'{-h,--h}'[show help]' \
				'--base[diff against this base instead of reviewworkflow.base]:base:__git_revisions' \
				'--force[overwrite an existing walkthrough]'
			;;
		build)
			_arguments -S \
				'(-h --h)'{-h,--h}'[show help]' \
				'--check[validate only; write nothing]'
			;;
		esac
		;;
	esac
}

# config [<key> [<value>]] [--unset <key>] [--porcelain [<branch>]]: same flat
# positional style _git_review_start already uses (no distinction between the
# key slot and the value/branch slot — keeps this in line with the rest of the
# file rather than fighting _arguments over which positional means what).
_git_review_config() {
	local state
	_arguments -S \
		'(-h --h)'{-h,--h}'[show help]' \
		'--unset[remove a key]:key:(base remote)' \
		'--porcelain[machine-readable config, candidates and delta marker]' \
		'*: :->configargs'

	if [ "$state" = configargs ]; then
		local -a names
		names=('base' 'remote' ${(f)"$(__grw_candidate_branches)"})
		_describe 'config key or branch' names
	fi
}

# Candidate branches for `config` — local heads and the configured remote's
# tracking branches, minus the three review namespaces and <remote>/HEAD. Same
# set `config --porcelain` reports (contracts/config-porcelain.md).
__grw_candidate_branches() {
	local remote
	remote="$(git config --get reviewworkflow.remote 2>/dev/null || echo origin)"
	git for-each-ref --format='%(refname:short)' refs/heads/ "refs/remotes/$remote/" 2>/dev/null |
		sed -e "s#^$remote/##" |
		grep -v -e '^review/' -e '^review-saved/' -e '^review-fixes/' -e '^HEAD$' |
		sort -u
}

_git_review_finish() {
	_arguments -S \
		'(-h --h)'{-h,--h}'[show help]' \
		'--onto-source[stage your edits on the PR branch itself]' \
		'--resume[continue after resolving replay conflicts]' \
		'--abort[undo the last finish and return to editing]' \
		'--force[with --abort, discard changes made to the finish branch]'
}

_git_review_comments() {
	local state line
	_arguments -S \
		'(-h --help)'{-h,--help}'[show help]' \
		':comments command:->commentsub' \
		'*::comments arguments:->commentargs'
	case "$state" in
	commentsub)
		local -a comment_commands
		comment_commands=('status:inspect comments' 'init:create one document' 'add:compose a comment'
			'renumber:number entries in physical order' 'entries:list physical entries'
			'diff:show the captured historical code' 'save:retain compare comments locally'
			'prepare:prepare pending Shared comments')
		_describe 'comments command' comment_commands
		;;
	commentargs)
		local -a comment_options
		comment_options=('(-h --help)'{-h,--help}'[show help]')
		case "$line[1]" in
		status|entries|diff|prepare) comment_options+=('--porcelain[machine-readable output]') ;;
		esac
		if [[ "$line[1]" != save ]]; then comment_options+=('--context[select an existing context]:context:'); fi
		case "$line[1]" in
		init|add|renumber|entries|diff) comment_options+=('--document[choose the document]:document:(local shared)') ;;
		esac
		case "$line[1]" in
		init|add) comment_options+=('(--use-context)--new-context[declare a different context]' '(--new-context)--use-context[choose a known context]:context:') ;;
		esac
		case "$line[1]" in
		init|add|renumber|diff|prepare) comment_options+=('--expect-context[guard the original session]:token:' '--expect-document[guard document bytes and presence]:revision:') ;;
		esac
		case "$line[1]" in
		add) comment_options+=('(--stdin)--text[comment body]:text:' '(--text)--stdin[read text from standard input]'
			'--path[captured file]:path:' '--side[selected side]:side:(base head)'
			'--start-line[first selected line]:line:' '--end-line[last selected line]:line:'
			'--base[full base object ID]:OID:' '--head[full head object ID]:OID:'
			'--base-path[path at base]:path:' '--head-path[path at head]:path:' '--unversioned[location came from a dirty buffer]') ;;
		diff) comment_options+=('--entry[physical ordinal]:ordinal:') ;;
		save) comment_options+=('--expect-context[guard the original session]:token:' '--expect-local[guard Local]:revision:' '--expect-shared[guard Shared]:revision:') ;;
		prepare) comment_options+=('--check[inspect delivery without writing]') ;;
		esac
		_arguments -S "$comment_options[@]"
		;;
	esac
}

_git_review_preview() {
	_arguments -S \
		'(-h --h)'{-h,--h}'[show help]' \
		'--stat[show a diffstat summary instead of the full diff]'
}

_git_review_ui() {
	_arguments -S \
		'(-h --h)'{-h,--h}'[show help]'
}

_git_review_continue() {
	local state
	_arguments -S \
		'(-h --h)'{-h,--h}'[show help]' \
		'*: :->savedbranches'

	if [ "$state" = savedbranches ]; then
		local -a names
		names=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads/review-saved/ 2>/dev/null | sed 's#^review-saved/##')"})
		_describe 'saved review' names
	fi
}

_git_review_clean() {
	local state
	_arguments -S \
		'(-h --h)'{-h,--h}'[show help]' \
		'*: :->reviewbranches'

	if [ "$state" = reviewbranches ]; then
		local -a names
		names=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads/review/ 2>/dev/null | sed 's#^review/##')"})
		_describe 'review branch' names
	fi
}

_git_review_forget() {
	local state
	_arguments -S \
		'(-h --h)'{-h,--h}'[show help]' \
		'(--saved)--delta[forget the --delta markers recorded by git review start]' \
		'(--delta)--stale[(--delta) forget markers whose branch no longer exists]' \
		'(--delta --saved)--saved[discard a review paused with git review save]' \
		'--all[every marker (--delta) or every saved review (--saved)]' \
		'--dry-run[list what would be forgotten without forgetting it]' \
		'*: :->forgetbranches'

	# With --saved, complete from review-saved/* branches; otherwise from the
	# recorded --delta markers (which outlive the review/* branches).
	if [ "$state" = forgetbranches ]; then
		local -a names
		if (( ${words[(I)--saved]} )); then
			names=(${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads/review-saved/ 2>/dev/null | sed 's#^review-saved/##')"})
			_describe 'saved review' names
		else
			names=(${(f)"$({ git config --get-regexp '^reviewworkflow\..*\.reviewed$' 2>/dev/null; git config --get-regexp '^reviewworkflowlocal\..*\.reviewed$' 2>/dev/null; } | sed -n -e 's/^reviewworkflowlocal\.//' -e 's/^reviewworkflow\.//' -e 's/\.reviewed .*//p' | sort -u)"})
			_describe 'marked branch' names
		fi
	fi
}

_git-review() {
	local curcontext="$curcontext" state line
	typeset -A opt_args

	_arguments -C \
		'(-h --h)'{-h,--h}'[list all available commands]' \
		'(-V --version)'{-V,--version}'[print the installed version]' \
		': :->verb' \
		'*:: :->args'

	case "$state" in
	verb)
		local -a verbs
		verbs=(
			'start:stage a PR diff on a new review/<branch> branch'
			'compare:stage the diff between two commit-ish, read-only'
			'walkthrough:author a reading walkthrough for the current PR'
			'comments:write and revisit Local or Shared review comments'
			'config:read or write the base branch and remote'
			'next:advance a commit-by-commit or walkthrough review one entry'
			'prev:step a commit-by-commit or walkthrough review back one entry'
			'status:show the state of the review on the current branch'
			'list:list every review/* branch in progress'
			'preview:show your edits so far without committing or switching'
			'finish:extract your edits onto review-fixes/<branch>'
			'save:pause the current review and return to where you started'
			'continue:resume a review paused with git review save'
			'abort:cancel the current review and return to where you started'
			'clean:delete review/* and review-fixes/* branches'
			'forget:discard a review'\''s persistent state (delta markers or a saved review)'
			'ui:hand off to the git-review-ui terminal UI, if installed'
		)
		_describe -t verbs 'git review verb' verbs
		;;
	args)
		curcontext="${curcontext%:*:*}:git-review-$line[1]:"
		case "$line[1]" in
		start) _git_review_start ;;
		compare) _git_review_compare ;;
		walkthrough) _git_review_walkthrough ;;
		comments) _git_review_comments ;;
		config) _git_review_config ;;
		finish) _git_review_finish ;;
		preview) _git_review_preview ;;
		continue) _git_review_continue ;;
		clean) _git_review_clean ;;
		forget) _git_review_forget ;;
		ui) _git_review_ui ;;
		next|prev|status|list|save|abort)
			_arguments '(-h --h)'{-h,--h}'[show help]'
			;;
		esac
		;;
	esac
}
