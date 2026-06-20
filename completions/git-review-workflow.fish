# Fish completion for git-review-workflow.
#
# Install by copying (or symlinking) this file into your fish completions dir:
#
#     ln -s /path/to/git-review-workflow/completions/git-review-workflow.fish \
#         ~/.config/fish/completions/
#
# These complete the `git review-pr`, `git finish-review`, ... subcommands.

# True when the command line is `git <subcommand> ...`.
function __grw_using -a sub
    set -l cmd (commandline -opc)
    test (count $cmd) -ge 2; and test $cmd[1] = git; and test $cmd[2] = $sub
end

# Local + remote branch names, for branch arguments.
function __grw_branches
    git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
end

# review/* branches with the prefix stripped, for clean-review.
function __grw_review_branches
    git for-each-ref --format='%(refname:short)' refs/heads/review/ 2>/dev/null \
        | string replace -r '^review/' ''
end

# Source branches that have a recorded --delta marker, for review-forget. The
# markers outlive the review/* branches, so this is the right candidate set.
function __grw_marked_branches
    git config --get-regexp '^reviewworkflow\..*\.reviewed$' 2>/dev/null \
        | string replace -r '^reviewworkflow\.(.*)\.reviewed .*$' '$1'
end

# git review
complete -c git -n '__grw_using review' -f -l help    -d 'list all available commands'
complete -c git -n '__grw_using review' -f -s V -l version -d 'print the installed version'

# git review-pr
complete -c git -n '__grw_using review-pr' -f -l delta -d 'review only commits since your last review'
complete -c git -n '__grw_using review-pr' -f -l from -d 'review only commits after <commit>'
complete -c git -n '__grw_using review-pr' -f -l step -d 'review one commit at a time'
complete -c git -n '__grw_using review-pr' -f -l help -d 'show help'
complete -c git -n '__grw_using review-pr' -f -a '(__grw_branches)'

# git finish-review
complete -c git -n '__grw_using finish-review' -f -l onto-source -d 'add edits as a commit on the PR branch'
complete -c git -n '__grw_using finish-review' -f -l push -d 'push the resulting branch to origin'
complete -c git -n '__grw_using finish-review' -f -l resume -d 'continue after resolving replay conflicts'
complete -c git -n '__grw_using finish-review' -f -l help -d 'show help'

# git clean-review
complete -c git -n '__grw_using clean-review' -f -l help -d 'show help'
complete -c git -n '__grw_using clean-review' -f -a '(__grw_review_branches)'

# git review-forget
complete -c git -n '__grw_using review-forget' -f -l all -d 'forget every recorded marker'
complete -c git -n '__grw_using review-forget' -f -l stale -d 'forget markers whose origin branch is gone'
complete -c git -n '__grw_using review-forget' -f -l dry-run -d 'with --stale, list what would be forgotten'
complete -c git -n '__grw_using review-forget' -f -l help -d 'show help'
complete -c git -n '__grw_using review-forget' -f -a '(__grw_marked_branches)'

# Commands that take no arguments beyond --help.
for sub in review-next review-prev review-status review-list review-abort
    complete -c git -n "__grw_using $sub" -f -l help -d 'show help'
end
