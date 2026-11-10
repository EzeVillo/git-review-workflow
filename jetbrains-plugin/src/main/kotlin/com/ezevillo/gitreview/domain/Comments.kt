package com.ezevillo.gitreview.domain

data class CommentRow(val tag: String, val fields: List<String>)
data class CommentDocument(val path: String, val context: String, val kind: String, val presence: String, val revision: String, val count: Int? = null)
data class CommentsReport(val rows: List<CommentRow> = emptyList(), val loading: Boolean = false) {
    fun records(tag: String) = rows.filter { it.tag == tag }.map { it.fields }
    fun destinations(operation: String = "add"): List<String> = records("comments-capability").filter { it[0] == operation && it[1] in listOf("local", "shared") }.map { it[1] }.distinct()
    val guard: String? get() = records("comments-guard").firstOrNull()?.firstOrNull()
    val supportsAddReply: Boolean get() = records("comments-add-reply").any { it[0] == "1" }
    val documents: List<CommentDocument> get() = records("comments-document").filter { it.size >= 5 }.map { f ->
        CommentDocument(f[0], f[1], f[2], f[3], f[4], records("comments-count").firstOrNull { it.size >= 2 && it[0] == f[0] }?.get(1)?.toIntOrNull()?.takeIf { it >= 0 })
    }
}

data class CommentsAddReply(val before: String, val after: String, val report: CommentsReport)

fun parseCommentsAddReply(text: String, document: String): CommentsAddReply? {
    val lines = text.trimEnd('\r', '\n').lines()
    val header = lines.first().split('\t')
    val token = Regex("[0-9a-f]{40}(?:[0-9a-f]{24})?")
    if (header.size != 4 || header[0] != "comments-add-result" || header[1] != "1" ||
        !token.matches(header[2]) || !token.matches(header[3]) || lines.last() != "comments-add-result-end\t1") return null
    val report = parseComments(lines.drop(1).dropLast(1).joinToString("\n"))
    val active = report.records("comments-context").singleOrNull { it[2] == "active" } ?: return null
    val guard = report.guard ?: return null
    if (!token.matches(guard) || active[3] != guard || report.records("comments-identity").singleOrNull()?.get(0) != "resolved" ||
        report.documents.none { it.context == active[0] && it.kind == document && it.presence == "present" && token.matches(it.revision) && (it.count ?: 0) > 0 }) return null
    return CommentsAddReply(header[2], header[3], report)
}
fun commentsOwnedBy(report: CommentsReport, owners: Set<String>): List<CommentDocument> {
    val contexts = report.records("comments-owner").filter { it.size >= 3 && it[2] in owners }.map { it[0] }.toSet()
    return report.documents.filter { it.context in contexts }
}
fun parseComments(text: String): CommentsReport {
    val minimum = mapOf("comments-add-reply" to 1, "comments-capability" to 2, "comments-owner" to 2, "comments-context" to 5, "comments-guard" to 1, "comments-document" to 5, "comments-count" to 2, "comments-diagnostic" to 3, "comments-identity" to 2, "comments-candidate" to 2, "comments-delivery" to 3, "comments-capture" to 3, "comment-body" to 2, "comment-scope" to 3, "comment-entry" to 4, "comment-version" to 3, "comment-path" to 3, "comment-location" to 4, "comment-unversioned" to 1, "comment-diagnostic" to 3, "comment-diff" to 3, "comment-blob" to 3, "comments-delivery-file" to 4)
    return CommentsReport(text.lineSequence().map { it.trimEnd('\r').split('\t') }.filter { f -> (if (f[0] == "comment-columns") 4 else minimum[f[0]])?.let { f.size > it } == true }.map { CommentRow(it[0], it.drop(1)) }.toList())
}
fun commentsArgv(report: CommentsReport, operation: String, document: String? = null, context: String? = null, ordinal: Int? = null): List<String> {
    val args = mutableListOf(operation)
    if (document != null && operation != "prepare") args += listOf("--document", document)
    if (context != null) args += listOf("--context", context)
    if (operation == "entries") return args + "--porcelain"
    val guard = context?.let { id -> report.records("comments-context").firstOrNull { it[0] == id }?.get(3) } ?: report.guard
    require(!guard.isNullOrEmpty()) { UserCopy.STALE }
    args += listOf("--expect-context", guard)
    for (kind in if (operation == "save") listOf("local", "shared") else listOf(document ?: "shared")) {
        val row = report.documents.firstOrNull { it.kind == kind && (context == null || it.context == context) }
        require(row?.revision != "unreadable") { CommentsCopy.unreadable }
        args += listOf(if (operation == "save") "--expect-$kind" else "--expect-document", row?.revision ?: "absent")
    }
    if (ordinal != null) args += listOf("--entry", ordinal.toString())
    return args
}

