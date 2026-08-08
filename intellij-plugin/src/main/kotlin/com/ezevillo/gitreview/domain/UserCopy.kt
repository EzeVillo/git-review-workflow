package com.ezevillo.gitreview.domain

/**
 * User-facing copy shared with the VS Code extension.
 *
 * Keep strings byte-for-byte aligned with the VS Code command modules and
 * housekeeping confirm copy so both clients read the same language.
 */
object UserCopy {
    const val PRODUCT_TITLE = "git review"

    const val DISCARD_BUSY = MutationLock.DISCARD_REASON

    // --- Empty / config pickers -------------------------------------------------

    const val NO_BRANCHES_FOR_BASE = "No branches to pick a base from were found."
    const val NO_BRANCHES_FOR_REVIEW = "No branches to pick a review from were found."
    const val NO_REMOTES = "No remotes to pick from were found."
    const val NO_SAVED_REVIEWS = "No saved reviews."
    const val NOT_RESUMABLE = "That review is not resumable."
    const val NO_ACTIVE_PREVIEW = "No active review to preview."
    const val NO_SOLE_ROOT = "Need a single git repository root."
    const val COULD_NOT_READ_CONFIG = "Could not read the review configuration."
    const val COULD_NOT_PARSE_CONFIG = "Could not parse the review configuration."
    const val COULD_NOT_READ_OFFERS = "Could not read reading options for this branch."
    const val CONFIGURE_BASE_FIRST =
        "Configure a base branch first (git review → Set the Base Branch)."
    const val READONLY_FINISH =
        "This is a read-only compare review; there is nothing to finish. Use Cancel when done."
    const val OUT_OF_RANGE_FALLBACK =
        "Run 'git review status' in a terminal for the diagnosis and recovery command."

    const val SET_BASE_TITLE = "Set the base branch"
    const val SET_BASE_PROMPT =
        "Where PRs land (main, develop, …) — full reviews compare against it"
    const val SET_REMOTE_TITLE = "Set the remote"
    const val SET_REMOTE_PROMPT = "Remote a full review fetches from"

    // --- Start wizard -----------------------------------------------------------

    const val START_BRANCH_TITLE = "Start a review — branch"
    const val START_BRANCH_PLACEHOLDER = "Branch to review"
    const val START_ORIGIN_TITLE = "Start a review — origin"
    const val START_ORIGIN_PLACEHOLDER = "Remote, local, or offline"
    const val START_RANGE_TITLE = "Start a review — range"
    const val START_RANGE_PLACEHOLDER = "Full range, or only what is new since the last review"
    const val START_LAYOUT_TITLE = "Start a review — how to read it"
    const val START_LAYOUT_PLACEHOLDER =
        "Walkthrough, commit by commit, keys only, or whole diff"
    const val START_CONFIRM_BUTTON = "Start the review"

    val SOURCE_LABELS: List<Pair<ReviewSource, String>> = listOf(
        ReviewSource.REMOTE to "Remote — fetch and review the remote tip of the branch",
        ReviewSource.LOCAL to
            "Local — review the local branch without fetching; base may still use the remote",
        ReviewSource.OFFLINE to
            "Offline — review the local branch with no network; base is resolved locally",
    )

    val RANGE_LABELS: List<Pair<ReviewRange, String>> = listOf(
        ReviewRange.FULL to "Full range — everything since the base branch",
        ReviewRange.DELTA to
            "Only what is new — commits since your last review of this branch (--delta)",
    )

    fun startConfirmTitle(branch: String, layout: ReviewLayout): String =
        "Start reviewing $branch, ${layoutSummary(layout)}?"

    fun startConfirmDetail(args: List<String>, base: String?): String {
        val lines = mutableListOf("git review start ${args.joinToString(" ")}")
        if (base != null) lines.add("Comparing against $base.")
        return lines.joinToString("\n")
    }

    fun startingProgress(branch: String): String = "Starting the review of $branch…"

    const val START_STALE_WIZARD =
        "The repository changed while the wizard was open; nothing was started."
    const val START_STALE_RUN =
        "The repository changed before the start ran; nothing was started."
    const val START_FAILED = "git review start failed."

    // --- Continue / abort / save ------------------------------------------------

    fun continueTitle(source: String): String = "Continue the saved review of $source?"
    fun continueDetail(source: String): String =
        "This switches to review/$source and restores your edits in the working tree."
    const val CONTINUE_BUTTON = "Continue"
    fun continuingProgress(source: String): String = "Continuing the review of $source…"
    const val CONTINUE_STALE =
        "The review state changed before continue ran; nothing was resumed."
    const val CONTINUE_FAILED = "git review continue failed."

