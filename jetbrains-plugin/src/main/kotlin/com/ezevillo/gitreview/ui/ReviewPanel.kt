package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.PanelModel
import com.ezevillo.gitreview.domain.SKELETON_DELAY_MS
import com.ezevillo.gitreview.domain.WHY_CEILING_MS
import com.ezevillo.gitreview.domain.WhyState
import com.ezevillo.gitreview.domain.isReviewReadable
import com.ezevillo.gitreview.domain.panelLayout
import com.ezevillo.gitreview.host.GitReviewService
import com.intellij.openapi.project.Project
import com.intellij.util.ui.JBUI
import java.awt.BorderLayout
import javax.swing.JLabel
import javax.swing.JPanel
import javax.swing.SwingUtilities
import javax.swing.Timer

/**
 * Tool-window body: subscribes to [GitReviewService], projects [panelLayout],
 * and delegates drawing/dispatch. No situation `when` of its own.
 */
class ReviewPanel(
    private val project: Project,
    private val service: GitReviewService,
) : JPanel(BorderLayout()) {
    private val captureTracker = project.getService(com.ezevillo.gitreview.host.CommentEditorTracker::class.java)
    private val commentHint = JLabel()
    private val hintTimer = Timer(180) { updateCommentHint() }.apply { start() }
    private fun updateCommentHint() {
        if (!isShowing) return
        commentHint.isVisible = service.hasResolvedState() && isReviewReadable(service.currentModel().situation)
        val capture = com.ezevillo.gitreview.host.CommentsActions(project, service).capture(captureTracker.editor())
        commentHint.text = if (service.currentModel().situation == com.ezevillo.gitreview.domain.Situation.FINISH_CONFLICT) com.ezevillo.gitreview.domain.CommentsCopy.general else capture?.label(capture.scopes.first()) ?: if (captureTracker.editor() != null) com.ezevillo.gitreview.domain.CommentsCopy.opaque else com.ezevillo.gitreview.domain.CommentsCopy.general
        commentHint.toolTipText = com.ezevillo.gitreview.domain.CommentsCopy.selectionHint
    }
    private val chrome = PluginPanelChrome()
    private val dispatcher = PanelActionDispatcher(project, service)
    private val renderer = PanelRenderer(chrome) { id, index, supportLinkId ->
        if (stale) return@PanelRenderer false
        dispatcher.dispatch(id, index, supportLinkId)
    }.apply { commentTargetHint = commentHint }

    private var disposeListener: (() -> Unit)? = null
    private var skeletonTimer: Timer? = null
    private var whyCeilingTimer: Timer? = null
    private var pendingModel: PanelModel? = null
    private var showingSkeleton = false
    /** Drawn model is stale during load — clicks no-op (extension `stale()`). */
    private var stale = false
    private var generation = 0

    init {
        border = JBUI.Borders.empty()
        disposeListener = service.onModelChanged { model ->
            SwingUtilities.invokeLater { onModel(model) }
        }
        // Nothing has been read yet: the seed state is an ERROR placeholder and
        // drawing it would claim the review state is broken before anyone looked
        // (the extension shows an empty webview until the first model arrives).
        if (service.hasResolvedState()) {
            onModel(service.currentModel())
        } else {
            paintWaiting()
        }
    }

    fun disposePanel() {
        disposeListener?.invoke()
        disposeListener = null
        skeletonTimer?.stop()
        whyCeilingTimer?.stop()
        hintTimer.stop()
    }

    private fun onModel(model: PanelModel) {
        generation += 1
        val gen = generation
        skeletonTimer?.stop()
        whyCeilingTimer?.stop()
        pendingModel = model

        val needsSkeleton = modelLooksLoading(model)
        if (!needsSkeleton) {
            stale = false
            showingSkeleton = false
            paintLayout(model, loading = false)
            return
        }

        // Keep previous surface briefly; after delay show skeleton with disabled controls.
        stale = true
        skeletonTimer = Timer(SKELETON_DELAY_MS.toInt()) {
            if (gen != generation) return@Timer
            showingSkeleton = true
            paintLayout(model, loading = true)
        }.also {
            it.isRepeats = false
            it.start()
        }

        // Why ceiling: if still loading why after threshold, show entry with why-loading block.
        if (model.why?.state == WhyState.LOADING) {
            whyCeilingTimer = Timer(WHY_CEILING_MS.toInt()) {
                if (gen != generation) return@Timer
                // Re-read; if still loading, paint non-skeleton with why loading
                val current = service.currentModel()
                if (current.why?.state == WhyState.LOADING) {
                    stale = false
                    showingSkeleton = false
                    paintLayout(current, loading = false)
                }
            }.also {
                it.isRepeats = false
                it.start()
            }
        }
    }

    private fun modelLooksLoading(model: PanelModel): Boolean {
        if (!isReviewReadable(model.situation)) return false
        if (model.busy) return true
        if (model.why?.state == WhyState.LOADING) return true
        return false
    }

    /** Pre-first-refresh surface: no situation, no controls — just "hold on". */
    private fun paintWaiting() {
        val label = JLabel(WAITING_TEXT)
        label.foreground = chrome.mutedForeground()
        label.border = JBUI.Borders.empty(8)
        removeAll()
        add(label, BorderLayout.NORTH)
        revalidate()
        repaint()
    }

    private fun paintLayout(model: PanelModel, loading: Boolean) {
        val layout = panelLayout(model, loading = loading)
        removeAll()
        add(renderer.render(layout), BorderLayout.CENTER)
        updateCommentHint()
        revalidate()
        repaint()
    }

    private companion object {
        const val WAITING_TEXT = "Reading the review state…"
    }
}
