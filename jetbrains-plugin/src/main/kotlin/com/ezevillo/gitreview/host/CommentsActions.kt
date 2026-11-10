package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.*
import com.ezevillo.gitreview.ui.CommentsComposer
import com.ezevillo.gitreview.ui.UiMessages
import com.ezevillo.gitreview.vcs.pickSoleGitRoot
import com.intellij.openapi.project.Project
import com.intellij.openapi.fileEditor.FileEditorManager
import com.intellij.openapi.fileEditor.FileDocumentManager
import com.intellij.openapi.application.ApplicationManager
import com.ezevillo.gitreview.diff.openEditorDiffs
import com.intellij.diff.DiffContentFactory
import com.intellij.diff.requests.SimpleDiffRequest
import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.execution.process.CapturingProcessHandler
import java.nio.charset.StandardCharsets
import java.io.File

typealias CommentCapture = com.ezevillo.gitreview.domain.CommentCapture
val COMMENT_CAPTURE_RESOLVER = com.intellij.openapi.util.Key.create<(com.intellij.openapi.editor.Editor) -> CommentCapture?>("git.review.comment.resolver")
val COMMENT_CAPTURE_KEY = com.intellij.openapi.util.Key.create<CommentCapture>("git.review.comment.capture")

fun saveSessionCommentDocuments(service: GitReviewService, root: String, action: String, params: ActionParams): Boolean =
    saveSessionComments(service.cliInvoker, root, service.currentState(), action, params,
        ::hasUnsavedEditorDocuments) { saveCommentFiles(it) != CommentBufferSave.FAILED }

