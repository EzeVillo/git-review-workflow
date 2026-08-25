package com.ezevillo.gitreview.domain

enum class ReviewLayout {
    WALK, KEYS, STEP, WHOLE;

    val id: String
        get() = when (this) {
            WALK -> "walk"
            KEYS -> "keys"
            STEP -> "step"
            WHOLE -> "whole"
        }
}

enum class ReviewRange {
    FULL, DELTA;

    val id: String get() = when (this) {
        FULL -> "full"
        DELTA -> "delta"
    }
}

enum class ReviewSource {
    REMOTE, LOCAL, OFFLINE;

    val id: String
        get() = when (this) {
            REMOTE -> "remote"
            LOCAL -> "local"
            OFFLINE -> "offline"
        }

    companion object {
        fun parse(raw: String?): ReviewSource? = when (raw) {
            "remote" -> REMOTE
            "local" -> LOCAL
            "offline" -> OFFLINE
            else -> null
        }
    }
}

data class ReviewIntent(
    val branch: String? = null,
    val layout: ReviewLayout,
    val range: ReviewRange,
    val source: ReviewSource,
)

data class IntentValidationContext(
    val delta: DeltaRecord? = null,
)

sealed class IntentValidationResult {
    data object Ok : IntentValidationResult()
    data class Fail(val reason: String) : IntentValidationResult()
}

fun validateIntent(intent: ReviewIntent, context: IntentValidationContext): IntentValidationResult {
    if (intent.range == ReviewRange.DELTA && context.delta == null) {
        return IntentValidationResult.Fail(
            "range \"delta\" requires a prior review tip (delta record) for the chosen source",
        )
    }
    return IntentValidationResult.Ok
}

/**
 * Translates [ReviewIntent] to start argv (without the verb).
 * Order: layout flags → --delta? → --local|--offline? → -- → branch
 */
fun intentToArgs(intent: ReviewIntent, currentBranch: String): List<String> {
    val args = ArrayList<String>()
    when (intent.layout) {
        ReviewLayout.STEP -> args.add("--step")
        ReviewLayout.WHOLE -> args.add("--no-walk")
        ReviewLayout.KEYS -> args.add("--keys")
        ReviewLayout.WALK -> { /* no layout flags */ }
    }
    if (intent.range == ReviewRange.DELTA) args.add("--delta")
    when (intent.source) {
        ReviewSource.LOCAL -> args.add("--local")
        ReviewSource.OFFLINE -> args.add("--offline")
        ReviewSource.REMOTE -> { /* default */ }
    }
    args.add("--")
    args.add(intent.branch ?: currentBranch)
    return args
}

/**
 * Argv de `git review walkthrough draft` (011). El verbo es `walkthrough`;
 * `draft` es el primer argumento.
 *
 * Origen y rango son **los mismos** que el asistente ya resolvió: el borrador
 * tiene que listar los archivos de la review que se va a iniciar, no los de
 * otro rango. `--force` sólo cuando el revisor eligió *Start over* en el picker
 * de un borrador cuya review ya cerró: es lo único que hace desaparecer prosa,
 * y este archivo no está en git.
 */
@JvmOverloads
fun draftArgs(
    branch: String,
    source: ReviewSource,
    range: ReviewRange,
    build: Boolean,
    /**
     * Throws away what is there and writes a blank skeleton. Without it the verb
     * reconciles, which is what is wanted nearly always; with it there is no way
     * back, because this file is not in git.
     */
    force: Boolean = false,
): List<String> {
    val args = ArrayList<String>()
    args.add("draft")
    if (build) args.add("--build")
    if (force) args.add("--force")
    args.addAll(originAndRangeFlags(source, range))
    args.add("--")
    args.add(branch)
    return args
}

/**
 * The origin and range flags, in the order the CLI documents. One place,
 * because the three steps of *Validate and start* — `draft --build`, the
 * `config --porcelain` that follows and the final `start` — have to carry
 * exactly the same ones: if they differ, the three speak about different ranges.
 */
private fun originAndRangeFlags(source: ReviewSource, range: ReviewRange): List<String> {
    val args = ArrayList<String>()
    when (source) {
        ReviewSource.LOCAL -> args.add("--local")
        ReviewSource.OFFLINE -> args.add("--offline")
        ReviewSource.REMOTE -> { /* default */ }
    }
    if (range == ReviewRange.DELTA) args.add("--delta")
    return args
}

/**
 * `git review config --porcelain <flags> -- <branch>` for a draft row: invoked
 * after a green `--build` from the panel, only to learn whether that draft
 * carries essential entries (`offer keys`).
 *
 * The flags are not the defaults: they come from the `<source>`/`<range>`
 * fields of the `draft` record, which are the ones the CLI wrote into the
 * instruction block when it generated the skeleton.
 */
fun draftConfigArgs(branch: String, source: ReviewSource, range: ReviewRange): List<String> {
    val args = ArrayList<String>()
    args.add("--porcelain")
    args.addAll(originAndRangeFlags(source, range))
    args.add("--")
    args.add(branch)
    return args
}

/**
 * `git review forget --draft -- <branch>`: discard the draft of ONE row.
 *
 * Never `--all` (it would sweep the other rows, and archived ones nobody is
 * looking at) nor `--saved` (that is a paused review's prose), and never
 * without the branch.
 */
fun forgetDraftArgs(branch: String): List<String> = listOf("--draft", "--", branch)

/**
 * `git review walkthrough guide [--team]`: create an authoring guide, empty.
 *
 * The verb is `walkthrough`; `guide` is the first argument, like `draft`. No
 * branch and no origin or range flags: a guide covers no range. Never `--force`
 * -- the CLI refuses it anyway, because overwriting hand-written prose with an
 * empty file is not something a flag should be able to do.
 */
fun createGuideArgs(team: Boolean): List<String> =
    if (team) listOf("guide", "--team") else listOf("guide")

/**
 * `git review walkthrough guide --delete`: remove YOUR guide.
 *
 * Never with `--team`: the shared one is a tracked file, so taking it out is
 * `git rm` plus a commit, and the CLI refuses the combination.
 */
fun deleteGuideArgs(): List<String> = listOf("guide", "--delete")
