package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.UnopenedDraft
import com.ezevillo.gitreview.domain.UserCopy
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.DialogWrapper
import com.intellij.util.ui.JBUI
import java.awt.BorderLayout
import javax.swing.JComponent
import javax.swing.JPanel

/**
 * El aviso que espera mientras el revisor completa su borrador (011,
 * contracts/client-draft-flow.md § Requisitos del aviso de espera).
 *
 * `isModal = false` no es una preferencia: lo que se le está pidiendo al
 * revisor es editar un archivo, y toda la familia `Messages.*` —que es lo que
 * usa el resto del plugin— bloquea el IDE entero mientras está abierta. Un
 * `DialogWrapper` no modal deja el editor vivo y sigue siendo persistente (no
 * se auto-oculta) y reintentable: tras un rechazo se vuelve a abrir con el
 * motivo a la vista, sin límite de intentos.
 *
 * El asistente de IntelliJ es síncrono, así que acá es donde se corta: el flujo
 * se reanuda desde [onClosed], con la rama, el origen y el rango capturados en
 * la closure del llamador.
 */
class DraftWaitDialog(
    project: Project,
    private val branch: String,
    private val error: String?,
    private val unopened: UnopenedDraft?,
    private val onClosed: (proceed: Boolean) -> Unit,
) : DialogWrapper(project, false) {

    init {
        title = UserCopy.DRAFT_WAIT_TITLE
        isModal = false
        setOKButtonText(UserCopy.DRAFT_CONTINUE_BUTTON)
        init()
    }

    override fun createCenterPanel(): JComponent {
        val panel = JPanel(BorderLayout())
        panel.border = JBUI.Borders.empty(8)
        val text = UserCopy.draftWaitMessage(branch, error, unopened)
        // HTML para que un stderr largo se envuelva en vez de estirar el diálogo
        // a lo ancho de la pantalla.
        panel.add(
            javax.swing.JLabel("<html><body style='width: 380px'>${escapeHtml(text)}</body></html>"),
            BorderLayout.CENTER,
        )
        return panel
    }

    override fun doOKAction() {
        super.doOKAction()
        onClosed(true)
    }

    /** Cancel y la cruz de la ventana son lo mismo: conservan el borrador. */
    override fun doCancelAction() {
        super.doCancelAction()
        onClosed(false)
    }
}