    fun abortTitle(source: String): String = "Cancel the review of $source?"
    const val ABORT_DETAIL =
        "This returns to the branch you started the review from; your uncommitted edits will be discarded."
    const val ABORT_BUTTON = "Cancel Review"
    fun abortingProgress(source: String): String = "Cancelling the review of $source…"
    const val ABORT_STALE =
        "The review state changed before the cancellation ran; nothing was cancelled."
    const val ABORT_FAILED = "git review abort failed."

    fun saveTitle(source: String): String = "Save the review of $source for later?"
    const val SAVE_DETAIL =
        "This pauses the review and returns to the branch you started from; your edits are kept and you can resume later."
    const val SAVE_BUTTON = "Save for Later"
    fun savingProgress(source: String): String = "Saving the review of $source for later…"
    const val SAVE_STALE =
        "The review state changed before the save ran; nothing was saved."
    const val SAVE_FAILED = "git review save failed."

    // --- Finish / undo / resume -------------------------------------------------

    fun finishLocationTitle(source: String): String =
        "Finish the review of $source — where do your edits go?"
    const val FINISH_LOCATION_PLACEHOLDER =
        "A separate branch, or onto the PR branch itself"

    val FINISH_LOCATION_SEPARATE =
        "A separate branch — review-fixes/<branch>, staged on top of the PR tip"
    val FINISH_LOCATION_ONTO =
        "Onto the PR branch itself — stage the edits directly on the PR branch"

    fun finishingProgress(source: String): String = "Finishing the review of $source…"
    const val FINISH_STALE_PICK =
        "The review state changed while choosing where to finish; nothing was finished."
    const val FINISH_STALE_RUN =
        "The review state changed before the finish ran; nothing was finished."
    const val FINISH_FAILED = "git review finish failed."

    fun finishSuccess(destination: String, outcome: FinishOutcome): String =
        when (outcome) {
            FinishOutcome.PENDING ->
                "$destination is ready. Undo is available if you need it."
            FinishOutcome.NO_EDITS -> "$destination is ready."
        }

    fun finishDestination(ontoSource: Boolean, source: String): String =
        if (ontoSource) source else "review-fixes/$source"

    const val UNDO_TITLE = "Undo this finish?"
    const val UNDO_DETAIL_PENDING =
        "This returns you to the review branch with your edits restored."
    const val UNDO_DETAIL_CONFLICT =
        "This discards any in-progress resolution and returns you to editing the review."
    const val UNDO_BUTTON = "Undo Finish"
    const val UNDOING_PROGRESS = "Undoing the finish…"
    const val UNDO_STALE =
        "The review state changed before the undo ran; nothing was undone."
    const val UNDO_ABORT_FAILED = "git review finish --abort failed."
    const val UNDO_FORCE_DETAIL =
        "Aborting with --force permanently discards the work made since the finish. This cannot be undone."
    const val UNDO_FORCE_BUTTON = "Discard Work and Undo"
    const val FORCE_UNDOING_PROGRESS = "Force-undoing the finish…"
    const val FORCE_UNDO_STALE =
        "The review state changed before the force-undo ran; nothing was undone."
    const val FORCE_UNDO_FAILED = "git review finish --abort --force failed."

    const val RESUME_PROGRESS = "Resuming the finish…"
    const val RESUME_FAILED = "git review finish --resume failed."

    // --- Compare / walkthrough / preview / housekeeping -------------------------

    const val COMPARE_LOWER_TITLE = "Compare: lower bound (from)"
    const val COMPARE_UPPER_TITLE = "Compare: upper bound (to)"
    const val COMPARE_LAYOUT_TITLE = "How to read the comparison"
    const val COMPARE_LAYOUT_PLACEHOLDER =
        "Walkthrough, keys only, commit by commit, or whole diff"
    const val COMPARE_CONFIRM_DETAIL =
        "Same effect as git review compare. Local changes must be clean."
    const val COMPARE_BUTTON = "Compare"
    const val COMPARE_FAILED = "git review compare failed."

    fun compareConfirmTitle(lower: String, upper: String, layout: ReviewLayout): String =
        "Compare $lower..$upper ${layoutSummary(layout)}? This creates a read-only review (finish will refuse)."

    fun comparingProgress(lower: String, upper: String): String =
        "Comparing $lower..$upper…"

    const val WALKTHROUGH_EXISTS_TITLE = "A walkthrough already exists. Overwrite it?"
    const val WALKTHROUGH_EXISTS_DETAIL =
        "This runs git review walkthrough init --force and replaces .review/walkthrough.md."
    const val WALKTHROUGH_OVERWRITE_BUTTON = "Overwrite"
    const val WALKTHROUGH_INIT_PROGRESS = "Initializing walkthrough…"
    const val WALKTHROUGH_OVERWRITE_PROGRESS = "Overwriting walkthrough…"
    const val WALKTHROUGH_INIT_FAILED = "git review walkthrough init failed."
    const val WALKTHROUGH_FORCE_FAILED = "git review walkthrough init --force failed."

