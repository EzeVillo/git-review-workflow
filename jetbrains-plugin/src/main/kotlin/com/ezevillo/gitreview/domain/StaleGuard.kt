package com.ezevillo.gitreview.domain

data class StateToken(
    val branch: String? = null,
    val tip: String? = null,
    val situation: Situation,
    val guard: String? = null,
)

fun captureToken(state: ReviewState): StateToken = StateToken(
    branch = state.state?.branch,
    tip = state.state?.tip,
    situation = state.situation,
    guard = state.guard,
)

fun tokenStillValid(token: StateToken, state: ReviewState): Boolean =
    token.situation == state.situation &&
        token.branch == state.state?.branch &&
        token.tip == state.state?.tip && token.guard == state.guard

fun parseStateGuard(output: String): String? {
    val guards = output.lineSequence().map { it.removeSuffix("\r") }
        .filter { it.startsWith("guard\t") }.map { it.removePrefix("guard\t") }.toList()
    return guards.singleOrNull()?.takeIf { Regex("(?:[0-9a-f]{40}|[0-9a-f]{64})").matches(it) }
}
