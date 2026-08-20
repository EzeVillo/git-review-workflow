package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.ControlId
import com.ezevillo.gitreview.domain.panelLayout
import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.awt.GridLayout
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
    fun `the draft actions are a grid of two even columns, not a row that wraps`() {
        // A wrapping row lays the four controls out over as many lines as it
        // needs and breaks in a different place on every row of the block, so
        // none lines up with the one beside it. Four even cells always do.
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _, _ -> false }
        val root = renderer.render(panelLayout(PanelFixtures.noReviewDrafts()))
        val discard = PanelRenderer.collectButtons(root)
            .first { it.toolTipText == "git review forget --draft (with confirmation)" }

        val actions = discard.parent as JPanel
        val grid = actions.layout as? GridLayout
        assertTrue(grid != null, "the draft actions are laid out as a grid")
        assertEquals(2, grid!!.rows, "two rows")
        assertEquals(2, grid.columns, "two columns")
        assertEquals(4, actions.componentCount, "one cell per control, no struts between them")
    }

    @Test
    fun `open draft carries a label of its own and a name that says which one`() {
        // In a cell of even width the label no longer forces the wrap the icon
        // was there to avoid, and a glyph among three labels does not say what
        // it opens. "Open" on its own repeats once per row, so what is read out
        // is the sentence.
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _, _ -> false }
        val root = renderer.render(panelLayout(PanelFixtures.noReviewDrafts()))
        val open = PanelRenderer.collectButtons(root)
            .first { it.toolTipText == "Open the reading order for editing" }

        assertEquals("Open", open.text, "etiqueta visible, no un glifo")
        assertEquals("Open the reading order", open.accessibleContext.accessibleName)
        assertTrue(open.isBorderPainted, "no es el destructivo: conserva su caja")
    }

    @Test
    fun `discard is the one control of the row without a fill`() {
        // The one irreversible control of the row: with no fill it drops a step
        // without leaving its cell, and a click in passing does not land on
        // something shaped like a button.
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _, _ -> false }
        val root = renderer.render(panelLayout(PanelFixtures.noReviewDrafts()))
        val discard = PanelRenderer.collectButtons(root)
            .first { it.toolTipText == "git review forget --draft (with confirmation)" }

        assertFalse(discard.isContentAreaFilled, "sin relleno propio")
        assertFalse(discard.isBorderPainted, "ni borde")
        assertEquals(PreviewPanelChrome().mutedForeground(), discard.foreground, "en el color de la meta")
        assertEquals("Discard", discard.text)
    }

    @Test
    fun `an icon control without a platform icon falls back to a glyph, not to its name`() {
        // El nombre accesible es una oracion entera: si cae ahi, el control se
        // vuelve el mas ancho de la fila, que es lo contrario de un icono.
        val layout = panelLayout(PanelFixtures.reviewWalk(atFirst = true))
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _, _ -> false }
        val buttons = PanelRenderer.collectButtons(renderer.render(layout))
        val prev = buttons.find { it.accessibleContext.accessibleName == "Previous entry" }
        assertTrue(prev != null, "the walk bar draws a prev control")
        assertEquals(PreviewPanelChrome().glyphPrev(), prev!!.text)
    }
}
