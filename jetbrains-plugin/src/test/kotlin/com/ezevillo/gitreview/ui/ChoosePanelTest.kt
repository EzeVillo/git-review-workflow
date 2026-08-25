package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.UserCopy
import com.intellij.util.ui.JBUI
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.awt.Component
import java.awt.Dimension
import javax.swing.DefaultListModel
import javax.swing.JList
import javax.swing.JTextField

/**
 * El picker pide su ancho, no lo hereda de la lista: una JList recorta lo que
 * pide cuando sus ítems son largos, y las etiquetas del asistente lo son.
 * [NarrowList] es ese recorte, para que la regresión caiga sin levantar el IDE.
 */
class ChoosePanelTest {
    private class NarrowList(items: Array<String>) : JList<String>(
        DefaultListModel<String>().apply { items.forEach { addElement(it) } },
    ) {
        override fun getPreferredSize(): Dimension =
            Dimension(100, super.getPreferredSize().height)
    }

    private fun widest(list: JList<String>, options: Array<String>): Int {
        val fm = list.getFontMetrics(list.font)
        return options.maxOf { fm.stringWidth(it) }
    }

    private fun panelWidth(message: String, options: Array<String>): Int {
        val list = NarrowList(options)
        return choosePanel(message, JTextField(), list).preferredSize.width
    }

    @Test
    fun `picker asks for the width of its longest option`() {
        val options = UserCopy.SOURCE_LABELS.map { it.second }.toTypedArray()
        val want = minOf(widest(NarrowList(options), options) + JBUI.scale(56), JBUI.scale(720))
        val width = panelWidth(UserCopy.START_ORIGIN_PLACEHOLDER, options)
        assertTrue(width >= want, "width=$width want>=$want")
    }

    @Test
    fun `layout labels drive the width too`() {
        val options = UserCopy.DRAFT_KEYS_LABELS.map { it.second }.toTypedArray()
        val want = minOf(widest(NarrowList(options), options) + JBUI.scale(56), JBUI.scale(720))
        val width = panelWidth(UserCopy.DRAFT_KEYS_PLACEHOLDER, options)
        assertTrue(width >= want, "width=$width want>=$want")
    }

    @Test
    fun `an outsized branch name is capped instead of stretching the dialog`() {
        val width = panelWidth(
            UserCopy.START_BRANCH_PLACEHOLDER,
            arrayOf("feature/" + "x".repeat(500)),
        )
        assertTrue(width <= JBUI.scale(720), "width=$width")
        assertTrue(width >= JBUI.scale(700), "width=$width")
    }

    @Test
    fun `short options still get a usable width`() {
        val width = panelWidth("Pick", arrayOf("a", "b"))
        assertTrue(width >= JBUI.scale(320), "width=$width")
    }

    /**
     * El filtro es parte del picker, siempre: sin el, un repo con muchas ramas
     * solo se navega con las flechas, que es justo el caso que la caja resuelve.
     */
    @Test
    fun `the filter box is part of the picker`() {
        val filter = JTextField()
        val panel = choosePanel("Pick", filter, NarrowList(arrayOf("a", "b")))
        assertTrue(filter.isShowing || contains(panel, filter), "filter not in the panel")
    }

    private fun contains(root: Component, target: Component): Boolean {
        if (root === target) return true
        val container = root as? java.awt.Container ?: return false
        return container.components.any { contains(it, target) }
    }
}
