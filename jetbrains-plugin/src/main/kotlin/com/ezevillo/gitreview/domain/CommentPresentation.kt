package com.ezevillo.gitreview.domain

data class CommentPresentation(val ordinal: Int, val label: String, val body: String, val location: String, val version: String, val preview: String, val warning: String = "", val canOpenDiff: Boolean = false)
fun decodeComment(value: String): String = Regex("%(25|09|0D|0A|3E)").replace(value) {
    when (it.groupValues[1]) { "25" -> "%"; "09" -> "\t"; "0D" -> "\r"; "0A" -> "\n"; else -> ">" }
}
fun presentComment(report: CommentsReport, entry: List<String>): CommentPresentation {
    fun rows(tag: String) = report.records(tag).filter { it[0] == entry[0] }
    val body = rows("comment-body").map { decodeComment(it[1]) }.dropWhile { it.isBlank() }.dropLastWhile { it.isBlank() }.joinToString("\n")
    val scope = rows("comment-scope").firstOrNull()
    val line = rows("comment-location").firstOrNull()
    val columns = rows("comment-columns").firstOrNull()
    val side = scope?.get(2) ?: line?.get(1)
    val path = rows("comment-path").firstOrNull { it[1] == side }?.get(2)
    val location = when {
        scope?.get(1) == "general" -> CommentsCopy.general
        path != null -> decodeComment(path) +
            (line?.let { ":${it[2]}${columns?.let { c -> ":${c[2]}" }.orEmpty()}–${it[3]}${columns?.let { c -> ":${c[3]}" }.orEmpty()}" } ?: "") + " · " + if (side == "base") CommentsCopy.baseSide else CommentsCopy.headSide
        else -> CommentsCopy.locationUnavailable
    }
    val version = rows("comment-version").firstOrNull()?.let { "${CommentsCopy.originalChanges} · ${it[1].take(8)} → ${it[2].take(8)}" }.orEmpty()
    val warning = if (rows("comment-unversioned").isNotEmpty()) CommentsCopy.originalUnversioned else ""
    val title = if (entry[3] == (path?.let(::decodeComment) ?: location)) location else entry[3] + " · " + location
    val preview = body.replace(Regex("\\s+"), " ").trim().codePoints().toArray()
    val excerpt = if (preview.size > 160) String(preview, 0, 159) + "…" else String(preview, 0, preview.size)
    return CommentPresentation(entry[0].toInt(), entry[1] + ". " + title, body.ifBlank { CommentsCopy.noBody }, location, version, excerpt, warning, scope?.get(1) != "general" && path != null)
}
