package com.ezevillo.gitreview.diff

import com.ezevillo.gitreview.domain.commentSelectionLines
import com.ezevillo.gitreview.domain.commentOriginalLines
import com.ezevillo.gitreview.domain.commentSelectionCoordinates
import com.ezevillo.gitreview.host.COMMENT_CAPTURE_KEY
import com.ezevillo.gitreview.host.COMMENT_CAPTURE_RESOLVER
import com.intellij.diff.*
import com.intellij.diff.requests.DiffRequest
import com.intellij.diff.tools.fragmented.UnifiedDiffViewer
import com.intellij.diff.tools.util.side.TwosideTextDiffViewer
import com.intellij.diff.tools.util.base.DiffViewerBase
import com.intellij.diff.tools.util.base.DiffViewerListener
import com.intellij.openapi.editor.markup.*
import com.intellij.openapi.editor.colors.EditorColors

data class CommentHighlight(val side: com.intellij.diff.util.Side, val first: Int, val last: Int, val body: String, val startColumn: Int? = null, val endColumn: Int? = null)
val COMMENT_HIGHLIGHT = com.intellij.openapi.util.Key.create<CommentHighlight>("git.review.comment.highlight")

class CommentDiffExtension : DiffExtension() {
    override fun onViewerCreated(viewer: FrameDiffTool.DiffViewer, context: DiffContext, request: DiffRequest) {
        val mark = request.getUserData(COMMENT_HIGHLIGHT)
        if (mark != null && viewer is DiffViewerBase) {
            val highlights = mutableListOf<RangeHighlighter>()
            viewer.addListener(object : DiffViewerListener() {
                override fun onBeforeRediff() { highlights.forEach { it.dispose() }; highlights.clear() }
                override fun onAfterRediff() {
                    highlights.forEach { it.dispose() }; highlights.clear()
                    val editor = when (viewer) {
                        is UnifiedDiffViewer -> viewer.editor
                        is TwosideTextDiffViewer -> viewer.getEditor(mark.side)
                        else -> return
                    }
                    for (original in mark.first..mark.last) {
                        val line = if (viewer is UnifiedDiffViewer) viewer.transferLineToOnesideStrict(mark.side, original - 1) else original - 1
                        if (line < 0 || line >= editor.document.lineCount) continue
                        val start = editor.document.getLineStartOffset(line) + if (original == mark.first) (mark.startColumn ?: 1) - 1 else 0
                        val end = if (original == mark.last && mark.endColumn != null) editor.document.getLineStartOffset(line) + mark.endColumn - 1 else editor.document.getLineEndOffset(line) + if (mark.startColumn != null) editor.document.getLineSeparatorLength(line) else 0
                        if (start > end || end > editor.document.getLineEndOffset(line) + editor.document.getLineSeparatorLength(line)) continue
                        val area = if (mark.startColumn == null) HighlighterTargetArea.LINES_IN_RANGE else HighlighterTargetArea.EXACT_RANGE
                        if (start == end && mark.startColumn != null) continue
                        highlights += editor.markupModel.addRangeHighlighter(EditorColors.SEARCH_RESULT_ATTRIBUTES, start, end, HighlighterLayer.SELECTION - 1, area).apply { errorStripeTooltip = mark.body }
                    }
                }
                override fun onDispose() { highlights.forEach { it.dispose() }; highlights.clear() }
            })
        }
        if (viewer !is UnifiedDiffViewer) return
        viewer.editor.putUserData(COMMENT_CAPTURE_RESOLVER) { editor ->
            val selection = editor.selectionModel
            val a = selection.selectionStart; val b = selection.selectionEnd
            val doc = editor.document
            val first = doc.getLineNumber(a); val last = doc.getLineNumber(b)
            val range = commentSelectionLines(first, a - doc.getLineStartOffset(first), last, b - doc.getLineStartOffset(last))
            val coordinates = commentSelectionCoordinates(first, a - doc.getLineStartOffset(first), last, b - doc.getLineStartOffset(last))
            val side = viewer.transferLineFromOnesideStrict(range.first - 1)?.second ?: return@putUserData null
            val capture = viewer.getContent(side).document.getUserData(COMMENT_CAPTURE_KEY) ?: return@putUserData null
            val mapped = commentOriginalLines(range.first, range.second) { viewer.transferLineFromOnesideStrict(side, it) } ?: return@putUserData null
            capture.copy(first = mapped.first, last = mapped.second + if (last > first && coordinates.endColumn == 1) 1 else 0,
                startColumn = coordinates.startColumn, endColumn = coordinates.endColumn,
                unversioned = capture.unversioned || com.intellij.openapi.fileEditor.FileDocumentManager.getInstance().isDocumentUnsaved(viewer.getContent(side).document),
                hasSelection = selection.hasSelection(), snippet = selection.selectedText.orEmpty().take(2000))
        }
    }
}