/** Offset-independent, zero-based half-open selection converted to inclusive lines. */
fun commentSelectionLines(anchorLine: Int, anchorColumn: Int, caretLine: Int, caretColumn: Int): Pair<Int, Int> {
    val forward = anchorLine < caretLine || anchorLine == caretLine && anchorColumn <= caretColumn
    val first = if (forward) anchorLine else caretLine
    val last = if (forward) caretLine else anchorLine
    val endColumn = if (forward) caretColumn else anchorColumn
    return (first + 1) to maxOf(first + 1, last + if (last > first && endColumn == 0) 0 else 1)
}

/** UTF-16 endpoints, 1-based with exclusive end, independent of visual tab width. */
data class CommentCoordinates(val first: Int, val last: Int, val startColumn: Int, val endColumn: Int)
fun commentSelectionCoordinates(anchorLine: Int, anchorColumn: Int, caretLine: Int, caretColumn: Int): CommentCoordinates {
    val forward = anchorLine < caretLine || anchorLine == caretLine && anchorColumn <= caretColumn
    return if (forward) CommentCoordinates(anchorLine + 1, caretLine + 1, anchorColumn + 1, caretColumn + 1)
    else CommentCoordinates(caretLine + 1, anchorLine + 1, caretColumn + 1, anchorColumn + 1)
}
fun commentTextOffsets(text: String, first: Int, last: Int, startColumn: Int? = null, endColumn: Int? = null): Pair<Int, Int> {
    val lines = text.split('\n')
    require(first > 0 && last >= first && last <= lines.size) { CommentsCopy.rangeUnavailable }
    val precise = startColumn != null || endColumn != null
    val start = if (precise) (startColumn ?: 0) - 1 else 0
    val end = if (precise) (endColumn ?: 0) - 1 else lines[last - 1].trimEnd('\r').length
    require(start >= 0 && end >= 0 && start <= lines[first - 1].trimEnd('\r').length && end <= lines[last - 1].trimEnd('\r').length && (!precise || first != last || start < end)) { CommentsCopy.rangeUnavailable }
    return (lines.take(first - 1).sumOf { it.length + 1 } + start) to (lines.take(last - 1).sumOf { it.length + 1 } + end)
}

/** Immutable capture: changing scope never reads the editor again. */
data class CommentCapture(val path: String, val side: String, val first: Int, val last: Int, val unversioned: Boolean, val base: String? = null, val head: String? = null, val basePath: String? = null, val headPath: String? = null, val hasSelection: Boolean = false, val snippet: String = "", val startColumn: Int? = null, val endColumn: Int? = null) {
    val rangeLabel: String get() = if (startColumn != null && endColumn != null) "$first:$startColumn–$last:$endColumn" else "$first–$last"
    val scopes: List<CommentScope> get() = (if (hasSelection) listOf(CommentScope.SELECTION) else emptyList()) + listOf(CommentScope.FILE, CommentScope.GENERAL)
    fun label(scope: CommentScope): String = when (scope) {
        CommentScope.GENERAL -> CommentsCopy.general
        CommentScope.FILE -> "${CommentsCopy.file} · $path (${if (side == "base") CommentsCopy.baseSide else CommentsCopy.headSide})"
        CommentScope.SELECTION -> "${CommentsCopy.selection} · $path:$rangeLabel (${if (side == "base") CommentsCopy.baseSide else CommentsCopy.headSide})"
    }
    fun locationArgs(scope: CommentScope): List<String> {
        if (scope == CommentScope.GENERAL) return emptyList()
        require(scope != CommentScope.SELECTION || hasSelection)
        return listOf("--path", path, "--side", side) +
            (if (scope == CommentScope.SELECTION) listOf("--start-line", first.toString(), "--end-line", last.toString()) else emptyList()) +
            (if (scope == CommentScope.SELECTION && startColumn != null && endColumn != null) listOf("--start-column", startColumn.toString(), "--end-column", endColumn.toString()) else emptyList()) +
            (if (unversioned) listOf("--unversioned") else emptyList()) +
            (if (base != null && head != null) listOf("--base", base, "--head", head) else emptyList()) +
            (basePath?.let { listOf("--base-path", it) } ?: emptyList()) +
            (headPath?.let { listOf("--head-path", it) } ?: emptyList())
    }
}
enum class CommentScope { SELECTION, FILE, GENERAL }

/** A unified selection must map completely and contiguously to one original side. */
fun commentOriginalLines(first: Int, last: Int, transfer: (Int) -> Int): Pair<Int, Int>? {
    if (first < 1 || last < first) return null
    val start = transfer(first - 1)
    if (start < 0) return null
    var previous = start
    for (line in (first + 1)..last) {
        val mapped = transfer(line - 1)
        if (mapped != previous + 1) return null
        previous = mapped
    }
    return (start + 1) to (previous + 1)
}