class CommentsActions(private val project: Project, private val service: GitReviewService) {
    private fun commentsFailure(work: () -> String?): String? {
        val result = try { work() } catch (error: Exception) { error.message ?: CommentsCopy.failed }
        if (!result.isNullOrEmpty()) runCatching { service.refreshNow() }
        return result
    }
    private fun cwd() = pickSoleGitRoot(project)?.rootPath
    private fun read(root: String, context: String? = null): CommentsReport {
        val result = service.cliInvoker.invoke("comments", listOf("status", "--porcelain") + if (context != null) listOf("--context", context) else emptyList(), root)
        val report = parseComments(result.stdout)
        return if (result.exitCode == 0) report else report.copy(rows = report.rows + CommentRow("comments-diagnostic", listOf("", "read", result.stderr)))
    }
    private fun error(result: InvokeResult) = if (result.exitCode == 0 && !result.timedOut) null else if (result.exitCode == 4) UserCopy.STALE else result.stderr.ifBlank { CommentsCopy.failed }
    fun add(captured: CommentCapture? = capture()) {
        val location = captured.takeUnless { service.currentState().situation == Situation.FINISH_CONFLICT }
        val root = cwd() ?: return
        if (!isReviewReadable(service.currentState().situation)) return
        Bg.async(project, CommentsCopy.add, work = { service.commentsForComposer(root) ?: read(root) }, then = { initial ->
            val destinations = initial.destinations()
            val guard = initial.guard ?: return@async
            if (destinations.isEmpty()) return@async
            var choice: String? = null
            if (initial.records("comments-identity").any { it[0] == "ambiguous" }) {
                val candidates = initial.records("comments-candidate")
                val options = listOf(CommentsCopy.newContext + " — " + CommentsCopy.newContextDetail) + candidates.map {
                    CommentsCopy.continueContext + ": " + it[1] + " — " + CommentsCopy.continueContextDetail + " " + it.getOrNull(2).orEmpty()
                }
                val hint = if ("shared" in destinations) CommentsCopy.contextHint else CommentsCopy.localContextHint
                val picked = UiMessages.choose(project, hint, CommentsCopy.chooseContext, options.toTypedArray())
                if (picked < 0) return@async
                choice = if (picked == 0) "" else candidates[picked - 1][0]
            }
            CommentsComposer(project, location, destinations, if (location == null && service.currentState().situation != Situation.FINISH_CONFLICT && project.getService(CommentEditorTracker::class.java).editor() != null) CommentsCopy.opaque else null) { kind, text, scope, done ->
                Bg.async(project, CommentsCopy.add, work = { commentsFailure {
                    service.mutationLock.run {
                        val useLatestDocument = initial.supportsAddReply && hasUnsavedEditorDocuments() == false
                        val fresh = if (useLatestDocument) initial else {
                            val current = read(root)
                            if (current.guard != guard) return@run UserCopy.STALE
                            when (saveCommentFiles(current.documents.filter { it.kind == kind }.map { it.path })) {
                                CommentBufferSave.UNCHANGED -> current
                                CommentBufferSave.SAVED -> read(root)
                                CommentBufferSave.FAILED -> return@run CommentsCopy.saveFailed
                            }
                        }
                        if (fresh.guard != guard) return@run UserCopy.STALE
                        val born = fresh.documents.none { it.presence == "present" }
                        // A clean editor has no bytes to flush. The CLI binds the
                        // form's context and appends to the current disk revision.
                        val args = if (useLatestDocument) mutableListOf("add", "--document", kind, "--expect-context", guard)
                        else commentsArgv(fresh, "add", kind).toMutableList()
                        args += "--stdin"
                        choice?.let { args += if (it.isEmpty()) listOf("--new-context") else listOf("--use-context", it) }
                        if (location != null) args += location.locationArgs(scope)
                        val snapshot = service.captureCommentsAdd()
                        val wantsReply = snapshot.state.guard != null && fresh.supportsAddReply
                        if (wantsReply) args += "--porcelain"
                        val result = service.cliInvoker.invokeWithInput("comments", args, root, text)
                        val reply = if (wantsReply && result.exitCode == 0 && !result.timedOut) parseCommentsAddReply(result.stdout, kind) else null
                        if (reply == null || !service.applyCommentsAdd(root, snapshot, reply)) service.refreshNow()
                        val message = error(result)
                        if (message == null && born) revealPanel(project, ControlId.ADD_COMMENT, commentsBlockBorn = true)
                        message ?: ""
                    } ?: CommentsCopy.failed
                } }, then = { done(it?.takeIf { message -> message.isNotEmpty() }) })
            }.show()
        })
    }
    fun row(action: ControlId, index: Int?) {
        val doc = service.currentState().comments?.documents?.getOrNull(index ?: -1) ?: return
        val root = cwd() ?: return
        if (action == ControlId.OPEN_COMMENTS) { openInEditor(project, doc.path); return }
        if (action == ControlId.DELETE_COMMENTS && !com.ezevillo.gitreview.ui.confirmCommentsDeletion(project)) return
        Bg.async(project, CommentsCopy.title, work = { commentsFailure {
            service.mutationLock.run {
                val initial = read(root, doc.context)
                if (saveCommentFiles(listOf(doc.path)) == CommentBufferSave.FAILED) return@run CommentsCopy.saveFailed
                val fresh = read(root, doc.context)
                if (fresh.guard != initial.guard || fresh.records("comments-context") != initial.records("comments-context")) return@run UserCopy.STALE
                if (action == ControlId.OPEN_COMMENT_DIFF) { openDiff(root, doc, fresh); return@run null }
                if (action == ControlId.PREPARE_SHARED_COMMENTS) return@run prepare(root, doc, fresh)
                val operation = if (action == ControlId.DELETE_COMMENTS) "delete" else if (action == ControlId.INIT_COMMENTS) "init" else if (action == ControlId.RENUMBER_COMMENTS) "renumber" else "prepare"
                val args = commentsArgv(fresh, operation, doc.kind, doc.context).toMutableList()
                if (operation == "delete") args[args.indexOf("--expect-document") + 1] = doc.revision
                val result = service.cliInvoker.invoke("comments", args, root)
                service.refreshNow(); error(result)
            }
        } }, then = { it?.let { message -> UiMessages.error(project, message) } })
    }
    fun capture(editor: com.intellij.openapi.editor.Editor? = project.getService(CommentEditorTracker::class.java).editor()): CommentCapture? {
        editor ?: return null
        if (editor.isDisposed) return null
        val startOffset = editor.selectionModel.selectionStart
        val endOffset = editor.selectionModel.selectionEnd
        val startLine = editor.document.getLineNumber(startOffset)
        val endLine = editor.document.getLineNumber(endOffset)
        val coordinates = commentSelectionCoordinates(startLine, startOffset - editor.document.getLineStartOffset(startLine), endLine, endOffset - editor.document.getLineStartOffset(endLine))
        val hasSelection = editor.selectionModel.hasSelection()
        val snippet = editor.selectionModel.selectedText.orEmpty().take(2000)
        editor.getUserData(COMMENT_CAPTURE_RESOLVER)?.let { return it(editor) }
        val original = editor.document.getUserData(COMMENT_CAPTURE_KEY)
        if (original != null) return original.copy(first = coordinates.first, last = coordinates.last, startColumn = coordinates.startColumn, endColumn = coordinates.endColumn, unversioned = original.unversioned || FileDocumentManager.getInstance().isDocumentUnsaved(editor.document), hasSelection = hasSelection, snippet = snippet)
        val file = FileDocumentManager.getInstance().getFile(editor.document) ?: return null
        val root = cwd() ?: return null
        val repoPath = File(root).toPath().toAbsolutePath().normalize()
        val filePath = File(file.path).toPath().toAbsolutePath().normalize()
        if (!filePath.startsWith(repoPath)) return null
        val path = repoPath.relativize(filePath).toString().replace('\\', '/')
        if (path.startsWith("../")) return null
        return CommentCapture(path, "head", coordinates.first, coordinates.last, FileDocumentManager.getInstance().isDocumentUnsaved(editor.document), hasSelection = hasSelection, snippet = snippet, startColumn = coordinates.startColumn, endColumn = coordinates.endColumn)
    }
    private fun prepare(root: String, doc: CommentDocument, report: CommentsReport): String? {
        var picked = -1
        ApplicationManager.getApplication().invokeAndWait { picked = UiMessages.choose(project, CommentsCopy.deliveryTitle, UserCopy.PRODUCT_TITLE, arrayOf(CommentsCopy.compareDelivery, CommentsCopy.retryDelivery)) }
        if (picked < 0) return null
        val check = service.cliInvoker.invoke("comments", commentsArgv(report, "prepare", "shared", doc.context) + listOf("--check", "--porcelain"), root)
        error(check)?.let { return it }
        val files = parseComments(check.stdout).records("comments-delivery-file")
        if (picked == 0) {
            val sides = listOf("prepared", "destination").map { role ->
                val row = files.single { it[1] == role }
                if (row[2] == "absent") null else refreshAndFind(File(row[0])) ?: throw IllegalStateException(CommentsCopy.historyFailed)
            }
            ApplicationManager.getApplication().invokeLater {
                val factory = DiffContentFactory.getInstance()
                openEditorDiffs(project, listOf(SimpleDiffRequest(CommentsCopy.deliveryTitle, sides[0]?.let { factory.create(project, it) } ?: factory.createEmpty(), sides[1]?.let { factory.create(project, it) } ?: factory.createEmpty(), CommentsCopy.shared, CommentsCopy.deliveryTitle)))
            }
            return null
        }
        if (saveCommentFiles(files.filter { it[1] != "baseline" }.map { it[0] }) == CommentBufferSave.FAILED) return CommentsCopy.saveFailed
        val fresh = read(root, doc.context)
        if (fresh.guard != report.guard || fresh.records("comments-context") != report.records("comments-context")) return UserCopy.STALE
        val result = service.cliInvoker.invoke("comments", commentsArgv(fresh, "prepare", "shared", doc.context), root)
        service.refreshNow()
        return error(result)
    }
    private fun openDiff(root: String, doc: CommentDocument, fresh: CommentsReport) {
        val entries = service.cliInvoker.invoke("comments", commentsArgv(fresh, "entries", doc.kind, doc.context), root)
        error(entries)?.let { throw IllegalStateException(it) }
        var report = parseComments(entries.stdout)
        val rows = report.records("comment-entry")
        if (rows.isEmpty()) { ApplicationManager.getApplication().invokeLater { UiMessages.info(project, CommentsCopy.empty) }; return }
        fun snapshot() = fresh.copy(rows = fresh.rows.filter { it.tag != "comments-document" } + report.rows.filter { it.tag == "comments-document" })
        val canDelete = fresh.records("comments-context").any { it[0] == doc.context && (it[2] in setOf("active", "result") || it[2] == "repository" && doc.kind == "local") }
        ApplicationManager.getApplication().invokeLater {
            com.ezevillo.gitreview.ui.CommentsBrowser(project, rows.map { presentComment(report, it) }, open = { comment, done ->
                Bg.async(project, CommentsCopy.diff, work = { commentsFailure { if (comment.canOpenDiff) openSelectedDiff(root, doc, snapshot(), comment); null } }, then = done)
            }, remove = if (!canDelete) null else { comment, done ->
                Bg.async(project, CommentsCopy.delete, work = {
                    var next: List<CommentPresentation>? = null
                    val failure = commentsFailure {
                        var entered = false
                        val message = service.mutationLock.run {
                            entered = true
                            try {
                                if (saveCommentFiles(listOf(doc.path)) == CommentBufferSave.FAILED) return@run CommentsCopy.saveFailed
                                val result = service.cliInvoker.invoke("comments", commentsArgv(snapshot(), "delete", doc.kind, doc.context, comment.ordinal), root)
                                error(result)?.let { return@run it }
                                val updated = service.cliInvoker.invoke("comments", commentsArgv(fresh, "entries", doc.kind, doc.context), root)
                                error(updated)?.let { return@run it }
                                report = parseComments(updated.stdout)
                                next = report.records("comment-entry").map { presentComment(report, it) }
                                null
                            } finally { service.refreshNow() }
                        }
                        if (!entered) CommentsCopy.failed else message
                    }
                    next to failure
                }, then = { (next, error) -> done(next, error) })
            }).show()
        }
    }

