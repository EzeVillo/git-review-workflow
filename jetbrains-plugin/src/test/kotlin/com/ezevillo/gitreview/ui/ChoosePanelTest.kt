package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.UserCopy
import com.intellij.util.ui.JBUI
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.awt.Component
import java.awt.Dimension
import java.awt.Graphics
import javax.swing.Icon
import javax.swing.JComboBox

/**
 * El picker pide su ancho, no lo hereda del combo: la ComboBox de la plataforma
 * recorta lo que pide cuando sus ítems son largos, y las etiquetas del
 * asistente lo son. [NarrowCombo] es ese recorte, para que la regresión caiga
 * sin levantar el IDE.
 */
class ChoosePanelTest {
    private val icon = object : Icon {
        override fun paintIcon(c: Component?, g: Graphics?, x: Int, y: Int) = Unit
        override fun getIconWidth(): Int = 16
        override fun getIconHeight(): Int = 16
    }

    private class NarrowCombo(items: Array<String>) : JComboBox<String>(items) {
        override fun getPreferredSize(): Dimension =
            Dimension(100, super.getPreferredSize().height)
    }

    private fun widest(combo: JComboBox<String>, options: Array<String>): Int {
        val fm = combo.getFontMetrics(combo.font)
        return options.maxOf { fm.stringWidth(it) }
    }

    @Test
    fun `picker asks for the width of its longest option`() {
        val options = UserCopy.SOURCE_LABELS.map { it.second }.toTypedArray()
        val combo = NarrowCombo(options)
        val want = minOf(widest(combo, options) + JBUI.scale(56), JBUI.scale(720))
        val width = choosePanel(UserCopy.START_ORIGIN_PLACEHOLDER, combo, icon).preferredSize.width
        assertTrue(width >= want, "width=$width want>=$want")
    }

    @Test
    fun `layout labels drive the width too`() {
        val options = UserCopy.DRAFT_KEYS_LABELS.map { it.second }.toTypedArray()
        val combo = NarrowCombo(options)
        val want = minOf(widest(combo, options) + JBUI.scale(56), JBUI.scale(720))
        val width = choosePanel(UserCopy.DRAFT_KEYS_PLACEHOLDER, combo, icon).preferredSize.width
        assertTrue(width >= want, "width=$width want>=$want")
    }

    @Test
    fun `an outsized branch name is capped instead of stretching the dialog`() {
        val combo = NarrowCombo(arrayOf("feature/" + "x".repeat(500)))
        val width = choosePanel(UserCopy.START_BRANCH_PLACEHOLDER, combo, icon).preferredSize.width
        // Tope, mas el icono, el gap y el borde del panel exterior.
        assertTrue(width <= JBUI.scale(720) + JBUI.scale(64), "width=$width")
        assertTrue(width >= JBUI.scale(700), "width=$width")
    }

    @Test
    fun `short options still get a usable width`() {
        val combo = NarrowCombo(arrayOf("a", "b"))
        val width = choosePanel("Pick", combo, icon).preferredSize.width
        assertTrue(width >= JBUI.scale(320), "width=$width")
    }
}
