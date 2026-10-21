package com.ezevillo.gitreview.host

import com.intellij.openapi.Disposable
import com.intellij.openapi.components.Service
import com.intellij.openapi.editor.Editor
import com.intellij.openapi.editor.EditorFactory
import com.intellij.openapi.editor.event.*
import com.intellij.openapi.fileEditor.FileEditorManager
import com.intellij.openapi.fileEditor.FileEditorManagerEvent
import com.intellij.openapi.fileEditor.FileEditorManagerListener
import com.intellij.openapi.project.Project
import com.intellij.openapi.util.Disposer
import java.awt.KeyboardFocusManager
import java.beans.PropertyChangeListener
import java.lang.ref.WeakReference
import javax.swing.SwingUtilities

/** Retains the code editor when focus moves into the review panel, including diff editors. */
@Service(Service.Level.PROJECT)
class CommentEditorTracker(private val project: Project) : Disposable {
    private var last = WeakReference<Editor>(null)
    init {
        val events = EditorFactory.getInstance().eventMulticaster
        events.addSelectionListener(object : SelectionListener {
            override fun selectionChanged(event: SelectionEvent) { remember(event.editor) }
        }, this)
        events.addCaretListener(object : CaretListener {
            override fun caretPositionChanged(event: CaretEvent) { remember(event.editor) }
        }, this)
        project.messageBus.connect(this).subscribe(FileEditorManagerListener.FILE_EDITOR_MANAGER, object : FileEditorManagerListener {
            override fun selectionChanged(event: FileEditorManagerEvent) {
                last = WeakReference(FileEditorManager.getInstance(project).selectedTextEditor)
            }
        })
        val focus = KeyboardFocusManager.getCurrentKeyboardFocusManager()
        val listener = PropertyChangeListener {
            val owner = focus.focusOwner ?: return@PropertyChangeListener
            EditorFactory.getInstance().allEditors.firstOrNull { it.project == project && !it.isDisposed && SwingUtilities.isDescendingFrom(owner, it.contentComponent) }?.let { remember(it) }
        }
        focus.addPropertyChangeListener("focusOwner", listener)
        Disposer.register(this, Disposable { focus.removePropertyChangeListener("focusOwner", listener) })
    }
    private fun remember(editor: Editor) {
        val owner = KeyboardFocusManager.getCurrentKeyboardFocusManager().focusOwner ?: return
        if (editor.project == project && !editor.isDisposed && SwingUtilities.isDescendingFrom(owner, editor.contentComponent)) last = WeakReference(editor)
    }
    fun editor(): Editor? {
        val owner = KeyboardFocusManager.getCurrentKeyboardFocusManager().focusOwner
        EditorFactory.getInstance().allEditors.firstOrNull { it.project == project && !it.isDisposed && owner != null && SwingUtilities.isDescendingFrom(owner, it.contentComponent) }?.let { last = WeakReference(it) }
        return last.get()?.takeUnless { it.isDisposed } ?: FileEditorManager.getInstance(project).selectedTextEditor
    }
    override fun dispose() { last.clear() }
}
