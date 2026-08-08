package com.ezevillo.gitreview.domain

data class StateToken(
    val branch: String? = null,
    val tip: String? = null,
    val situation: Situation,
)

fun captureToken(state: ReviewState): StateToken = StateToken(
    branch = state.state?.branch,
    tip = state.state?.tip,
    situation = state.situation,
)

fun tokenStillValid(token: StateToken, state: ReviewState): Boolean =
    token.situation == state.situation &&
        token.branch == state.state?.branch &&
        token.tip == state.state?.tip