    const val WALKTHROUGH_BUILD_TITLE = "Rebuild the walkthrough from your filled-in draft?"
    const val WALKTHROUGH_BUILD_DETAIL =
        "Validates .review/walkthrough.md, reorders entries and renumbers 1..N (git review walkthrough build)."
    const val WALKTHROUGH_BUILD_BUTTON = "Build"
    const val WALKTHROUGH_BUILD_PROGRESS = "Building walkthrough…"
    const val WALKTHROUGH_BUILD_FAILED = "git review walkthrough build failed."
    const val WALKTHROUGH_BUILT = "Walkthrough built."

    const val PREVIEW_FAILED = "git review preview failed."
    const val PREVIEW_EMPTY = "(no edits to preview)"

    const val HOUSEKEEPING_STALE =
        "The review state changed before the action ran; nothing was changed."

    const val CLEAN_PICK_TITLE = "Clean review leftovers"
    const val CLEAN_ONE_LABEL = "Clean leftovers for one branch…"
    const val CLEAN_ALL_LABEL = "Clean all leftover review branches"
    const val CLEAN_BRANCH_TITLE = "Branch to clean"
    const val CLEAN_BRANCH_PROMPT =
        "Source branch name (e.g. feature/checkout), not review/…"

    const val FORGET_PICK_TITLE = "Forget review state"
    const val FORGET_SAVED_ONE_LABEL = "Discard one saved review…"
    const val FORGET_SAVED_ALL_LABEL = "Discard every saved review"
    const val FORGET_DELTA_ONE_LABEL = "Forget delta marker for one branch…"
    const val FORGET_DELTA_ALL_LABEL = "Forget every delta marker"
    const val FORGET_DELTA_STALE_LABEL = "Forget stale delta markers"
    const val FORGET_SAVED_SOURCE_TITLE = "Saved review to discard"
    const val FORGET_DELTA_SOURCE_TITLE = "Branch for delta marker"
    const val FORGET_SOURCE_PROMPT = "Source branch name (e.g. feature/checkout)"
    const val ENTER_BRANCH_NAME = "Enter a branch name…"

    const val INSTALL_DOCS_URL =
        "https://github.com/EzeVillo/git-review-workflow#readme"

    // --- Navigate / open --------------------------------------------------------

    fun navigateFailed(direction: String): String = "git review $direction failed."

    const val OPEN_RANGE_FAILED = "Could not read the files of this review's range."
    fun openNoChangesLeft(display: String): String =
        "$display has no changes left in this review."
    fun openCommitFailed(sha: String): String = "Could not read the files of commit $sha."
    fun openCommitEmpty(sha: String): String = "Commit $sha changes no files."

    // --- Stale / generic fallbacks by action id ---------------------------------

    fun staleMessage(action: String, force: Boolean = false): String = when {
        force && action == "undoFinish" -> FORCE_UNDO_STALE
        action == "abortReview" -> ABORT_STALE
        action == "saveReview" -> SAVE_STALE
        action == "continueReview" -> CONTINUE_STALE
        action == "finishReview" -> FINISH_STALE_RUN
        action == "undoFinish" -> UNDO_STALE
        action == "startReview" -> START_STALE_RUN
        action == "cleanReview" || action == "forgetReview" -> HOUSEKEEPING_STALE
        else -> HOUSEKEEPING_STALE
    }

    fun failureFallback(action: String, params: ActionParams = ActionParams.Empty): String =
        when (action) {
            "abortReview" -> ABORT_FAILED
            "saveReview" -> SAVE_FAILED
            "continueReview" -> CONTINUE_FAILED
            "finishReview" -> FINISH_FAILED
            "undoFinish" -> when (params) {
                is ActionParams.UndoFinish ->
                    if (params.force) FORCE_UNDO_FAILED else UNDO_ABORT_FAILED
                else -> UNDO_ABORT_FAILED
            }
            "resumeFinish" -> RESUME_FAILED
            "compareReview" -> COMPARE_FAILED
            "walkthroughInit" -> when (params) {
                is ActionParams.WalkthroughInit ->
                    if (params.force) WALKTHROUGH_FORCE_FAILED else WALKTHROUGH_INIT_FAILED
                else -> WALKTHROUGH_INIT_FAILED
            }
            "walkthroughBuild" -> WALKTHROUGH_BUILD_FAILED
            "previewEdits", "previewEditsStat" -> PREVIEW_FAILED
            "setBase", "setRemote" -> "git review config failed."
            "next" -> navigateFailed("next")
            "prev" -> navigateFailed("prev")
            "startReview" -> START_FAILED
            "cleanReview", "forgetReview" -> {
                val hk = (params as? ActionParams.Housekeeping)?.action
                if (hk != null) {
                    "git review ${verbForHousekeeping(hk)} failed."
                } else {
                    "git review clean failed."
                }
            }
            else -> "git review $action failed."
        }
}
