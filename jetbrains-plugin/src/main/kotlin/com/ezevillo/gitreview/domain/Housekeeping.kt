package com.ezevillo.gitreview.domain

enum class HousekeepingKind {
    CLEAN_ONE,
    CLEAN_KEEP_FIXES,
    CLEAN_FIXES_ONE,
    CLEAN_FIXES_ONE_ALL,
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
    /**
     * CLEAN_FIXES_ONE only: what the CLI reported about that branch, so the
     * confirmation can say how much it costs. Nothing is derived here -- the one
     * that can ask git is the CLI. Null reads as UNKNOWN.
     */
    val fixesState: FixesState? = null,
    /**
     * CLEAN_FIXES_ONE only: whether `review/<src>` still exists. It changes the
     * copy and nothing else -- the argv carries `--fixes-only` always, because a
     * value re-read on every refresh cannot decide which branches a command
     * deletes.
     */
    val session: Boolean = false,
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
    HousekeepingKind.CLEAN_FIXES_ONE -> {
        require(!action.source.isNullOrEmpty()) { "clean-fixes-only requires source" }
        listOf("--fixes-only", action.source)
    }
    // No branch: --fixes-only alone only ever touches review-fixes/* (clean's
    // own scoping, see bin/git-review-verbs/clean), so this never reaches a
    // live review/* session the way a bare CLEAN_ALL does.
    HousekeepingKind.CLEAN_FIXES_ONE_ALL -> listOf("--fixes-only")
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

/**
 * What the CLEAN_FIXES_ONE confirmation says about the cost. One sentence per
 * state and none folds into another: "nothing committed" is not "safe because it
 * is already integrated", and "unknown" is not "not integrated".
 */
private fun fixesCostSentence(state: FixesState?): String = when (state) {
    FixesState.EMPTY -> "Nothing was ever committed on it, so no work of yours is lost."
    FixesState.MERGED -> "Its commits are already in the base branch."
    FixesState.UNMERGED -> "It has commits the base branch does not have -- deleting it loses them."
    else -> "There is no base branch configured, so git cannot tell whether its commits are integrated."
}

fun confirmCopyFor(action: HousekeepingAction): ConfirmCopy {
    val src = action.source.orEmpty()
    return when (action.kind) {
        HousekeepingKind.CLEAN_ONE -> ConfirmCopy(
            title = "Delete the leftovers from reviewing $src?",
            detail = "This removes the review branch and any edits you extracted from it. Anything you already committed elsewhere stays. It cannot be undone.",
            button = "Delete",
        )
        HousekeepingKind.CLEAN_KEEP_FIXES -> {
            // Lo que se CONSERVA va primero, y no es un adorno: este dialogo
            // sale del boton que cierra el ciclo, y la unica duda que frena a
            // alguien ahi es si el clean se lleva sus ediciones. La respuesta es
            // que no, y decirla antes de nombrar lo que si se pierde es la
            // diferencia entre leer el cartel y apretar a ciegas.
            val destination = if (action.onto == true) src else "review-fixes/$src"
            ConfirmCopy(
                title = "Keep your edits & remove Undo?",
                detail = "Your edits stay on $destination - commit and push them from Source Control. What goes away is being able to undo this finish.",
                button = "Keep edits & remove Undo",
            )
        }
        HousekeepingKind.CLEAN_FIXES_ONE -> {
            // The session is named only when it exists: promising to leave
            // something that is not there is noise, and the argv is the same.
            val session = if (action.session) {
                " You can still undo the finish afterwards."
            } else {
                ""
            }
            ConfirmCopy(
                title = "Delete the edits you extracted from $src?",
                detail = fixesCostSentence(action.fixesState) + session + " It cannot be undone.",
                button = "Delete",
            )
        }
        HousekeepingKind.CLEAN_FIXES_ONE_ALL -> ConfirmCopy(
            title = "Delete every branch of extracted edits?",
            detail = "They hold edits you made while reviewing and never committed anywhere else. " +
                "Nothing you are reviewing right now is touched. It cannot be undone.",
            button = "Delete all",
        )
        HousekeepingKind.CLEAN_ALL -> ConfirmCopy(
            title = "Delete all review leftovers?",
            detail = "This removes every review branch and every branch of extracted edits that you are not currently on. Paused reviews and your last review points are left alone. It cannot be undone.",
            button = "Delete all",
        )
        HousekeepingKind.FORGET_SAVED_ONE -> ConfirmCopy(
            title = "Delete the paused review of $src?",
            detail = "This throws away the edits you had saved with it. It cannot be undone.",
            button = "Delete",
        )
        HousekeepingKind.FORGET_SAVED_ALL -> ConfirmCopy(
            title = "Delete every paused review?",
            detail = "This throws away the edits saved with each of them. It cannot be undone.",
            button = "Delete all",
        )
        // Los tres de --delta dicen la CONSECUENCIA y no la operacion, y la
        // dicen con la etiqueta que el asistente usa para el rango ("only what
        // is new"): quien vaya a apretar esto lo eligio alguna vez ahi, y es el
        // unico lugar donde ese dato se nota. "Removes the last-reviewed tip"
        // describia un ref que ninguna superficie del producto nombra.
        HousekeepingKind.FORGET_DELTA_ONE -> ConfirmCopy(
            title = "Forget where you got to on $src?",
            detail = "Next time you review this branch, \"only what is new\" will have no starting point, so you will be offered the full range instead.",
            button = "Forget",
        )
        HousekeepingKind.FORGET_DELTA_ALL -> ConfirmCopy(
            title = "Forget where you got to on every branch?",
            detail = "Next time you review any of them, \"only what is new\" will have no starting point, so you will be offered the full range instead.",
            button = "Forget all",
        )
        HousekeepingKind.FORGET_DELTA_STALE -> ConfirmCopy(
            title = "Forget the branches that are gone?",
            detail = "This clears where you got to on branches that no longer exist. It checks the remote first, so it may take a moment.",
            button = "Forget",
        )
    }
}
