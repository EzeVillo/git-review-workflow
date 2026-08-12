package com.ezevillo.gitreview.domain

enum class InvocationClass {
    READ,
    LOCAL_MUTATION,
    NETWORK,
    SUPPORT_GIT,
}

const val READ_TIMEOUT_MS: Long = 15_000
const val LOCAL_MUTATION_TIMEOUT_MS: Long = 120_000
const val NETWORK_MUTATION_TIMEOUT_MS: Long = 300_000
const val SUPPORT_GIT_TIMEOUT_MS: Long = 30_000

private val LOCAL_MUTATION_VERBS = setOf(
    "finish", "save", "abort", "continue", "next", "prev",
    "clean", "forget", "compare", "walkthrough", "preview",
)

private val NETWORK_MUTATION_VERBS = setOf("start")

fun timeoutForClass(verb: String, args: List<String>): Long {
    if (verb in NETWORK_MUTATION_VERBS) return NETWORK_MUTATION_TIMEOUT_MS
    if (verb == "forget" && "--stale" in args) return NETWORK_MUTATION_TIMEOUT_MS
    if (verb in LOCAL_MUTATION_VERBS) return LOCAL_MUTATION_TIMEOUT_MS
    return READ_TIMEOUT_MS
}

fun timeoutMs(invocationClass: InvocationClass): Long = when (invocationClass) {
    InvocationClass.READ -> READ_TIMEOUT_MS
    InvocationClass.LOCAL_MUTATION -> LOCAL_MUTATION_TIMEOUT_MS
    InvocationClass.NETWORK -> NETWORK_MUTATION_TIMEOUT_MS
    InvocationClass.SUPPORT_GIT -> SUPPORT_GIT_TIMEOUT_MS
}
