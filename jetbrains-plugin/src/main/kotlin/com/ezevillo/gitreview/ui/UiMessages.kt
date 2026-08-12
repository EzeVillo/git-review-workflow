package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.UserCopy
import com.ezevillo.gitreview.domain.cliErrorText
import com.ezevillo.gitreview.domain.flattenCliMessage
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.ComboBox
import com.intellij.openapi.ui.DialogWrapper
import com.intellij.openapi.ui.Messages
import com.intellij.util.ui.JBUI
import java.awt.BorderLayout
import javax.swing.Icon
import javax.swing.JComponent
import javax.swing.JLabel
import javax.swing.JPanel

/**
 * Thin wrappers around IntelliJ [Messages] so dialog copy stays aligned with
 * VS Code (`showWarningMessage` / `showErrorMessage` / `showInformationMessage`).
 *
 * Mapping:
 * - VS Code **message** → dialog title
 * - VS Code **detail** → dialog body
 * - VS Code **button** → Yes / primary button text
 */
object UiMessages {
    fun info(project: Project?, text: String, title: String = UserCopy.PRODUCT_TITLE) {
        Messages.showInfoMessage(project, text, title)
    }

    fun warning(project: Project?, text: String, title: String = UserCopy.PRODUCT_TITLE) {
        Messages.showWarningDialog(project, text, title)
    }

    fun error(project: Project?, text: String, title: String = UserCopy.PRODUCT_TITLE) {
        val body = text.ifBlank { "Operation failed." }
        Messages.showErrorDialog(project, body, title)
    }

    /** CLI failure: prefer flattened stderr, then stdout, then [fallback]. */
    fun cliError(
        project: Project?,
        stderr: String,
        fallback: String,
        stdout: String = "",
        title: String = UserCopy.PRODUCT_TITLE,
    ) {
        error(project, cliErrorText(stderr, stdout, fallback), title)
    }

    /**
     * Modal confirm matching VS Code `showWarningMessage(..., { modal, detail }, button)`.
     * Returns true only when the affirmative button is chosen.
     */
    fun confirm(
        project: Project?,
        title: String,
        detail: String,
        yesText: String,
        icon: Icon = Messages.getWarningIcon(),
        noText: String = "Cancel",
    ): Boolean {
        val body = detail.ifBlank { title }
        val result = Messages.showYesNoDialog(
            project,
            body,
            title,
            yesText,
            noText,
            icon,
        )
        return result == Messages.YES
    }

    /**
     * Single-choice dialog: modal, one non-editable combo, index result, -1 on
     * cancel — the shape every wizard and action here already expects.
     *
     * Hand-rolled on [DialogWrapper] because `Messages.showChooseDialog` is
     * deprecated (the Marketplace verifier flags it) and the platform has no
     * drop-in replacement: `Messages.showDialog` turns every option into a
     * button, which does not survive a branch list.
     */
    fun choose(
        project: Project?,
        message: String,
        title: String,
        options: Array<String>,
        defaultOption: String = options.first(),
        icon: Icon = Messages.getQuestionIcon(),
    ): Int {
        val dialog = ChooseDialog(project, message, title, options, defaultOption, icon)
        return if (dialog.showAndGet()) dialog.selectedIndex else -1
    }

    fun input(
        project: Project?,
        message: String,
        title: String,
    ): String? = Messages.showInputDialog(project, message, title, null)?.trim()?.takeIf { it.isNotEmpty() }

    fun flatten(text: String): String = flattenCliMessage(text)
}

/** Escapes text that is about to be dropped inside a Swing HTML label. */
internal fun escapeHtml(text: String): String =
    text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

/** The combo dialog behind [UiMessages.choose]. */
private class ChooseDialog(
    project: Project?,
    private val message: String,
    dialogTitle: String,
    options: Array<String>,
    defaultOption: String,
    private val icon: Icon,
) : DialogWrapper(project, true) {
    private val combo = ComboBox(options)

    init {
        title = dialogTitle
        combo.isEditable = false
        if (options.isNotEmpty()) {
            combo.selectedIndex = options.indexOf(defaultOption).coerceAtLeast(0)
        }
        init()
    }

    val selectedIndex: Int get() = combo.selectedIndex

    override fun getPreferredFocusedComponent(): JComponent = combo

    override fun createCenterPanel(): JComponent {
        val panel = JPanel(BorderLayout(JBUI.scale(10), 0))
        panel.border = JBUI.Borders.empty(8)
        panel.add(JLabel(icon), BorderLayout.WEST)

        val body = JPanel(BorderLayout(0, JBUI.scale(6)))
        body.add(JLabel(message), BorderLayout.NORTH)
        body.add(combo, BorderLayout.CENTER)
        panel.add(body, BorderLayout.CENTER)
        return panel
    }
}
