# Fish completion for git-review-workflow.
#
# Every command lives under the `git review <verb>` dispatcher, so these
# completions offer the verbs after `git review`, then each verb's own options
# and arguments.
#
# Install by copying (or symlinking) this file into your fish completions dir:
#
#     ln -s /path/to/git-review-workflow/completions/git-review-workflow.fish \
#         ~/.config/fish/completions/

# Echo the git-review verb on the command line (the first non-option token after
# `review`), or fail with no output if none has been typed yet.
function __grw_review_verb
    set -l tokens (commandline -opc)
    test (count $tokens) -ge 2; and test $tokens[1] = git; and test $tokens[2] = review
    or return 1
    for t in $tokens[3..-1]
        switch $t
            case '-*'
                continue
            case '*'
                echo $t
                return 0
        end
    end
    return 1
end

# True on `git review` before any verb is chosen — when to offer the verb list.
function __grw_review_bare
    not __grw_review_verb >/dev/null 2>&1
    and begin
        set -l tokens (commandline -opc)
        test (count $tokens) -ge 2; and test $tokens[1] = git; and test $tokens[2] = review
    end
end

# True when the chosen verb equals $verb.
function __grw_review_using -a verb
    test (__grw_review_verb 2>/dev/null) = $verb
end

# Local + remote branch names, for branch/commit-ish arguments.
function __grw_branches
    git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
end

# review/* branches with the prefix stripped, for clean.
function __grw_review_branches
    git for-each-ref --format='%(refname:short)' refs/heads/review/ 2>/dev/null \
        | string replace -r '^review/' ''
end

# Source branches that have a recorded --delta marker, for forget --delta. The
# markers outlive the review/* branches, so this is the right candidate set.
function __grw_marked_branches
    # Both marker sections, reviewworkflow.* (remote) and reviewworkflowlocal.*
    # (--local). A branch reviewed both ways collapses to one entry via sort -u, so
    # it shows once by its plain name (forget --delta <branch> clears both).
    begin
        git config --get-regexp '^reviewworkflow\..*\.reviewed$' 2>/dev/null
        git config --get-regexp '^reviewworkflowlocal\..*\.reviewed$' 2>/dev/null
    end \
        | string replace -r '^reviewworkflow(local)?\.(.*)\.reviewed .*$' '$2' \
        | sort -u
end

# Source branches with a saved review (review-saved/*), for continue and
# forget --saved.
function __grw_saved_branches
    git for-each-ref --format='%(refname:short)' refs/heads/review-saved/ 2>/dev/null \
        | string replace -r '^review-saved/' ''
end

# ── git review (no verb yet): dispatcher flags + the verb list ────────────────
complete -c git -n '__grw_review_bare' -f -l h -d 'list all available commands'
complete -c git -n '__grw_review_bare' -f -s V -l version -d 'print the installed version'
complete -c git -n '__grw_review_bare' -f -a start -d 'stage a PR diff on a new review/<branch> branch'
complete -c git -n '__grw_review_bare' -f -a compare -d 'stage the diff between two commit-ish, read-only'
complete -c git -n '__grw_review_bare' -f -a next -d 'advance a commit-by-commit review to the next commit'
complete -c git -n '__grw_review_bare' -f -a prev -d 'step a commit-by-commit review back to the previous commit'
complete -c git -n '__grw_review_bare' -f -a status -d 'show the state of the review on the current branch'
complete -c git -n '__grw_review_bare' -f -a list -d 'list every review/* branch in progress'
complete -c git -n '__grw_review_bare' -f -a preview -d 'show your edits so far without committing or switching'
complete -c git -n '__grw_review_bare' -f -a finish -d 'extract your edits onto review-fixes/<branch>'
complete -c git -n '__grw_review_bare' -f -a save -d 'pause the current review and return to where you started'
complete -c git -n '__grw_review_bare' -f -a continue -d 'resume a review paused with git review save'
complete -c git -n '__grw_review_bare' -f -a abort -d 'cancel the current review and return to where you started'
complete -c git -n '__grw_review_bare' -f -a clean -d 'delete review/* and review-fixes/* branches'
complete -c git -n '__grw_review_bare' -f -a forget -d "discard a review's persistent state (delta markers or a saved review)"

