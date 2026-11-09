package com.ezevillo.gitreview.domain

fun parseContinueGuard(output: String): String? {
    val lines = output.lineSequence().map { it.removeSuffix("\r") }.toList()
    if (lines.count { it == "capability\tcontinue-state" } != 1) return null
    return lines.singleOrNull { it.startsWith("continue-guard\t") }
        ?.removePrefix("continue-guard\t")?.takeIf { Regex("(?:[0-9a-f]{40}|[0-9a-f]{64})").matches(it) }
}

fun isContinueReply(output: String): Boolean {
    val lines = output.replace("\r\n", "\n").removeSuffix("\n").split("\n")
    if (lines.firstOrNull() != "continue-state\t1" || lines.lastOrNull() != "continue-state\tcomplete" ||
        lines.count { it.startsWith("continue-state\t") } != 2 ||
        lines.count { it.startsWith("state\t") } != 1 || parseStateGuard(output) == null) return false
    return try {
        val parsed = parsePorcelain(output)
        parsed.state.branch.startsWith("review/") && parsed.finish == null &&
            parsed.state.mode in listOf(ReviewMode.WHOLE, ReviewMode.STEP, ReviewMode.WALK)
    } catch (_: Exception) { false }
}
