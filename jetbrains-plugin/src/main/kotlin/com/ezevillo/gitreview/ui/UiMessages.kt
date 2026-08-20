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
import java.awt.Component
import java.awt.Dimension
import javax.swing.DefaultListCellRenderer
import javax.swing.Icon
import javax.swing.JComboBox
import javax.swing.JComponent
import javax.swing.JLabel
import javax.swing.JList
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

/**
 * El cuerpo del picker, aparte del diálogo —y por eso `internal`— porque el
 * ancho es lo único que este diálogo decide, y así un test headless lo mira sin
 * levantar la plataforma.
 *
 * [DialogWrapper] empaqueta contra el tamaño preferido de este panel, y un
 * combo no pide el ancho de sus ítems: las etiquetas del asistente ("Local —
 * review the local branch without fetching…") salían cortadas con puntos
 * suspensivos, y leerlas pedía agrandar la ventana a mano en cada paso. Se mide
 * el ítem más largo y se pide ese ancho, con tope para que un nombre de rama
 * desmedido no estire el diálogo a lo ancho de la pantalla — ahí queda el
 * tooltip, y el diálogo se puede agrandar y recuerda el tamaño.
 */
internal fun choosePanel(message: String, combo: JComboBox<String>, icon: Icon): JComponent {
    val fm = combo.getFontMetrics(combo.font)
    val widest = (0 until combo.itemCount)
        .maxOfOrNull { fm.stringWidth(combo.getItemAt(it) ?: "") } ?: 0
    // El extra cubre la flecha y los bordes del combo. El mensaje va arriba y no
    // manda, salvo que sea más largo que todas las opciones.
    val target = maxOf(widest + JBUI.scale(56), fm.stringWidth(message))
        .coerceIn(JBUI.scale(320), JBUI.scale(720))

    val body = object : JPanel(BorderLayout(0, JBUI.scale(6))) {
        override fun getPreferredSize(): Dimension =
            Dimension(target, super.getPreferredSize().height)
    }
    body.add(JLabel(message), BorderLayout.NORTH)
    body.add(combo, BorderLayout.CENTER)

    val panel = JPanel(BorderLayout(JBUI.scale(10), 0))
    panel.border = JBUI.Borders.empty(8)
    panel.add(JLabel(icon), BorderLayout.WEST)
    panel.add(body, BorderLayout.CENTER)
    return panel
}

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
        // El texto entero, para el ítem que igual no entre en el tope de ancho.
        // Renderer de Swing y no `SimpleListCellRenderer.create`: ese método está
        // scheduled for removal —lo reporta la validación del Marketplace— y su
        // reemplazo, el DSL `listCellRenderer`, cuelga de `LcrRow`, que es
        // @ApiStatus.Experimental. Sin until-build en el descriptor, atarse a una
        // forma que puede cambiar es canjear un warning por un NoSuchMethodError
        // en un IDE futuro; esto es un tooltip sobre un JLabel, no vale el riesgo.
        combo.renderer = object : DefaultListCellRenderer() {
            override fun getListCellRendererComponent(
                list: JList<*>,
                value: Any?,
                index: Int,
                selected: Boolean,
                focused: Boolean,
            ): Component {
                val component = super.getListCellRendererComponent(list, value, index, selected, focused)
                toolTipText = value as? String
                return component
            }
        }
        if (options.isNotEmpty()) {
            combo.selectedIndex = options.indexOf(defaultOption).coerceAtLeast(0)
        }
        combo.toolTipText = combo.selectedItem as? String
        combo.addActionListener { combo.toolTipText = combo.selectedItem as? String }
        isResizable = true
        init()
    }

    val selectedIndex: Int get() = combo.selectedIndex

    /**
     * Todos los pickers comparten clave a propósito: son el mismo diálogo con
     * otra lista, así que agrandarlo una vez alcanza para los pasos que siguen.
     */
    override fun getDimensionServiceKey(): String = "GitReview.ChooseDialog"

    override fun getPreferredFocusedComponent(): JComponent = combo

    override fun createCenterPanel(): JComponent = choosePanel(message, combo, icon)
}
