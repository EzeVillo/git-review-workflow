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

    /**
     * Lo que se dice cuando el testigo de estado (StaleGuard) rechaza una
     * mutacion porque el repositorio cambio entre la confirmacion y la
     * invocacion. **Uno solo para los ocho comandos**, y antes eran diez.
     *
     * Las diez variantes decian la misma cosa con el verbo cambiado -- "nothing
     * was finished", "nothing was saved", "nothing was undone" --, y ese verbo
     * no es informacion: es el boton que el revisor acaba de apretar, que
     * todavia tiene bajo el cursor. Lo unico que no puede deducir es POR QUE no
     * paso nada, y eso es identico en los diez casos.
     *
     * No lleva "try again": el panel ya se refresco solo, asi que el estado que
     * se ve al leer el mensaje es el nuevo. Decir que reintente seria pedirle
     * que repita una decision que quiza el estado nuevo ya volvio innecesaria.
     */
    const val STALE = "The repository changed while you were deciding, so nothing happened."

    // --- Empty / config pickers -------------------------------------------------

    const val NO_BRANCHES_FOR_BASE = "No branches to pick a base from were found."
    const val NO_BRANCHES_FOR_REVIEW = "No branches to pick a review from were found."
    const val NO_REMOTES = "No remotes to pick from were found."
    const val NO_SAVED_REVIEWS = "No saved reviews."

    // Los pickers de housekeeping están cerrados sobre lo que la CLI reportó, así que
    // con la lista vacía no hay nada que elegir. El de --delta nombra la salida que sí
    // alcanza a los marcadores huérfanos — el caso por el que ahí había texto libre.
    const val NO_REVIEWS_TO_CLEAN = "No reviews to clean were found."
    const val NO_REVIEWS_TO_DISCARD = "No reviews to discard were found."
    const val NO_DELTA_SOURCES =
        "No reviews were found to name a delta marker. " +
            "Use \"Forget stale delta markers\" for markers whose branch is gone."
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

    /**
     * What "Copy for agent" puts on the clipboard for one draft row.
     *
     * A pointer, not a prompt: the brief lives inside the file, in the
     * instruction block at the top, and repeating it here would give an agent
     * two sources for the same rules. [path] is the absolute path the CLI
     * reported for that row — never one this client built.
     *
     * Byte for byte identical to userCopy.ts and UserCopy.cs.
     */
    fun draftAgentPrompt(path: String): String =
        "Fill in the reading order at $path. The instructions are inside the file, " +
            "in the comment at the top. Do not change the file list or the numbering rules."

    /**
     * What "Copy for agent" puts on the clipboard for the author's own
     * walkthrough.
     *
     * A pointer, like the draft one, and for the same reason. Two sentences
     * differ, and both are about the situation rather than the format: the file
     * usually already holds finished prose (a walkthrough is written when the PR
     * is done, and then the PR keeps moving), so the one damaging thing an agent
     * can do here is rewrite it whole. Saying "fill in the reading order" over a
     * full file is an instruction to start over, and it would undo exactly what
     * updating in place exists to preserve.
     *
     * Byte for byte identical to userCopy.ts and UserCopy.cs.
     */
    fun walkthroughAgentPrompt(path: String): String =
        "Update the reading order at $path. The instructions are inside the file, " +
            "in the comment at the top. Entries that already have a number and a why are " +
            "finished: leave them as they are, and fill in only the ones marked \"## ?.\"."

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
    /**
     * El ULTIMO paso del asistente, y por eso lleva la rama: elegir una forma de
     * lectura aca ya arranca la review. La frase es la que decia la pantalla de
     * confirmacion que este paso reemplaza.
     */
    fun startLayoutTitle(branch: String): String =
        "Start reviewing $branch — how do you want to read it?"

    const val START_LAYOUT_PLACEHOLDER =
        "Walkthrough, commit by commit, keys only, or whole diff"

    /**
     * The only thing a draft `update` says that no row answers: what was kept,
     * what came in and what fell out. The row shows the NEW annotated/total
     * pair, never what moved to get there.
     *
     * Written here rather than forwarding the CLI's stdout, which says the same
     * with an absolute path and the next command -- and that command is the
     * *Validate and start* button on that very row. The three numbers arrive in
     * the `merged` record of `walkthrough draft --porcelain`: reading them out
     * of the human sentence would be parsing human output, which the contract
     * forbids.
     *
     * Zeroes are not spelled out. An update that adds and drops nothing is a
     * real outcome -- the range moved without changing which files it touches
     * -- and earns its sentence, but making somebody read "0 added, 0 dropped"
     * to find out neither happened is the noise this sentence exists to avoid.
     *
     * Byte for byte identical to userCopy.ts and UserCopy.cs.
     */
    fun draftUpdated(kept: Int, added: Int, dropped: Int): String {
        if (added == 0 && dropped == 0) {
            return "Reading order updated: nothing moved, $kept kept."
        }
        val text = StringBuilder("Reading order updated: $kept kept")
        if (added > 0) text.append(", $added added")
        if (dropped > 0) text.append(", $dropped no longer in the PR")
        return "$text."
    }

    // --- Reviewer's draft walkthrough (011) -------------------------------------

    const val DRAFT_FAILED = "Could not draft a reading order."
    const val DRAFT_BUILD_FAILED = "Could not check your reading order."
    const val DRAFT_KEYS_PLACEHOLDER =
        "Your draft marks key entries: read all of them, or only those"

    fun draftProgress(branch: String, build: Boolean): String =
        if (build) "Validating your draft for $branch…" else "Drafting a walkthrough for $branch…"

    // --- Bloque de borradores del panel (012) -----------------------------------

    const val DISCARD_DRAFT_BUTTON = "Discard"

    fun discardDraftTitle(branch: String): String =
        "Discard the reading order you wrote for $branch?"

    fun discardDraftDetail(branch: String, path: String): String =
        "This deletes $path. It cannot be undone."

    fun discardDraftProgress(branch: String): String =
        "Discarding the reading order for $branch…"

    const val DISCARD_GUIDE_BUTTON = "Discard"

    const val DISCARD_GUIDE_TITLE = "Discard the authoring guide you wrote?"

    fun discardGuideDetail(path: String): String =
        "This deletes $path. It cannot be undone."

    const val DISCARD_GUIDE_PROGRESS = "Discarding your authoring guide…"

    const val CREATE_GUIDE_PROGRESS = "Creating the authoring guide…"

    /** Recorrido completo vs sólo esenciales, tras validar un borrador con keys. */
    val DRAFT_KEYS_LABELS: List<Pair<Boolean, String>> = listOf(
        false to "Walkthrough — the whole reading order you wrote",
        true to "Walkthrough — keys only — only the entries you marked key",
    )

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
            "Only what is new — commits since your last review of this branch",
    )

    fun startingProgress(branch: String): String = "Starting the review of $branch…"

    const val START_FAILED = "Could not start the review."

    // --- Continue / abort / save ------------------------------------------------

    fun continueTitle(source: String): String = "Continue the saved review of $source?"
    fun continueDetail(source: String): String =
        "This switches to review/$source and restores your edits in the working tree."
    const val CONTINUE_BUTTON = "Continue"
    fun continuingProgress(source: String): String = "Continuing the review of $source…"
    const val CONTINUE_FAILED = "Could not resume the review."

    fun abortTitle(source: String): String = "Cancel the review of $source?"
    const val ABORT_DETAIL =
        "This returns to the branch you started the review from; your uncommitted edits will be discarded."
    const val ABORT_BUTTON = "Cancel Review"
    fun abortingProgress(source: String): String = "Cancelling the review of $source…"
    const val ABORT_FAILED = "Could not cancel the review."

    fun saveTitle(source: String): String = "Save the review of $source for later?"
    const val SAVE_DETAIL =
        "This pauses the review and returns to the branch you started from; your edits are kept and you can resume later."
    const val SAVE_BUTTON = "Save for Later"
    fun savingProgress(source: String): String = "Saving the review of $source for later…"
    const val SAVE_FAILED = "Could not pause the review."

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
    const val FINISH_FAILED = "Could not finish the review."

    /**
     * El acuse de un finish en verde, o `null` cuando el panel ya lo dio.
     *
     * `PENDING` es el caso normal y devuelve null: el panel entra en
     * finish-pending y su banner dice lo mismo con mas contexto -- el destino,
     * que hay que commitear desde Source Control, y los dos botones --. El
     * toast era esa frase otra vez, un segundo antes.
     *
     * `NO_EDITS` es el residual: sin registro pending no hay banner, asi que sin
     * esta linea un finish exitoso no dejaria ninguna senal.
     */
    fun finishSuccess(destination: String, outcome: FinishOutcome): String? =
        when (outcome) {
            FinishOutcome.PENDING -> null
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
    const val UNDO_ABORT_FAILED = "Could not undo the finish."
    const val UNDO_FORCE_DETAIL =
        "This permanently discards the work made since the finish. It cannot be undone."
    const val UNDO_FORCE_BUTTON = "Discard Work and Undo"
    const val FORCE_UNDOING_PROGRESS = "Force-undoing the finish…"
    const val FORCE_UNDO_FAILED = "Could not undo the finish, even discarding the newer work."

    const val RESUME_PROGRESS = "Resuming the finish…"
    const val RESUME_FAILED = "Could not continue the finish."

    // --- Compare / walkthrough / preview / housekeeping -------------------------

    const val COMPARE_LOWER_TITLE = "Compare: lower bound (from)"
    const val COMPARE_UPPER_TITLE = "Compare: upper bound (to)"
    const val COMPARE_LAYOUT_TITLE = "How to read the comparison"
    const val COMPARE_LAYOUT_PLACEHOLDER =
        "Walkthrough, keys only, commit by commit, or whole diff"
    const val COMPARE_CONFIRM_DETAIL =
        "Your working tree must be clean to start it."
    const val COMPARE_BUTTON = "Compare"
    const val COMPARE_FAILED = "Could not compare those two revisions."

    fun compareConfirmTitle(lower: String, upper: String, layout: ReviewLayout): String =
        "Compare $lower..$upper ${layoutSummary(layout)}? This creates a read-only review (finish will refuse)."

    fun comparingProgress(lower: String, upper: String): String =
        "Comparing $lower..$upper…"

    /**
     * The choice between reconciling a walkthrough and starting it over, asked
     * BEFORE the verb runs.
     *
     * It used to hang off the CLI FAILING: init ran, and when it died because
     * the file was already there, that is where the three clients offered to
     * overwrite. Since init updates instead of refusing, that path stopped
     * existing -- and with it the only way to reach --force from a panel.
     *
     * Byte for byte identical to userCopy.ts and UserCopy.cs.
     */
    const val WALKTHROUGH_EXISTS_TITLE = "This branch already has a walkthrough."
    const val WALKTHROUGH_EXISTS_DETAIL =
        "Update keeps everything you already wrote for files that are still in the PR, and adds the ones that are new.\n\n" +
            "Start over replaces it with a blank list. The file is committed to the PR, so git checkout -- .review/walkthrough.md brings the old one back."
    /**
     * Del lado del REVISOR no hay par equivalente, y la asimetria es deliberada.
     *
     * Hubo uno: un modal que, sobre cualquier borrador cuya review ya habia
     * cerrado, preguntaba si reconciliar o empezar de cero. Preguntaba porque el
     * asistente no podia saber cual de las dos cosas hacia falta -- el `state`
     * del registro `draft` dice si el orden ya se leyo, no si sigue cubriendo el
     * rango --, asi que le pasaba la duda al revisor. Ahora la contesta la CLI,
     * que es la que tiene los dos tips, ofreciendo `draft-update` solo cuando hay
     * algo que reconciliar; sin pregunta, no hay modal.
     *
     * Y empezar de cero no se repone aca: del lado del autor el archivo esta
     * trackeado y `git checkout --` lo devuelve, del lado del revisor vive fuera
     * de git y no hay vuelta atras. Un boton para eso no va en un paso por el que
     * se pasa de largo; va en Discard, que confirma.
     */
    const val WALKTHROUGH_UPDATE_BUTTON = "Update"
    const val WALKTHROUGH_START_OVER_BUTTON = "Start over"
    const val WALKTHROUGH_INIT_PROGRESS = "Initializing walkthrough…"
    const val WALKTHROUGH_OVERWRITE_PROGRESS = "Overwriting walkthrough…"
    const val WALKTHROUGH_INIT_FAILED = "Could not create the walkthrough."
    const val WALKTHROUGH_FORCE_FAILED = "Could not replace the walkthrough."

    const val WALKTHROUGH_BUILD_TITLE = "Check and renumber the walkthrough?"
    const val WALKTHROUGH_BUILD_DETAIL =
        "This puts the files in the order you wrote and numbers them 1 to N. If something is missing, nothing changes and you will see what to fix."
    const val WALKTHROUGH_BUILD_BUTTON = "Build"
    const val WALKTHROUGH_BUILD_PROGRESS = "Building walkthrough…"
    const val WALKTHROUGH_BUILD_FAILED = "Could not build the walkthrough."

    const val PREVIEW_FAILED = "Could not preview your edits."
    const val PREVIEW_EMPTY = "(no edits to preview)"

    const val CLEAN_PICK_TITLE = "Clean review leftovers"
    const val CLEAN_ONE_LABEL = "Clean leftovers for one branch…"
    const val CLEAN_ALL_LABEL = "Clean all leftover review branches"
    const val CLEAN_BRANCH_TITLE = "Branch to clean"
    const val FORGET_PICK_TITLE = "Forget review state"
    const val FORGET_SAVED_ONE_LABEL = "Discard one saved review…"
    const val FORGET_SAVED_ALL_LABEL = "Discard every saved review"
    const val FORGET_DELTA_ONE_LABEL = "Forget delta marker for one branch…"
    const val FORGET_DELTA_ALL_LABEL = "Forget every delta marker"
    const val FORGET_DELTA_STALE_LABEL = "Forget stale delta markers"
    const val FORGET_SAVED_SOURCE_TITLE = "Saved review to discard"
    const val FORGET_DELTA_SOURCE_TITLE = "Branch for delta marker"

    const val INSTALL_DOCS_URL =
        "https://github.com/EzeVillo/git-review-workflow#readme"

    // --- Navigate / open --------------------------------------------------------

    fun navigateFailed(direction: String): String =
        if (direction == "next") "Could not move to the next entry."
        else "Could not move to the previous entry."

    const val OPEN_RANGE_FAILED = "Could not read the files of this review's range."
    fun openNoChangesLeft(display: String): String =
        "$display has no changes left in this review."
    const val OPEN_RANGE_EMPTY = "This review's range does not touch any files."
    fun openCommitFailed(sha: String): String = "Could not read the files of commit $sha."
    fun openCommitEmpty(sha: String): String = "Commit $sha changes no files."

    // --- Generic fallbacks by action id -----------------------------------------

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
            "setBase", "setRemote" -> "Could not save the setting."
            "next" -> navigateFailed("next")
            "prev" -> navigateFailed("prev")
            "startReview" -> START_FAILED
            "cleanReview", "forgetReview" -> {
                val hk = (params as? ActionParams.Housekeeping)?.action
                if (hk != null) {
                    if (verbForHousekeeping(hk) == "forget") {
                        "Could not forget that."
                    } else {
                        "Could not clean up."
                    }
                } else {
                    "Could not clean up."
                }
            }
            else -> "Something went wrong."
        }
}
