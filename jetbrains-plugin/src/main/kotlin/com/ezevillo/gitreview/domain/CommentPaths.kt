package com.ezevillo.gitreview.domain

fun hasCommentPaths(output: String): Boolean = output.lineSequence().count { it == "capability\tcomments-paths" } == 1
data class CommentPaths(val paths: List<String>?)
fun parseCommentPaths(output: String, guard: String): CommentPaths? {
    val lines = output.replace("\r\n", "\n").removeSuffix("\n").split("\n")
    val head = lines.first().split("\t")
    val token = Regex("(?:[0-9a-f]{40}|[0-9a-f]{64})")
    if (head.size != 4 || head[0] != "comments-paths" || head[1] != "1" || !token.matches(guard) ||
        head[2] != guard || lines.last() != "comments-paths\tcomplete") return null
    if (head[3] == "legacy") return if (lines.size == 2) CommentPaths(null) else null
    if (!token.matches(head[3]) || lines.size != 4) return null
    val paths = mutableListOf<String>()
    for ((i, kind) in listOf("local", "shared").withIndex()) {
        val prefix = "comments-path\t$kind\t"
        if (!lines[i + 1].startsWith(prefix)) return null
        val raw = lines[i + 1].removePrefix(prefix)
        if (raw.isEmpty() || Regex("%(?!25|09|0A|0D|3E)").containsMatchIn(raw)) return null
        paths += Regex("%[0-9A-F]{2}").replace(raw) { when (it.value) {
            "%25" -> "%"; "%09" -> "\t"; "%0A" -> "\n"; "%0D" -> "\r"; "%3E" -> ">"; else -> error("invalid path escape")
        } }
    }
    return CommentPaths(paths)
}
