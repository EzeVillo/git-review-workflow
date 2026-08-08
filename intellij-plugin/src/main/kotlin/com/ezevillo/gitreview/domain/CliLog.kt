package com.ezevillo.gitreview.domain

const val STDERR_MAX: Int = 2000

/** Quote one argv for log readability (not shell-reparseable). */
fun shellQuoteArg(arg: String): String {
    if (arg.isEmpty()) return "\"\""
    if (Regex("""[\s"\\]""").containsMatchIn(arg)) {
        return "\"${arg.replace("\\", "\\\\").replace("\"", "\\\"")}\""
    }
    return arg
}

fun formatCommandLine(command: String, args: List<String>): String =
    (listOf(command) + args.map { shellQuoteArg(it) }).joinToString(" ")

data class CliLogEnd(
    val exitCode: Int?,
    val errorCode: String? = null,
    val durationMs: Long,
    val stderr: String,
    val timedOut: Boolean = false,
)

/** Formats end-of-invocation log lines (pure; host chooses the sink). */
fun formatCliEnd(result: CliLogEnd): List<String> {
    val ms = "${result.durationMs}ms"
    if (result.timedOut) {
        return listOf("← timed out after $ms (killed)")
    }
    if (result.errorCode != null) {
        return listOf("← spawn failed ${result.errorCode}  $ms")
    }
    val line = "← exit ${result.exitCode ?: "null"}  $ms"
    if (result.exitCode == 0) {
        return listOf(line)
    }
    val lines = ArrayList<String>()
    lines.add(line)
    val err = result.stderr.trimEnd()
    if (err.isEmpty()) return lines
    val body = if (err.length > STDERR_MAX) {
        "${err.take(STDERR_MAX)}\n… (truncated)"
    } else err
    for (part in body.split(Regex("\r?\n"))) {
        lines.add("  $part")
    }
    return lines
}
