package com.ezevillo.gitreview.domain

/**
 * Outcome of an invocation (data-model.md § Situation). Pure logic, no IDE.
 */
enum class Situation {
    REVIEW,
    NO_REVIEW,
    OUT_OF_RANGE,
    ERROR,
    CLI_MISSING,
    CLI_OUTDATED,
    FINISH_CONFLICT,
    FINISH_PENDING,
    ;

    /** Wire / UI id matching the VS Code extension (`review`, `cli-missing`, …). */
    val id: String
        get() = when (this) {
            REVIEW -> "review"
            NO_REVIEW -> "no-review"
            OUT_OF_RANGE -> "out-of-range"
            ERROR -> "error"
            CLI_MISSING -> "cli-missing"
            CLI_OUTDATED -> "cli-outdated"
            FINISH_CONFLICT -> "finish-conflict"
            FINISH_PENDING -> "finish-pending"
        }

    companion object {
        fun fromId(id: String): Situation? = entries.find { it.id == id }
    }
}

/**
 * Maps `status --porcelain` exit code to [Situation]. Unknown codes (including 1)
 * are always [Situation.ERROR], never [Situation.REVIEW].
 */
fun situationForExitCode(exitCode: Int?): Situation = when (exitCode) {
    0 -> Situation.REVIEW
    2 -> Situation.NO_REVIEW
    3 -> Situation.OUT_OF_RANGE
    else -> Situation.ERROR
}

/**
 * Extends [situationForExitCode] with finish records:
 * `finish-conflict` over `review`, `finish-pending` over `no-review`.
 */
fun situationFor(
    exitCode: Int?,
    hasFinishConflict: Boolean,
    hasFinishPending: Boolean,
): Situation {
    val base = situationForExitCode(exitCode)
    if (base == Situation.REVIEW && hasFinishConflict) return Situation.FINISH_CONFLICT
    if (base == Situation.NO_REVIEW && hasFinishPending) return Situation.FINISH_PENDING
    return base
}

/**
 * Situations where [ReviewState] has a populated state record and read/open
 * commands are safe: active review or finish-conflict.
 */
fun isReviewReadable(situation: Situation): Boolean =
    situation == Situation.REVIEW || situation == Situation.FINISH_CONFLICT
