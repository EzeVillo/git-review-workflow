package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.PanelModel
import com.ezevillo.gitreview.domain.Situation
import com.ezevillo.gitreview.domain.MIN_CLI_VERSION
import com.ezevillo.gitreview.domain.NPM_INSTALL_CMD
import com.ezevillo.gitreview.domain.NPM_UPDATE_CMD
import com.ezevillo.gitreview.host.GitReviewService
import com.intellij.openapi.project.Project
import com.intellij.ui.JBColor
import com.intellij.ui.components.JBLabel
import com.intellij.ui.components.JBScrollPane
import com.intellij.util.ui.JBUI
import java.awt.BorderLayout
import java.awt.FlowLayout
import java.awt.Font
import javax.swing.Box
import javax.swing.BoxLayout
import javax.swing.JButton
import javax.swing.JPanel
import javax.swing.JTextArea
import javax.swing.SwingUtilities

/**
 * Native Swing panel that paints [PanelModel]. Uses JBColor/UIManager only.
 */
class ReviewPanel(
    private val project: Project,
    private val service: GitReviewService,
) : JPanel(BorderLayout()) {
    private val body = JPanel()
    private val scroll = JBScrollPane(body)
    private var disposeListener: (() -> Unit)? = null

    init {
        body.layout = BoxLayout(body, BoxLayout.Y_AXIS)
        body.border = JBUI.Borders.empty(8)
        add(scroll, BorderLayout.CENTER)
        disposeListener = service.onModelChanged { model ->
            SwingUtilities.invokeLater { render(model) }
        }
        render(service.currentModel())
    }

    fun disposePanel() {
        disposeListener?.invoke()
        disposeListener = null
    }

    private fun render(model: PanelModel) {
        body.removeAll()
        body.add(header(model))
        body.add(Box.createVerticalStrut(8))
        when (model.situation) {
            Situation.CLI_MISSING -> renderCliMissing(model, install = true)
            Situation.CLI_OUTDATED -> renderCliMissing(model, install = false)
            Situation.ERROR -> renderError(model)
            Situation.OUT_OF_RANGE -> renderMessage("Out of range", model.stderr)
            Situation.NO_REVIEW -> renderNoReview(model)
            Situation.FINISH_PENDING -> renderFinishPending(model)
            Situation.FINISH_CONFLICT -> renderReview(model, conflict = true)
            Situation.REVIEW -> renderReview(model, conflict = false)
        }
        body.add(Box.createVerticalGlue())
        body.revalidate()
        body.repaint()
    }

    private fun header(model: PanelModel): JPanel {
        val row = JPanel(FlowLayout(FlowLayout.LEFT, 4, 0))
        row.add(JBLabel("git review").apply {
            font = font.deriveFont(Font.BOLD, 14f)
        })
        if (model.busy) {
            row.add(JBLabel("…busy"))
        }
        val refresh = JButton("Refresh")
        refresh.addActionListener { service.scheduleRefresh() }
        row.add(refresh)
        return row
    }

    private fun renderCliMissing(model: PanelModel, install: Boolean) {
        val title = if (install) {
            "The git-review CLI ($MIN_CLI_VERSION or newer) was not found."
        } else {
            "The installed git-review CLI is older than $MIN_CLI_VERSION."
        }
        body.add(wrapLabel(title))
        body.add(Box.createVerticalStrut(6))
        body.add(wrapLabel("Reload the window after installing, or wait — the panel checks again every few seconds."))
        body.add(Box.createVerticalStrut(6))
        val cmd = if (install) NPM_INSTALL_CMD else NPM_UPDATE_CMD
        body.add(codeBlock(cmd))
        if (!model.stderr.isNullOrBlank()) {
            body.add(Box.createVerticalStrut(6))
            body.add(wrapLabel(model.stderr, muted = true))
        }
    }

    private fun renderError(model: PanelModel) {
        body.add(wrapLabel("Cannot use git review here"))
        body.add(Box.createVerticalStrut(6))
        body.add(wrapLabel(model.stderr ?: "Unknown error"))
    }

    private fun renderNoReview(model: PanelModel) {
        if (model.noBaseConfigured) {
            body.add(wrapLabel("Set a base branch before starting a review."))
            body.add(wrapLabel("Use the \"Set the Base Branch\" action (Settings → git review)."))
            if (model.configuredRemote != null) {
                body.add(wrapLabel("Remote: ${model.configuredRemote}", muted = true))
            }
            return
        }
        body.add(wrapLabel("No active review"))
        if (model.configuredBase != null) {
            body.add(wrapLabel("Base: ${model.configuredBase}", muted = true))
        }
        if (model.configuredRemote != null) {
            body.add(wrapLabel("Remote: ${model.configuredRemote}", muted = true))
        }
        if (model.reviews.isNotEmpty()) {
            body.add(Box.createVerticalStrut(8))
            body.add(wrapLabel("Saved / leftover reviews:"))
            for (r in model.reviews) {
                val marks = buildString {
                    if (r.saved) append(" saved")
                    if (r.current) append(" current")
                    if (r.orphan) append(" orphan")
                    if (r.resumable) append(" resumable")
                }
                body.add(wrapLabel("• ${r.name}$marks"))
            }
        }
        body.add(Box.createVerticalStrut(8))
        body.add(wrapLabel("Start a review from the git review actions."))
    }

    private fun renderFinishPending(model: PanelModel) {
        body.add(wrapLabel("Finish pending"))
        val pf = model.pendingFinish
        if (pf != null) {
            body.add(wrapLabel("Branch: ${pf.branch}" + if (pf.onto) " (onto source)" else ""))
        }
        body.add(wrapLabel("Use Undo Finish or Clean to resolve.", muted = true))
    }

    private fun renderReview(model: PanelModel, conflict: Boolean) {
        if (conflict) {
            body.add(wrapLabel("Finish conflict — navigation locked", muted = false))
        }
        body.add(wrapLabel("${model.mode?.id ?: "?"} · ${model.branch ?: ""}"))
        body.add(wrapLabel("source ${model.source ?: "?"}  tip ${model.tip?.take(12) ?: "?"}", muted = true))
        if (model.base != null) body.add(wrapLabel("base ${model.base}", muted = true))
        if (model.position != null && model.total != null) {
            body.add(wrapLabel("position ${model.position} / ${model.total}"))
        }
        if (model.baseMoved) body.add(wrapLabel("Base moved (total < recorded)", muted = true))
        if (model.degraded) body.add(wrapLabel("Walkthrough degraded", muted = true))
        if (model.readonly) body.add(wrapLabel("Read-only compare", muted = true))
        if (model.keysOnly) body.add(wrapLabel("Keys only", muted = true))

        val current = model.current
        if (current != null) {
            body.add(Box.createVerticalStrut(8))
            body.add(wrapLabel("Current: ${current.display}"))
            if (current.subject != null) body.add(wrapLabel(current.subject, muted = true))
            if (current.essential) body.add(wrapLabel("(key)", muted = true))
        }

        if (model.files.isNotEmpty()) {
            body.add(Box.createVerticalStrut(8))
            body.add(wrapLabel("Files (${model.files.size}):"))
            for (f in model.files.take(50)) {
                val mark = if (f.display == model.lastOpened) " ← last" else ""
                body.add(wrapLabel("• ${f.display}$mark"))
            }
            if (model.files.size > 50) {
                body.add(wrapLabel("… and ${model.files.size - 50} more", muted = true))
            }
        }

        val why = model.why
        if (why != null) {
            body.add(Box.createVerticalStrut(8))
            when (why.state) {
                com.ezevillo.gitreview.domain.WhyState.LOADING -> body.add(wrapLabel("Why: loading…"))
                com.ezevillo.gitreview.domain.WhyState.ABSENT -> body.add(wrapLabel("Why: (none)"))
                com.ezevillo.gitreview.domain.WhyState.FAILED -> body.add(wrapLabel("Why: failed to load"))
                com.ezevillo.gitreview.domain.WhyState.PRESENT -> {
                    body.add(wrapLabel("Why:"))
                    body.add(codeBlock(why.text.orEmpty()))
                }
            }
        }

        if (model.navigationLocked) {
            body.add(Box.createVerticalStrut(6))
            body.add(wrapLabel("Resume or undo finish before navigating.", muted = true))
        }
    }

    private fun renderMessage(title: String, detail: String?) {
        body.add(wrapLabel(title))
        if (!detail.isNullOrBlank()) body.add(wrapLabel(detail, muted = true))
    }

    private fun wrapLabel(text: String, muted: Boolean = false): JBLabel {
        val label = JBLabel("<html><body style='width:220px'>${escape(text)}</body></html>")
        if (muted) {
            label.foreground = JBColor.GRAY
        }
        label.alignmentX = LEFT_ALIGNMENT
        label.border = JBUI.Borders.empty(2, 0)
        return label
    }

    private fun codeBlock(text: String): JTextArea {
        val area = JTextArea(text)
        area.isEditable = false
        area.lineWrap = true
        area.wrapStyleWord = true
        area.background = JBColor.background()
        area.foreground = JBColor.foreground()
        area.border = JBUI.Borders.customLine(JBColor.border(), 1)
        area.alignmentX = LEFT_ALIGNMENT
        area.font = Font(Font.MONOSPACED, Font.PLAIN, 12)
        return area
    }

    private fun escape(s: String): String =
        s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
}
