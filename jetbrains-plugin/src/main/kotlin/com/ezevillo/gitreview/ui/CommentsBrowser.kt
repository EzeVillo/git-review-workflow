package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.CommentPresentation
import com.ezevillo.gitreview.domain.CommentsCopy
import com.ezevillo.gitreview.domain.ControlId
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.DialogWrapper
import com.intellij.ui.OnePixelSplitter
import com.intellij.ui.components.JBList
import com.intellij.ui.components.JBScrollPane
import com.intellij.util.ui.JBUI
import com.intellij.util.ui.UIUtil
import java.awt.BorderLayout
import java.awt.Dimension
import java.awt.event.ActionEvent
import javax.swing.*

/** Modeless list/detail browser, closed after a successful diff opening. */
class CommentsBrowser(project: Project, entries: List<CommentPresentation>, private val open: (CommentPresentation, (String?) -> Unit) -> Unit, private val remove: ((CommentPresentation, (List<CommentPresentation>?, String?) -> Unit) -> Unit)? = null) : DialogWrapper(project, false) {
    private val model = DefaultListModel<CommentPresentation>().apply { entries.forEach { addElement(it) } }
    private val list = JBList<CommentPresentation>(model)
    private var busy = false
    private fun prose() = JTextArea().apply {
        isEditable = false; isOpaque = false; lineWrap = true; wrapStyleWord = true
        font = UIUtil.getLabelFont(); border = JBUI.Borders.empty(8)
    }
    private val body = prose().apply { accessibleContext.accessibleName = CommentsCopy.body }
    private val version = prose()
    private val warning = prose()
    private val error = prose()
    private val details = JToggleButton(CommentsCopy.details).apply {
        isContentAreaFilled = false
        addActionListener { version.isVisible = isSelected; version.parent.revalidate(); version.parent.repaint() }
    }
    private val openAction = object : AbstractAction(CommentsCopy.openDiff) {
        override fun actionPerformed(event: ActionEvent?) {
            val entry = list.selectedValue ?: return
            if (busy || !entry.canOpenDiff) return
            setBusy(true); error.text = ""
            open(entry) { message ->
                if (message == null) close(OK_EXIT_CODE)
                else { setBusy(false); error.text = message; error.isVisible = true }
            }
        }
    }
    private val deleteAction = object : AbstractAction(CommentsCopy.delete) {
        override fun actionPerformed(event: ActionEvent?) {
            val entry = list.selectedValue ?: return
            val delete = remove ?: return
            if (busy) return
            setBusy(true)
            if (!UiMessages.confirm(project, ControlId.DELETE_COMMENT_ENTRY, CommentsCopy.deleteEntryTitle, CommentsCopy.deleteEntryDetail, CommentsCopy.delete)) { setBusy(false); return }
            val index = list.selectedIndex
            error.text = ""; error.isVisible = false
            delete(entry) { next, message ->
                if (next != null) {
                    model.clear(); next.forEach { model.addElement(it) }
                    if (next.isNotEmpty()) list.selectedIndex = minOf(index, next.lastIndex)
                }
                error.text = message.orEmpty(); error.isVisible = message != null
                setBusy(false); updateDetail()
            }
        }
    }
    private fun setBusy(value: Boolean) {
        busy = value; list.isEnabled = !value; cancelAction.isEnabled = !value
        openAction.isEnabled = !value && list.selectedValue?.canOpenDiff == true
        deleteAction.isEnabled = !value && list.selectedValue != null
    }
    init {
        title = CommentsCopy.title; isModal = false
        list.selectionMode = ListSelectionModel.SINGLE_SELECTION
        list.fixedCellWidth = 1 // Let labels elide to the viewport instead of adding horizontal scrolling.
        list.accessibleContext.accessibleName = CommentsCopy.entries
        list.cellRenderer = object : DefaultListCellRenderer() {
            override fun getListCellRendererComponent(list: JList<*>?, value: Any?, index: Int, selected: Boolean, focused: Boolean): java.awt.Component {
                val entry = value as CommentPresentation
                val heading = super.getListCellRendererComponent(list, entry.label, index, selected, focused) as JLabel
                heading.putClientProperty("html.disable", true)
                val preview = JLabel(entry.preview).apply {
                    putClientProperty("html.disable", true)
                    foreground = if (selected) heading.foreground else UIUtil.getContextHelpForeground()
                }
                return JPanel(BorderLayout(0, 4)).apply {
                    background = heading.background; border = JBUI.Borders.empty(8, 10)
                    add(heading, BorderLayout.NORTH); add(preview, BorderLayout.CENTER)
                    toolTipText = entry.label
                    accessibleContext.accessibleName = entry.label + " · " + entry.preview
                }
            }
        }
        list.addListSelectionListener { if (!it.valueIsAdjusting) updateDetail() }
        init(); if (entries.isNotEmpty()) list.selectedIndex = 0 else openAction.isEnabled = false
    }
    private fun updateDetail() {
        val entry = list.selectedValue
        setBusy(busy)
        getButton(openAction)?.isVisible = entry?.canOpenDiff == true
        if (entry == null) {
            body.text = CommentsCopy.empty; version.isVisible = false; details.isVisible = false; warning.isVisible = false
            return
        }
        version.text = entry.version; body.text = entry.body; body.caretPosition = 0
        warning.text = entry.warning; warning.isVisible = entry.warning.isNotBlank()
        details.isVisible = entry.version.isNotBlank(); details.isSelected = false; version.isVisible = false
    }
    override fun createCenterPanel(): JComponent = JPanel(BorderLayout(0, 8)).apply {
        preferredSize = JBUI.size(760, 560)
        val detail = JPanel(BorderLayout(0, 8))
        detail.add(JPanel().apply {
            layout = BoxLayout(this, BoxLayout.Y_AXIS)
            add(warning); add(JPanel(java.awt.FlowLayout(java.awt.FlowLayout.LEFT, 0, 0)).apply { add(details) }); add(version)
        }, BorderLayout.NORTH)
        fun scroll(component: JComponent) = JBScrollPane(component).apply {
            border = JBUI.Borders.empty(); viewportBorder = JBUI.Borders.empty()
            horizontalScrollBarPolicy = ScrollPaneConstants.HORIZONTAL_SCROLLBAR_NEVER
        }
        detail.add(scroll(body), BorderLayout.CENTER)
        add(OnePixelSplitter(true, 0.30f).apply {
            firstComponent = scroll(list).apply { minimumSize = Dimension(0, 70) }
            secondComponent = detail.apply { minimumSize = Dimension(0, 140) }
            border = JBUI.Borders.empty()
        }, BorderLayout.CENTER)
        error.isVisible = false
        add(error, BorderLayout.SOUTH)
    }
    override fun createActions(): Array<Action> = if (remove != null) arrayOf(openAction, deleteAction) else arrayOf(openAction)
}