    private fun openSelectedDiff(root: String, doc: CommentDocument, snapshot: CommentsReport, comment: CommentPresentation) {
        val guarded = commentsArgv(snapshot, "diff", doc.kind, doc.context, comment.ordinal)
        val result = service.cliInvoker.invoke("comments", guarded + "--porcelain", root)
        error(result)?.let { throw IllegalStateException(it) }
        val recipe = parseComments(result.stdout)
        val blobs = recipe.records("comment-blob")
        if (blobs.isEmpty()) {
            val rendered = service.cliInvoker.invoke("comments", guarded, root)
            error(rendered)?.let { throw IllegalStateException(it) }
            ApplicationManager.getApplication().invokeAndWait { openCommentText(project, comment.location + "\n" + comment.version + "\n" + comment.warning + "\n\n" + comment.body + "\n\n" + rendered.stdout) }
            return
        }
        fun content(side: String): String {
            val blob = blobs.firstOrNull { it[1] == side } ?: error(CommentsCopy.historyFailed)
            if (blob[2] == "absent") return ""
            require(blob.size >= 4 && blob[3].matches(Regex("[0-9a-f]{40}|[0-9a-f]{64}")))
            val output = CapturingProcessHandler(GeneralCommandLine("git", "cat-file", "blob", blob[3]).withWorkDirectory(root).withCharset(StandardCharsets.UTF_8).withEnvironment("GIT_NO_LAZY_FETCH", "1")).runProcess(30000)
            check(output.exitCode == 0 && !output.isTimeout) { output.stderr.ifBlank { CommentsCopy.historyFailed } }
            return output.stdout
        }
        val base = content("base"); val head = content("head")
        val mark = recipe.records("comment-location").firstOrNull()?.let { row ->
            val side = if (row[1] == "base") com.intellij.diff.util.Side.LEFT else com.intellij.diff.util.Side.RIGHT
            val first = row[2].toIntOrNull() ?: error(CommentsCopy.rangeUnavailable)
            val last = row[3].toIntOrNull() ?: error(CommentsCopy.rangeUnavailable)
            val text = if (side == com.intellij.diff.util.Side.LEFT) base else head
            val columns = recipe.records("comment-columns").firstOrNull { it[0] == row[0] && it[1] == row[1] }
            val startColumn = columns?.get(2)?.toIntOrNull()
            val endColumn = columns?.get(3)?.toIntOrNull()
            require(columns == null || startColumn != null && endColumn != null) { CommentsCopy.rangeUnavailable }
            commentTextOffsets(text, first, last, startColumn, endColumn)
            com.ezevillo.gitreview.diff.CommentHighlight(side, first, last, comment.body, startColumn, endColumn)
        }
        ApplicationManager.getApplication().invokeAndWait {
            val factory = DiffContentFactory.getInstance()
            fun historical(side: String, text: String): com.intellij.diff.contents.DiffContent {
                val content = factory.create(project, text)
                val blob = blobs.first { it[1] == side }
                val range = recipe.records("comment-diff").firstOrNull()
                fun decode(value: String) = Regex("%(25|09|0D|0A|3E)").replace(value) { match -> when (match.groupValues[1]) { "25" -> "%"; "09" -> "\t"; "0D" -> "\r"; "0A" -> "\n"; else -> ">" } }
                if (blob[2] == "present" && range != null) {
                    val before = blobs.firstOrNull { it[1] == "base" && it[2] == "present" }?.get(0)?.let(::decode)
                    val after = blobs.firstOrNull { it[1] == "head" && it[2] == "present" }?.get(0)?.let(::decode)
                    content.document.putUserData(COMMENT_CAPTURE_KEY, CommentCapture(decode(blob[0]), side, 1, 1, false, range[1], range[2], before, after))
                }
                return content
            }
            val request = SimpleDiffRequest(comment.location + " · " + comment.preview.take(60), historical("base", base), historical("head", head), CommentsCopy.baseSide, CommentsCopy.headSide)
            mark?.let {
                request.putUserData(com.ezevillo.gitreview.diff.COMMENT_HIGHLIGHT, it)
                request.putUserData(com.intellij.diff.util.DiffUserDataKeys.SCROLL_TO_LINE, com.intellij.openapi.util.Pair.create(it.side, it.first - 1))
            }
            openEditorDiffs(project, listOf(request))
        }
    }
}
