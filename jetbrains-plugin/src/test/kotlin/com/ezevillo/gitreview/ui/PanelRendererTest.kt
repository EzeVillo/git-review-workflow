package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.ControlId
import com.ezevillo.gitreview.domain.panelLayout
import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.awt.BorderLayout
import javax.swing.JButton
import javax.swing.JPanel
import javax.swing.SwingConstants

class PanelRendererTest {
    @Test
    fun `renderer produces controls in layout order with enabled state`() {
        val model = PanelFixtures.reviewWalk(atFirst = true)
        val layout = panelLayout(model)
        val expected = layout.collectControls().filter {
            it.id in setOf(
                ControlId.SHOW_WHY,
                ControlId.OPEN_ENTRY,
                ControlId.OPEN_CHANGE,
                ControlId.PREV,
                ControlId.NEXT,
            )
        }
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _, _ -> false }
        val root = renderer.render(layout)
        val buttons = PanelRenderer.collectButtons(root)
        // At least as many body buttons as expected body controls
        assertTrue(buttons.size >= expected.size, "buttons=${buttons.size} expected>=${expected.size}")
        val prev = buttons.find { it.toolTipText == "Previous entry" || it.accessibleContext.accessibleName == "Previous entry" }
        assertTrue(prev != null, "prev icon button present")
        assertFalse(prev!!.isEnabled, "prev disabled on first entry")
        val next = buttons.find { it.toolTipText == "Next entry" || it.accessibleContext.accessibleName == "Next entry" }
        assertTrue(next != null)
        assertTrue(next!!.isEnabled)
    }

    @Test
    fun `icon controls expose accessible names`() {
        val layout = panelLayout(PanelFixtures.reviewWalk())
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _, _ -> false }
        val buttons = PanelRenderer.collectButtons(renderer.render(layout))
        val names = buttons.mapNotNull { it.accessibleContext?.accessibleName ?: it.toolTipText }
        assertTrue(names.any { it == "Previous entry" })
        assertTrue(names.any { it == "Next entry" })
    }

    @Test
    fun `section open state survives re-render`() {
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _, _ -> false }
        val layout1 = panelLayout(PanelFixtures.noReviewReady())
        val root1 = renderer.render(layout1)
        // Open first tools section toggle if present
        val toggles = PanelRenderer.collectButtons(root1).filter { it.text?.contains("Other actions") == true }
        if (toggles.isNotEmpty()) {
            toggles.first().doClick()
        }
        val layout2 = panelLayout(PanelFixtures.noReviewReady())
        val root2 = renderer.render(layout2)
        val toggle2 = PanelRenderer.collectButtons(root2).find { it.text?.contains("Other actions") == true }
        // After expand, re-render should keep open (▼ marker)
        if (toggle2 != null && toggles.isNotEmpty()) {
            assertTrue(toggle2.text.startsWith("▼"), "section should stay open: ${toggle2.text}")
        }
    }

    @Test
    fun `the primary control is painted as the primary one and the rest are not`() {
        val chrome = PreviewPanelChrome()
        val renderer = PanelRenderer(chrome) { _, _, _ -> false }
        val buttons = PanelRenderer.collectButtons(
            renderer.render(panelLayout(PanelFixtures.noReviewReady())),
        )
        val start = buttons.find { it.text == "Start a review" }
        assertTrue(start != null, "start button present")
        assertEquals(chrome.primaryButtonBackground(), start!!.background)
        val discard = buttons.find { it.text == "Discard" }
        assertTrue(discard != null, "inventory button present")
        assertTrue(
            discard!!.background != chrome.primaryButtonBackground(),
            "only one control per situation carries the primary paint",
        )
    }

    @Test
    fun `no block in the column may grow past the height it asked for`() {
        // The stretch is what pushed Start to the bottom of the pane and blew
        // air between every paragraph.
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _, _ -> false }
        val offenders = ArrayList<String>()
        var situation = ""
        fun walk(c: java.awt.Component) {
            if (c is java.awt.Container) {
                val column = c.layout as? javax.swing.BoxLayout
                if (column != null) {
                    for (child in c.components) {
                        // A filler is the deliberate stretch: the glue that pins
                        // the footer to the bottom edge, and the struts.
                        if (child is javax.swing.Box.Filler) continue
                        if (child is javax.swing.JComponent && child.maximumSize.height == Int.MAX_VALUE) {
                            offenders.add("$situation: ${child::class.simpleName} in ${c::class.simpleName}")
                        }
                    }
                }
                for (child in c.components) walk(child)
            }
        }
        for ((name, model) in PanelFixtures.all()) {
            situation = name
            walk(renderer.render(panelLayout(model)))
        }
        assertTrue(offenders.isEmpty(), "unbounded blocks in a column: $offenders")
    }

    @Test
    fun `a file row is painted as a list row and not as a framed button`() {
        // A stack of framed buttons reads as a stack of actions; the extension
        // paints the same list as paths with no chrome of their own.
        val layout = panelLayout(PanelFixtures.reviewWhole(3))
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _, _ -> false }
        val buttons = PanelRenderer.collectButtons(renderer.render(layout))
        val row = buttons.find { it.text == "file2.kt" }
        assertTrue(row != null, "file row present")
        assertFalse(row!!.isContentAreaFilled, "a row takes no button fill")
        assertFalse(row.isBorderPainted, "a row takes no button frame")
        assertEquals(SwingConstants.LEFT, row.horizontalAlignment)
        assertEquals("file2.kt", row.toolTipText, "the full path stays one hover away")
        // The whole-range Diff above the list is still a button, and it is not
        // one of the rows.
        val diff = buttons.find { it.text == "Diff" }
        assertTrue(diff != null, "Diff button present")
        assertTrue(diff!!.isContentAreaFilled, "the verb above the list keeps its fill")
    }

    @Test
    fun `the last opened row says so`() {
        val layout = panelLayout(PanelFixtures.reviewWhole(3))
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _, _ -> false }
        val buttons = PanelRenderer.collectButtons(renderer.render(layout))
        val opened = buttons.find { it.text == "file1.kt" }
        assertTrue(opened != null, "first file is the last opened one in the fixture")
        assertEquals("Last opened: file1.kt", opened!!.toolTipText)
    }

    @Test
    fun `file rows are single click buttons`() {
        val layout = panelLayout(PanelFixtures.reviewWhole(3))
        val renderer = PanelRenderer(PreviewPanelChrome()) { id, index, _ ->
            assertEquals(ControlId.OPEN_CHANGE, id)
            assertTrue(index != null)
            false
        }
        val buttons = PanelRenderer.collectButtons(renderer.render(layout))
        val fileBtn = buttons.find { it.text == "file1.kt" }
        assertTrue(fileBtn != null)
        fileBtn!!.doClick()
    }

    @Test
    fun `a draft row that does not fit on one line asks for the height of two`() {
        // FlowLayout lays the row out over as many lines as it needs but asks
        // for the height of one, so at sidebar width everything past the first
        // line is clipped away — not moved: Discard never gets drawn at all.
        val row = JPanel(WrapLayout(4, 2))
        repeat(4) { row.add(JButton("Validate and start")) }
        val oneLine = row.getComponent(0).preferredSize.height

        val host = JPanel(BorderLayout())
        host.add(row, BorderLayout.CENTER)
        host.setSize(320, 400)
        host.doLayout()

        assertTrue(
            row.preferredSize.height > oneLine * 2,
            "four wide controls at 320px need more than two rows of height",
        )
    }

    @Test
    fun `an icon control without a platform icon falls back to a glyph, not to its name`() {
        // El nombre accesible es una oracion entera: si cae ahi, el control se
        // vuelve el mas ancho de la fila, que es lo contrario de un icono.
        val layout = panelLayout(PanelFixtures.noReviewDrafts())
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _, _ -> false }
        val buttons = PanelRenderer.collectButtons(renderer.render(layout))
        val open = buttons.find { it.toolTipText == "Open the reading order for editing" }
        assertTrue(open != null, "the draft row draws an openDraft control")
        assertEquals(PreviewPanelChrome().glyphFile(), open!!.text)
    }
}
