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
 * otro rango. Nunca `--force`: pisar un borrador empezado se pide a mano.
 */
fun draftArgs(
    branch: String,
    source: ReviewSource,
    range: ReviewRange,
    build: Boolean,
): List<String> {
    val args = ArrayList<String>()
    args.add("draft")
    if (build) args.add("--build")
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
