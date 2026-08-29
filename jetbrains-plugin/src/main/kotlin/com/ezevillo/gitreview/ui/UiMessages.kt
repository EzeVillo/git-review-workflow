package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.ControlId
import com.ezevillo.gitreview.domain.PickerRows
import com.ezevillo.gitreview.domain.UserCopy
import com.ezevillo.gitreview.domain.cliErrorText
import com.ezevillo.gitreview.domain.flattenCliMessage
import com.ezevillo.gitreview.domain.requiresConfirmation
import com.intellij.openapi.diagnostic.logger
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.DialogWrapper
import com.intellij.openapi.ui.Messages
import com.intellij.ui.ColoredListCellRenderer
import com.intellij.ui.DocumentAdapter
import com.intellij.ui.SimpleTextAttributes
import com.intellij.ui.components.JBList
import com.intellij.ui.components.JBScrollPane
import com.intellij.ui.components.JBTextField
import com.intellij.util.ui.JBUI
import java.awt.BorderLayout
import java.awt.Dimension
import java.awt.event.KeyEvent
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import javax.swing.DefaultListModel
import javax.swing.Icon
import javax.swing.JComponent
import javax.swing.JLabel
import javax.swing.JList
import javax.swing.JPanel
import javax.swing.KeyStroke
import javax.swing.ListSelectionModel
import javax.swing.event.DocumentEvent

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
    private val logger = logger<UiMessages>()

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

    /** Which of a three-way dialog's exits the user took. */
    enum class Choice { FIRST, SECOND, CANCELLED }

    /**
     * Two named courses of action plus Cancel, for the questions where refusing
     * and choosing the other option are different answers.
     *
     * [confirm] cannot express this: its "no" is a cancel, so a second course of
     * action would have to be a second dialog. Here both exits do something and
     * the third one does nothing, which is what "Update / Start over / Cancel"
     * needs.
     */
    fun choose(
        project: Project?,
        title: String,
        detail: String,
        firstText: String,
        secondText: String,
        icon: Icon = Messages.getWarningIcon(),
    ): Choice {
        val body = detail.ifBlank { title }
        val result = Messages.showYesNoCancelDialog(
            project,
            body,
            title,
            firstText,
            secondText,
            "Cancel",
            icon,
        )
        return when (result) {
            Messages.YES -> Choice.FIRST
            Messages.NO -> Choice.SECOND
            else -> Choice.CANCELLED
        }
    }

    /**
     * LA UNICA PUERTA a un dialogo de confirmacion de este plugin, y por eso
     * toma el [id]: es lo que hace que `confirms:` del canonico GOBIERNE en vez
     * de solo describir.
     *
     * Antes la tabla existia y nadie la consultaba -- el despachador la miraba
     * en un `if` de cuerpo vacio --, asi que sacar o agregar una confirmacion no
     * ponia nada en rojo, y el canonico llego a declarar `confirms: true` para
     * un control que hacia rato no confirmaba. El id no cambia lo que se dibuja:
     * cambia que un llamador no pueda abrir un modal que el contrato no declara.
     *
     * En debug tira; en produccion escribe al log y sigue confirmando, que es la
     * degradacion segura -- un modal de mas molesta, uno de menos borra trabajo
     * sin preguntar. El gate estatico es ConfirmationContractTest.
     */
    fun confirm(
        project: Project?,
        id: ControlId,
        title: String,
        detail: String,
        yesText: String,
        icon: Icon = Messages.getWarningIcon(),
        noText: String = "Cancel",
    ): Boolean {
        if (!requiresConfirmation(id)) {
            logger.error("confirm() called for ${id.wire}, which the canonical marks confirms: false")
        }
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
     * Single-choice dialog: modal, a filter box over a list, index result, -1 on
     * cancel — the shape every wizard and action here already expects.
     *
     * Hand-rolled on [DialogWrapper] because `Messages.showChooseDialog` is
     * deprecated (the Marketplace verifier flags it) and the platform has no
     * drop-in replacement: `Messages.showDialog` turns every option into a
     * button, which does not survive a branch list.
     *
     * The filter box is always there, with two options or two hundred: it is how
     * you pick, not a rescue for long lists. A picker that hides it below some
     * count teaches two different interactions for the same question, and the
     * one learned first is the one that does not filter.
     */
    fun choose(
        project: Project?,
        message: String,
        title: String,
        options: Array<String>,
        defaultOption: String = options.first(),
    ): Int {
        val dialog = ChooseDialog(project, message, title, options, defaultOption)
        return if (dialog.showAndGet()) dialog.selectedIndex else -1
    }

    /**
     * Same picker, but the typed text is itself an answer: it is offered as the
     * first row whenever it does not match an option exactly. Only `compare`
     * needs this — it takes a commit-ish, and a tag or a SHA is a legitimate
     * answer no branch list carries. Every other picker stays closed over its
     * options, where a typo cannot become a branch name nobody meant.
     *
     * Null on cancel and on empty.
     */
    fun chooseOrType(
        project: Project?,
        message: String,
        title: String,
        options: Array<String>,
    ): String? {
        if (options.isEmpty()) return input(project, message, title)
        val dialog = ChooseDialog(
            project, message, title, options, options.first(), freeText = true,
        )
        if (!dialog.showAndGet()) return null
        return dialog.selectedValue?.trim()?.takeIf { it.isNotEmpty() }
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
 * [DialogWrapper] empaqueta contra el tamaño preferido de este panel, y ni un
 * combo ni una lista piden el ancho de sus ítems: las etiquetas del asistente
 * ("Local — review the local branch without fetching…") salían cortadas con
 * puntos suspensivos, y leerlas pedía agrandar la ventana a mano en cada paso.
 * Se mide el ítem más largo y se pide ese ancho, con tope para que un nombre de
 * rama desmedido no estire el diálogo a lo ancho de la pantalla — ahí queda el
 * tooltip, y el diálogo se puede agrandar y recuerda el tamaño.
 *
 * Sin ícono: el de `Messages.getQuestionIcon()` que traía antes era el mismo
 * círculo azul en los cuatro pasos del asistente sin importar la pregunta, así
 * que no distinguía nada — y centrado por [BorderLayout] contra una lista de
 * doce filas quedaba flotando a media altura, leyéndose como un botón de ayuda
 * roto en vez de una decoración. Un filtro-sobre-lista ya se explica solo.
 */
internal fun choosePanel(
    message: String,
    filter: JComponent,
    list: JList<String>,
): JComponent {
    val fm = list.getFontMetrics(list.font)
    val model = list.model
    val widest = (0 until model.size)
        .maxOfOrNull { fm.stringWidth(model.getElementAt(it) ?: "") } ?: 0
    // El extra cubre la barra de scroll y los bordes. El mensaje va arriba y no
    // manda, salvo que sea más largo que todas las opciones.
    val target = maxOf(widest + JBUI.scale(56), fm.stringWidth(message))
        .coerceIn(JBUI.scale(320), JBUI.scale(720))

    val body = object : JPanel(BorderLayout(0, JBUI.scale(6))) {
        override fun getPreferredSize(): Dimension =
            Dimension(target, super.getPreferredSize().height)
    }
    body.border = JBUI.Borders.empty(8)
    body.add(JLabel(message), BorderLayout.NORTH)

    val middle = JPanel(BorderLayout(0, JBUI.scale(6)))
    middle.add(filter, BorderLayout.NORTH)
    val scroll = JBScrollPane(list)
    // Alto fijo en filas y no en ítems: una lista de dos opciones y una de
    // doscientas abren el mismo diálogo, así que filtrar no lo hace saltar.
    scroll.preferredSize = Dimension(target, JBUI.scale(240))
    middle.add(scroll, BorderLayout.CENTER)
    body.add(middle, BorderLayout.CENTER)

    return body
}

/**
 * The filter-over-a-list dialog behind [UiMessages.choose] and
 * [UiMessages.chooseOrType].
 *
 * La fila que se devuelve nunca se lee de la posición visible: [indices] lleva,
 * por fila, el índice en el array del llamador, así que filtrar no puede cambiar
 * lo que significa una selección. En modo [freeText] hay una fila más, la de lo
 * tipeado, cuyo índice es [TYPED] justamente porque no está en ese array.
 */
private class ChooseDialog(
    project: Project?,
    private val message: String,
    dialogTitle: String,
    private val options: Array<String>,
    defaultOption: String,
    private val freeText: Boolean = false,
) : DialogWrapper(project, true) {
    private val filter = JBTextField()
    private val model = DefaultListModel<String>()
    private val list = JBList(model)

    /** Por fila visible, el índice en [options] — o [TYPED]. */
    private val indices = mutableListOf<Int>()

    init {
        title = dialogTitle
        list.selectionMode = ListSelectionModel.SINGLE_SELECTION
        list.visibleRowCount = 12
        // `ColoredListCellRenderer` y no `DefaultListCellRenderer`: éste último
        // pinta con los colores por defecto de Swing en vez de los del tema activo
        // de la plataforma, así que una fila sin seleccionar salía en el celeste de
        // link de Swing en vez del gris de texto normal de Darcula/tema claro. Y no
        // `SimpleListCellRenderer.create`: ese método está scheduled for removal
        // —lo reporta la validación del Marketplace— y su reemplazo, el DSL
        // `listCellRenderer`, cuelga de `LcrRow`, que es @ApiStatus.Experimental.
        // `ColoredListCellRenderer` no tiene ninguno de los dos problemas: sigue
        // los colores de selección/foco de la lista como cualquier popup nativo, y
        // de paso separa en gris la mitad descriptiva de la etiqueta (" — texto" o
        // " (current)"), que antes se leía con el mismo peso que el nombre.
        list.cellRenderer = object : ColoredListCellRenderer<String>() {
            init {
                ipad = JBUI.insets(3, 8)
            }

            override fun customizeCellRenderer(
                list: JList<out String>,
                value: String,
                index: Int,
                selected: Boolean,
                hasFocus: Boolean,
            ) {
                toolTipText = value
                val dash = value.indexOf(" — ")
                val suffix = if (dash >= 0) dash else PAREN_SUFFIX.find(value)?.range?.first ?: -1
                if (suffix < 0) {
                    append(value)
                } else {
                    append(value.substring(0, suffix))
                    append(value.substring(suffix), SimpleTextAttributes.GRAYED_ATTRIBUTES)
                }
            }
        }
        // Doble click elige, como en cualquier lista de la plataforma.
        list.addMouseListener(object : MouseAdapter() {
            override fun mouseClicked(event: MouseEvent) {
                if (event.clickCount == 2 && list.selectedIndex >= 0) doOKAction()
            }
        })

        filter.document.addDocumentListener(object : DocumentAdapter() {
            override fun textChanged(event: DocumentEvent) = applyFilter()
        })
        // Abajo desde el filtro camina a la lista en vez de morir ahí. Enter no se
        // toca: lo toma el botón por defecto del diálogo, que es lo que se espera.
        filter.registerKeyboardAction(
            { if (model.size() > 0) list.requestFocusInWindow() },
            KeyStroke.getKeyStroke(KeyEvent.VK_DOWN, 0),
            JComponent.WHEN_FOCUSED,
        )

        applyFilter()
        selectOriginal(options.indexOf(defaultOption).coerceAtLeast(0))
        isResizable = true
        init()
    }

    /** El índice en [options], o -1 cuando lo elegido es la fila de texto libre. */
    val selectedIndex: Int
        get() = indices.getOrNull(list.selectedIndex)
            ?.takeIf { it != PickerRows.TYPED } ?: PickerRows.NONE

    /** Lo elegido como texto: una opción, o lo tipeado en modo [freeText]. */
    val selectedValue: String? get() = list.selectedValue

    override fun doOKAction() {
        // Sin fila elegida no hay respuesta, y aceptar igual devolvería la primera
        // opción a espaldas del revisor.
        if (list.selectedIndex < 0) return
        super.doOKAction()
    }

    private fun applyFilter() {
        val needle = filter.text.trim()
        val keep = indices.getOrNull(list.selectedIndex)
        val rows = PickerRows.rows(options.asList(), needle, freeText)

        model.clear()
        indices.clear()
        rows.forEach { index ->
            model.addElement(if (index == PickerRows.TYPED) needle else options[index])
            indices.add(index)
        }

        list.selectedIndex = PickerRows.selection(rows, keep)
        if (list.selectedIndex >= 0) list.ensureIndexIsVisible(list.selectedIndex)
    }

    private fun selectOriginal(original: Int) {
        val row = indices.indexOf(original)
        list.selectedIndex = if (row >= 0) row else if (model.size() > 0) 0 else -1
    }

    /**
     * Todos los pickers comparten clave a propósito: son el mismo diálogo con
     * otra lista, así que agrandarlo una vez alcanza para los pasos que siguen.
     */
    override fun getDimensionServiceKey(): String = "GitReview.ChooseDialog"

    override fun getPreferredFocusedComponent(): JComponent = filter

    override fun createCenterPanel(): JComponent = choosePanel(message, filter, list)

    private companion object {
        /** " (current)" y similares: el paréntesis final de la etiqueta. */
        val PAREN_SUFFIX = Regex(""" \([^)]*\)$""")
    }
}
