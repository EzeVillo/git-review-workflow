package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.UserCopy
import com.ezevillo.gitreview.domain.cliErrorText
import com.ezevillo.gitreview.domain.flattenCliMessage
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.Messages
import javax.swing.Icon

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

    fun choose(
        project: Project?,
        message: String,
        title: String,
        options: Array<String>,
        defaultOption: String = options.first(),
        icon: Icon = Messages.getQuestionIcon(),
    ): Int =
        Messages.showChooseDialog(project, message, title, icon, options, defaultOption)

    fun input(
        project: Project?,
        message: String,
        title: String,
    ): String? = Messages.showInputDialog(project, message, title, null)?.trim()?.takeIf { it.isNotEmpty() }

    fun flatten(text: String): String = flattenCliMessage(text)
}
