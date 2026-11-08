package com.ezevillo.gitreview.domain

fun hasNavigationState(output: String): Boolean =
    output.lineSequence().map { it.removeSuffix("\r") }
        .count { it == "capability\tnavigation-state" } == 1

fun isNavigationReply(output: String): Boolean {
    val lines = output.lineSequence().map { it.removeSuffix("\r") }.toList()
    if (!hasNavigationState(output) || parseStateGuard(output) == null ||
        lines.count { it.startsWith("state\t") } != 1 ||
        lines.count { it.startsWith("navigation\t") } != 1 ||
        lines.none { it == "navigation\tmoved" || it == "navigation\tunchanged" }) return false
    return try {
        val parsed = parsePorcelain(output)
        parsed.state.branch.startsWith("review/") && parsed.finish == null &&
            parsed.state.mode in listOf(ReviewMode.WALK, ReviewMode.STEP)
    } catch (_: Exception) { false }
}

fun navigationNotice(output: String): String = output.lineSequence()
    .map { it.removeSuffix("\r") }.singleOrNull { it.startsWith("notice\t") }
    ?.removePrefix("notice\t").orEmpty()

/** null means unknown/invalid; empty means the CLI explicitly found no prose. */
fun parseInlineWhy(output: String): String? {
    val rows = output.lineSequence().map { it.removeSuffix("\r").split('\t') }.toList()
    val header = rows.singleOrNull { it.first() == "why" } ?: return null
    if (header.size != 3 || !Regex("0|[1-9][0-9]*").matches(header[2])) return null
    val count = header[2].toIntOrNull() ?: return null
    val lines = rows.filter { it.first() == "why-line" }
    if (header[1] == "absent") return "".takeIf { count == 0 && lines.isEmpty() }
    if (header[1] != "present" || count == 0 || count != lines.size) return null
    val result = StringBuilder()
    for ((index, row) in lines.withIndex()) {
        if (row.size != 3 || row[1] != (index + 1).toString()) return null
        var at = 0
        while (at < row[2].length) {
            val char = row[2][at++]
            if (char != '\\') result.append(char)
            else {
                if (at == row[2].length) return null
                result.append(when (row[2][at++]) { '\\' -> '\\'; 't' -> '\t'; 'r' -> '\r'; else -> return null })
            }
        }
        result.append('\n')
    }
    return result.toString()
}

fun whyFromText(text: String): PanelWhy = if (text.trim().isEmpty()) PanelWhy(WhyState.ABSENT)
else PanelWhy(WhyState.PRESENT, text = text.trimEnd())
