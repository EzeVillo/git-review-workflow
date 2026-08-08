package com.ezevillo.gitreview.domain

enum class FinishOutcome {
    NO_EDITS,
    PENDING,
}

/**
 * Decide toast after successful `finish` from refreshed state only — never
 * parse finish human stdout.
 */
fun finishOutcome(refreshed: ReviewState, branch: String): FinishOutcome {
    val pending = refreshed.branches.any { it.name == branch && it.finish?.state == "pending" }
    return if (pending) FinishOutcome.PENDING else FinishOutcome.NO_EDITS
}