# ── git review start ──────────────────────────────────────────────────────────
complete -c git -n '__grw_review_using start' -f -r -l base -d 'base to diff against when the branch is omitted'
complete -c git -n '__grw_review_using start' -f -l delta -d 'review only commits since your last review'
complete -c git -n '__grw_review_using start' -f -l from -d 'review only commits after <commit>'
complete -c git -n '__grw_review_using start' -f -l step -d 'review one commit at a time'
complete -c git -n '__grw_review_using start' -f -l local -d 'review your local branches directly, without fetching'
complete -c git -n '__grw_review_using start' -f -l h -d 'show help'
complete -c git -n '__grw_review_using start' -f -a '(__grw_branches)'

# ── git review compare ────────────────────────────────────────────────────────
complete -c git -n '__grw_review_using compare' -f -l step -d 'review one commit at a time'
complete -c git -n '__grw_review_using compare' -f -l h -d 'show help'
complete -c git -n '__grw_review_using compare' -f -a '(__grw_branches)'

# ── git review finish ─────────────────────────────────────────────────────────
complete -c git -n '__grw_review_using finish' -f -l onto-source -d 'stage edits on the PR branch itself'
complete -c git -n '__grw_review_using finish' -f -l resume -d 'continue after resolving replay conflicts'
complete -c git -n '__grw_review_using finish' -f -l abort -d 'undo the last finish and return to editing'
complete -c git -n '__grw_review_using finish' -f -l force -d 'with --abort, discard changes made to the finish branch'
complete -c git -n '__grw_review_using finish' -f -l h -d 'show help'

# ── git review preview ────────────────────────────────────────────────────────
complete -c git -n '__grw_review_using preview' -f -l stat -d 'show a diffstat summary instead of the full diff'
complete -c git -n '__grw_review_using preview' -f -l h -d 'show help'

# ── git review continue ───────────────────────────────────────────────────────
complete -c git -n '__grw_review_using continue' -f -l h -d 'show help'
complete -c git -n '__grw_review_using continue' -f -a '(__grw_saved_branches)'

# ── git review clean ──────────────────────────────────────────────────────────
complete -c git -n '__grw_review_using clean' -f -l h -d 'show help'
complete -c git -n '__grw_review_using clean' -f -a '(__grw_review_branches)'

# ── git review forget (--delta acts on markers, --saved on review-saved/*) ─────
complete -c git -n '__grw_review_using forget' -f -l delta -d 'forget the --delta markers recorded by git review start'
complete -c git -n '__grw_review_using forget' -f -l saved -d 'discard a review paused with git review save'
complete -c git -n '__grw_review_using forget' -f -l all -d 'every marker (--delta) or every saved review (--saved)'
complete -c git -n '__grw_review_using forget' -f -l stale -d 'with --delta, forget markers whose branch is gone'
complete -c git -n '__grw_review_using forget' -f -l dry-run -d 'list what would be forgotten without forgetting it'
complete -c git -n '__grw_review_using forget' -f -l h -d 'show help'
# Offer saved branches once --saved is on the line, marked branches otherwise.
complete -c git -n '__grw_review_using forget; and __fish_contains_opt saved' -f -a '(__grw_saved_branches)'
complete -c git -n '__grw_review_using forget; and not __fish_contains_opt saved' -f -a '(__grw_marked_branches)'

# ── Verbs that take no arguments beyond --h ───────────────────────────────────
for verb in next prev status list abort save
    complete -c git -n "__grw_review_using $verb" -f -l h -d 'show help'
end
