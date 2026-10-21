package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.*
import java.awt.BorderLayout
import java.awt.Dimension
import java.awt.GridBagLayout
import java.awt.GridBagConstraints
import java.awt.Insets
import javax.swing.*
import javax.swing.event.DocumentEvent
import javax.swing.event.DocumentListener

class CommentForm(private val captured: CommentCapture?, private val destinations: List<String>, warning: String? = null, private val changed: () -> Unit) : JPanel(BorderLayout(8, 8)) {
    val scopes = captured?.scopes ?: listOf(CommentScope.GENERAL)
    val scope = JComboBox(scopes.map { captured?.label(it) ?: CommentsCopy.general }.toTypedArray())
    val destination = JComboBox(destinations.map { if (it == "local") CommentsCopy.localDestination else CommentsCopy.sharedDestination }.toTypedArray()).apply {
        selectedIndex = if (destinations.size == 1) 0 else -1
        isVisible = destinations.size > 1
        renderer = object : DefaultListCellRenderer() {
            override fun getListCellRendererComponent(list: JList<*>?, value: Any?, index: Int, selected: Boolean, focused: Boolean): java.awt.Component =
                super.getListCellRendererComponent(list, value ?: CommentsCopy.destination, index, selected, focused)
        }
        accessibleContext.accessibleName = CommentsCopy.destination
    }
    val text = JTextArea(12, 60).apply { lineWrap = true; wrapStyleWord = true }
    val preview = JTextArea().apply { isEditable = false; lineWrap = true; wrapStyleWord = true }
    val previewPane = JScrollPane(preview).apply { preferredSize = Dimension(560, 88) }
    val textPane = JScrollPane(text).apply { preferredSize = Dimension(560, 240) }
    var busy = false; private set
    val canCancel get() = !busy
    val selectedScope get() = scopes[scope.selectedIndex]
    val canSave get() = !busy && destination.selectedIndex >= 0 && text.text.isNotBlank()
    init {
        val header = JPanel(GridBagLayout())
        var row = 0
        fun field(component: JComponent) {
            header.add(component, GridBagConstraints().apply {
                gridx = 0; gridy = row++; weightx = 1.0; fill = GridBagConstraints.HORIZONTAL
                anchor = GridBagConstraints.WEST; insets = Insets(0, 0, 8, 0)
            })
        }
        if (warning != null) field(JLabel(warning))
        if (captured?.unversioned == true) field(JTextArea(CommentsCopy.unversioned, 2, 60).apply { isEditable = false; isOpaque = false; lineWrap = true; wrapStyleWord = true })
        field(JLabel(CommentsCopy.scope)); field(scope)
        field(previewPane); field(destination)
        field(JLabel(CommentsCopy.body).apply { labelFor = this@CommentForm.text })
        add(header, BorderLayout.NORTH)
        add(textPane, BorderLayout.CENTER)
        text.document.addDocumentListener(object : DocumentListener {
            override fun insertUpdate(e: DocumentEvent) = changed()
            override fun removeUpdate(e: DocumentEvent) = changed()
            override fun changedUpdate(e: DocumentEvent) = changed()
        })
        destination.addActionListener { changed() }
        scope.addActionListener { updatePreview(); changed() }
        updatePreview()
    }
    private fun updatePreview() {
        previewPane.isVisible = selectedScope == CommentScope.SELECTION
        preview.text = if (previewPane.isVisible) captured?.snippet.orEmpty() else ""
        revalidate(); repaint()
        preview.caretPosition = 0
    }
    fun save(submit: (String, String, CommentScope, (String?) -> Unit) -> Unit, completed: (String?) -> Unit) {
        if (!canSave) return
        val kind = destinations[destination.selectedIndex]
        val body = text.text
        val target = selectedScope
        saving(true)
        var settled = false
        val done: (String?) -> Unit = { error ->
            if (!settled) {
                settled = true
                if (error != null) saving(false)
                completed(error)
            }
        }
        try { submit(kind, body, target, done) } catch (error: Exception) { done(error.message ?: CommentsCopy.failed) }
    }
    fun saving(value: Boolean) {
        busy = value
        scope.isEnabled = !value; destination.isEnabled = !value; text.isEditable = !value
        changed()
    }
}
