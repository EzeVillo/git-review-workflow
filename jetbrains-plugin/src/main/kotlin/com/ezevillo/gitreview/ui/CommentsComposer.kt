package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.*
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.DialogWrapper
import java.awt.event.ActionEvent
import javax.swing.*

/** Frozen code context, explicit destination, and a single in-flight save. */
class CommentsComposer(project: Project, captured: CommentCapture?, destinations: List<String>, warning: String? = null, private val submit: (String, String, CommentScope, (String?) -> Unit) -> Unit) : DialogWrapper(project) {
    private val form = CommentForm(captured, destinations, warning) { update() }
    init {
        title = CommentsCopy.add; setOKButtonText(CommentsCopy.submit); init(); update()
        form.text.inputMap.put(KeyStroke.getKeyStroke("control ENTER"), "save-comment")
        form.text.actionMap.put("save-comment", object : AbstractAction() { override fun actionPerformed(e: ActionEvent) { if (isOKActionEnabled) doOKAction() } })
    }
    private fun update() {
        isOKActionEnabled = form.canSave
        cancelAction.isEnabled = !form.busy
        setOKButtonText(if (form.busy) CommentsCopy.saving else CommentsCopy.submit)
    }
    override fun createCenterPanel(): JComponent = form
    override fun getPreferredFocusedComponent(): JComponent = form.text
    override fun doCancelAction() { if (form.canCancel) super.doCancelAction() }
    override fun doOKAction() {
        if (!form.canSave) return
        setErrorText(null)
        form.save(submit) { error ->
            // DialogWrapper.doOKAction checks the disabled OK action and refuses to close.
            if (error == null) close(OK_EXIT_CODE) else setErrorText(error)
        }
    }
}
