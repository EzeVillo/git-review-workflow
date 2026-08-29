package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.ControlId
import com.ezevillo.gitreview.domain.revealsPanel
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.diagnostic.logger
import com.intellij.openapi.project.Project
import com.intellij.openapi.wm.ToolWindowManager

private val logger = logger<GitReviewService>()

/**
 * El id del descriptor, que no se puede renombrar sin renombrarlo tambien en
 * `plugin.xml`: la tool window se resuelve POR id y no hay constante compartida
 * entre el XML y el codigo.
 */
private const val TOOL_WINDOW_ID = "gitReview.walkthrough"

/**
 * LA UNICA PUERTA al reveal, y por eso toma el [id]: es lo que hace que
 * `reveals:` del canonico GOBIERNE en vez de solo describir -- la misma leccion
 * que dejo `confirms:`, que se declaraba en tres lugares y no gobernaba en
 * ninguno.
 *
 * Se llama DESPUES del refresco y solo en verde: revelar un panel que no cambio
 * es el salto que ensena a ignorar los saltos, y sobre un error el mensaje ya
 * esta en pantalla.
 *
 * `show` y no `activate`: trae la tool window al frente sin llevarle el foco, asi
 * que el revisor sigue escribiendo donde estaba. Y va por `invokeLater` porque
 * esto muta el modelo de ventanas de la plataforma, que es EDT-only: los
 * llamadores estan en handlers de accion, pero uno solo que llegue desde un hilo
 * de fondo seria un fallo de runtime y de ninguna otra forma.
 *
 * El gate estatico es `RevealContractTest`.
 */
fun revealPanel(project: Project, id: ControlId) {
    if (!revealsPanel(id)) {
        // Un id que el canonico no declara NO revela: aca la degradacion segura
        // es la contraria a la de UiMessages.confirm -- un reveal de mas hace
        // saltar el panel cuando no corresponde, que es exactamente el ruido que
        // esta tabla existe para evitar.
        logger.error("revealPanel() called for ${id.wire}, which the canonical does not list under reveals:")
        return
    }
    ApplicationManager.getApplication().invokeLater({
        if (project.isDisposed) return@invokeLater
        ToolWindowManager.getInstance(project).getToolWindow(TOOL_WINDOW_ID)?.show()
    }, project.disposed)
}
