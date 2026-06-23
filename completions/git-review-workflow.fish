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

# Source branches that have a recorded --delta marker, for review-forget-delta. The
# markers outlive the review/* branches, so this is the right candidate set.
function __grw_marked_branches
    # Both marker sections, reviewworkflow.* (remote) and reviewworkflowlocal.*
    # (--local). A branch reviewed both ways collapses to one entry via sort -u, so
    # it shows once by its plain name (review-forget-delta <branch> clears both).
    begin
        git config --get-regexp '^reviewworkflow\..*\.reviewed$' 2>/dev/null
        git config --get-regexp '^reviewworkflowlocal\..*\.reviewed$' 2>/dev/null
    end \
        | string replace -r '^reviewworkflow(local)?\.(.*)\.reviewed .*$' '$2' \
        | sort -u
end

# Source branches with a saved review (review-saved/*), for review-continue and
# review-forget-saved.
function __grw_saved_branches
    git for-each-ref --format='%(refname:short)' refs/heads/review-saved/ 2>/dev/null \
        | string replace -r '^review-saved/' ''
end

# git review
complete -c git -n '__grw_using review' -f -l h    -d 'list all available commands'
complete -c git -n '__grw_using review' -f -s V -l version -d 'print the installed version'

# git review-pr
complete -c git -n '__grw_using review-pr' -f -l this -d 'review the branch you are currently on'
complete -c git -n '__grw_using review-pr' -f -l delta -d 'review only commits since your last review'
complete -c git -n '__grw_using review-pr' -f -l from -d 'review only commits after <commit>'
complete -c git -n '__grw_using review-pr' -f -l step -d 'review one commit at a time'
complete -c git -n '__grw_using review-pr' -f -l local -d 'review your local branches directly, without fetching'
complete -c git -n '__grw_using review-pr' -f -l h -d 'show help'
complete -c git -n '__grw_using review-pr' -f -a '(__grw_branches)'

# git finish-review
complete -c git -n '__grw_using finish-review' -f -l onto-source -d 'stage edits on the PR branch itself'
complete -c git -n '__grw_using finish-review' -f -l resume -d 'continue after resolving replay conflicts'
complete -c git -n '__grw_using finish-review' -f -l abort -d 'undo the last finish and return to editing'
complete -c git -n '__grw_using finish-review' -f -l force -d 'with --abort, discard changes made to the finish branch'
complete -c git -n '__grw_using finish-review' -f -l h -d 'show help'

# git clean-review
complete -c git -n '__grw_using clean-review' -f -l h -d 'show help'
complete -c git -n '__grw_using clean-review' -f -a '(__grw_review_branches)'

# git review-forget-delta
complete -c git -n '__grw_using review-forget-delta' -f -l all -d 'forget every recorded marker'
complete -c git -n '__grw_using review-forget-delta' -f -l stale -d 'forget markers whose remote branch is gone'
complete -c git -n '__grw_using review-forget-delta' -f -l dry-run -d 'with --stale, list what would be forgotten'
complete -c git -n '__grw_using review-forget-delta' -f -l h -d 'show help'
complete -c git -n '__grw_using review-forget-delta' -f -a '(__grw_marked_branches)'

# git review-forget-saved
complete -c git -n '__grw_using review-forget-saved' -f -l all -d 'discard every saved review'
complete -c git -n '__grw_using review-forget-saved' -f -l h -d 'show help'
complete -c git -n '__grw_using review-forget-saved' -f -a '(__grw_saved_branches)'

# git review-continue
complete -c git -n '__grw_using review-continue' -f -l h -d 'show help'
complete -c git -n '__grw_using review-continue' -f -a '(__grw_saved_branches)'

# git review-preview
complete -c git -n '__grw_using review-preview' -f -l stat -d 'show a diffstat summary instead of the full diff'
complete -c git -n '__grw_using review-preview' -f -l h -d 'show help'

# Commands that take no arguments beyond --h.
for sub in review-next review-prev review-status review-list review-abort review-save
    complete -c git -n "__grw_using $sub" -f -l h -d 'show help'
end
