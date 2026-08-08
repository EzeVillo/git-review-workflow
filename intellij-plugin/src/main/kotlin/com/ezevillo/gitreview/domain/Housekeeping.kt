package com.ezevillo.gitreview.domain

enum class HousekeepingKind {
    CLEAN_ONE,
    CLEAN_KEEP_FIXES,
    CLEAN_ALL,
    FORGET_SAVED_ONE,
    FORGET_SAVED_ALL,
    FORGET_DELTA_ONE,
    FORGET_DELTA_ALL,
    FORGET_DELTA_STALE,
}

data class HousekeepingAction(
    val kind: HousekeepingKind,
    val source: String? = null,
    val onto: Boolean? = null,
)

data class ConfirmCopy(
    val title: String,
    val detail: String,
    val button: String,
)

fun sourceFromReviewName(name: String): String {
    for (prefix in listOf("review-saved/", "review/", "review-fixes/")) {
        if (name.startsWith(prefix)) return name.removePrefix(prefix)
    }
    return name
}

fun pendingFinishInfo(state: ReviewState): Pair<String, Boolean>? {
    if (state.situation != Situation.FINISH_PENDING) return null
    val pending = state.branches.find { it.finish?.state == "pending" } ?: return null
    val finish = pending.finish ?: return null
    return sourceOf(pending) to finish.onto
}

fun pendingFinishSource(state: ReviewState): String? = pendingFinishInfo(state)?.first

fun verbForHousekeeping(action: HousekeepingAction): String =
    if (action.kind.name.startsWith("CLEAN")) "clean" else "forget"

fun argsForHousekeeping(action: HousekeepingAction): List<String> = when (action.kind) {
    HousekeepingKind.CLEAN_ONE -> {
        require(!action.source.isNullOrEmpty()) { "clean-one requires source" }
        listOf(action.source)
    }
    HousekeepingKind.CLEAN_KEEP_FIXES -> {
        require(!action.source.isNullOrEmpty()) { "clean-keep-fixes requires source" }
        listOf("--keep-fixes", action.source)
    }
    HousekeepingKind.CLEAN_ALL -> emptyList()
    HousekeepingKind.FORGET_SAVED_ONE -> {
        require(!action.source.isNullOrEmpty()) { "forget-saved-one requires source" }
        listOf("--saved", action.source)
    }
    HousekeepingKind.FORGET_SAVED_ALL -> listOf("--saved", "--all")
    HousekeepingKind.FORGET_DELTA_ONE -> {
        require(!action.source.isNullOrEmpty()) { "forget-delta-one requires source" }
        listOf("--delta", action.source)
    }
    HousekeepingKind.FORGET_DELTA_ALL -> listOf("--delta", "--all")
    HousekeepingKind.FORGET_DELTA_STALE -> listOf("--delta", "--stale")
}

fun housekeepingNeedsNetwork(action: HousekeepingAction): Boolean =
    action.kind == HousekeepingKind.FORGET_DELTA_STALE

fun confirmCopyFor(action: HousekeepingAction): ConfirmCopy {
    val src = action.source.orEmpty()
    return when (action.kind) {
        HousekeepingKind.CLEAN_ONE -> ConfirmCopy(
            title = "Clean leftover review branches for $src?",
            detail = "Deletes review/$src and review-fixes/$src (and banked edit refs) if they exist and are not checked out. Does not touch delta markers.",
            button = "Clean",
        )
        HousekeepingKind.CLEAN_KEEP_FIXES -> {
            val destination = if (action.onto == true) src else "review-fixes/$src"
            ConfirmCopy(
                title = "Drop the finish undo for $src?",
                detail = "Runs git review clean --keep-fixes $src: deletes review/$src and the finish undo point so the pending finish goes away. Your staged edits stay on $destination; delta markers are left alone. Remember to commit and push them from Source Control.",
                button = "Clean",
            )
        }
        HousekeepingKind.CLEAN_ALL -> ConfirmCopy(
            title = "Clean all leftover review branches?",
            detail = "Deletes every review/* and review-fixes/* branch that is not currently checked out, plus orphaned edit/undo refs. Does not touch delta markers or saved reviews.",
            button = "Clean All",
        )
        HousekeepingKind.FORGET_SAVED_ONE -> ConfirmCopy(
            title = "Discard the saved review of $src?",
            detail = "Deletes review-saved/$src, its banked edits and metadata, and rolls back the delta marker it left.",
            button = "Discard",
        )
        HousekeepingKind.FORGET_SAVED_ALL -> ConfirmCopy(
            title = "Discard every saved review?",
            detail = "Deletes all review-saved/* branches, their banked edits and metadata, and rolls back their delta markers.",
            button = "Discard All Saved",
        )
        HousekeepingKind.FORGET_DELTA_ONE -> ConfirmCopy(
            title = "Forget the delta marker for $src?",
            detail = "Removes the last-reviewed tip used by git review start --delta for this branch (remote and local markers).",
            button = "Forget Marker",
        )
        HousekeepingKind.FORGET_DELTA_ALL -> ConfirmCopy(
            title = "Forget every delta marker?",
            detail = "Removes all last-reviewed tips used by git review start --delta.",
            button = "Forget All Markers",
        )
        HousekeepingKind.FORGET_DELTA_STALE -> ConfirmCopy(
            title = "Forget stale delta markers?",
            detail = "Fetches from the remote (when needed) and removes markers whose branch no longer exists.",
            button = "Forget Stale",
        )
    }
}
