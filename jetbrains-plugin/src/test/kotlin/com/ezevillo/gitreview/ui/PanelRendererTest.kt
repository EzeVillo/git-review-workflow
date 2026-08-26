package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.ControlId
import com.ezevillo.gitreview.domain.Emphasis
import com.ezevillo.gitreview.domain.panelLayout
import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.awt.GridLayout
import javax.swing.JLabel
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
        // The first tools section of the empty state.
        val toggle1 = PanelRenderer.collectButtons(root1).single { it.text?.endsWith(" Walkthrough") == true }
        assertTrue(toggle1.text.startsWith("▶"), "collapsed to begin with: ${toggle1.text}")
        toggle1.doClick()
        val layout2 = panelLayout(PanelFixtures.noReviewReady())
        val root2 = renderer.render(layout2)
        val toggle2 = PanelRenderer.collectButtons(root2).single { it.text?.endsWith(" Walkthrough") == true }
        assertTrue(toggle2.text.startsWith("▼"), "section should stay open: ${toggle2.text}")
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
    fun `the draft actions are a grid of even columns, not a row that wraps`() {
        // A wrapping row lays the controls out over as many lines as it needs
        // and breaks in a different place on every row of the block, so none
        // lines up with the one beside it. Even cells always do.
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _, _ -> false }
        val root = renderer.render(panelLayout(PanelFixtures.noReviewDrafts()))
        val copy = PanelRenderer.collectButtons(root)
            .first { it.text == "Copy for agent" }

        val actions = copy.parent as JPanel
        val grid = actions.layout as? GridLayout
        assertTrue(grid != null, "the draft actions are laid out as a grid")
        assertEquals(1, grid!!.rows, "one line: the two glyphs left the pane")
        assertEquals(2, grid.columns, "two columns")
        assertEquals(2, actions.componentCount, "one cell per labelled control, no struts between them")
    }

    @Test
    fun `the two controls of the row are glyphs in the header, beside the progress`() {
        // They move nothing along and their subject is the file the progress
        // pair just named, so they ride that pair instead of the button pane.
        // With no visible label the accessible name IS the name of the control.
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _, _ -> false }
        val root = renderer.render(panelLayout(PanelFixtures.noReviewDrafts()))
        val buttons = PanelRenderer.collectButtons(root)
        val open = buttons.first { it.toolTipText == "Open the reading order for editing" }
        val discard = buttons.first { it.toolTipText == "git review forget --draft (with confirmation)" }

        assertEquals("Open the reading order", open.accessibleContext.accessibleName)
        assertEquals("Discard the reading order", discard.accessibleContext.accessibleName)
        // PreviewPanelChrome has no platform icons, so both fall back to their
        // glyph -- never to the sentence, which would make them the widest
        // controls of the row.
        assertEquals(PreviewPanelChrome().glyphFile(), open.text)
        assertEquals(PreviewPanelChrome().glyphTrash(), discard.text)

        // Same parent, and it is the header: the pane below holds the labelled
        // pair and nothing else.
        assertEquals(open.parent, discard.parent, "los dos van juntos")
        val copy = buttons.first { it.text == "Copy for agent" }
        assertNotEquals(copy.parent, open.parent, "y no en la botonera")
        val header = open.parent as JPanel
        assertTrue(
            header.components.any { it is JLabel && it.text == "3/9" },
            "estan en la cabecera, al lado del par que nombra su sujeto",
        )
    }

    @Test
    fun `every icon control of a row draws its own glyph`() {
        // The bug this pins: only the draft row's two ids were mapped, so a guide
        // row's Open and Discard and the walkthrough row's Open fell through --
        // to the accessible name here (a sentence-wide button in the header) and
        // to Next's arrow in the other client. The canonical declares file and
        // trash for all three pairs.
        val chrome = PreviewPanelChrome()
        val renderer = PanelRenderer(chrome) { _, _, _ -> false }
        val root = renderer.render(panelLayout(PanelFixtures.noReviewWalkthroughStale()))
        val buttons = PanelRenderer.collectButtons(root)
        for (name in listOf("Open the guide", "Open the walkthrough")) {
            val b = buttons.first { it.accessibleContext.accessibleName == name }
            assertEquals(chrome.glyphFile(), b.text, name)
        }
        val discard = buttons.first { it.accessibleContext.accessibleName == "Discard the guide" }
        assertEquals(chrome.glyphTrash(), discard.text)
    }

    @Test
    fun `no icon control anywhere falls back to its accessible name`() {
        // The same drift as the test above, asked over EVERY fixture instead of
        // over a hand-written list of names -- which is what let it happen a
        // second time: the fixes rows arrived with their own trash control, no
        // name here mentioned it, and the row drew a sentence-wide button that
        // reads as disabled next to the glyphs of the two sections above it.
        // An icon control renders one of the panel's glyphs; the accessible name
        // is the floor of the tooltip, never the face of the button.
        val chrome = PreviewPanelChrome()
        val glyphs = setOf(
            chrome.glyphPrev(),
            chrome.glyphNext(),
            chrome.glyphCopy(),
            chrome.glyphFile(),
            chrome.glyphTrash(),
        )
        val renderer = PanelRenderer(chrome) { _, _, _ -> false }
        var seen = 0
        for ((name, model) in PanelFixtures.all()) {
            val layout = panelLayout(model)
            val iconNames = layout.collectControls()
                .filter { it.emphasis == Emphasis.ICON }
                .map { it.accessibleName }
                .toSet()
            if (iconNames.isEmpty()) continue
            for (b in PanelRenderer.collectButtons(renderer.render(layout))) {
                if (b.accessibleContext.accessibleName !in iconNames) continue
                seen++
                assertTrue(
                    b.text in glyphs,
                    "$name: el control de icono '${b.accessibleContext.accessibleName}' " +
                        "dibuja \"${b.text}\" en vez de un glifo del panel",
                )
            }
        }
        // Sin esto el barrido pasa vacio el dia que collectControls deje de ver
        // un bloque de filas, que es la otra mitad del mismo bug.
        assertTrue(seen >= 12, "el barrido tiene que llegar a los iconos: seen=$seen")
    }

    @Test
    fun `the badge closes the header line of every row`() {
        // So that the states of all three sections land in the same column at the
        // right edge. The glyphs go before it, still glued to what names their
        // subject.
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _, _ -> false }
        val root = renderer.render(panelLayout(PanelFixtures.noReviewWalkthroughStale()))
        val open = PanelRenderer.collectButtons(root)
            .first { it.accessibleContext.accessibleName == "Open the walkthrough" }
        val header = open.parent as JPanel
        val badge = header.components.filterIsInstance<JLabel>().last()
        assertEquals("may be out of date", badge.text)
        assertTrue(
            header.components.indexOf(badge) > header.components.indexOf(open),
            "el badge va despues del icono",
        )
    }

    /**
     * Lays a tree out without ever realizing a peer: `validate()` is a no-op on a
     * component that was never displayed, and a JFrame is not an option in the
     * headless runner CI uses for this suite.
     */
    private fun layoutOffscreen(root: java.awt.Container, width: Int, height: Int) {
        root.setSize(width, height)
        fun rec(c: java.awt.Container) {
            c.doLayout()
            for (child in c.components) if (child is java.awt.Container) rec(child)
        }
        repeat(3) { rec(root) }
    }

    @Test
    fun `the footer is capped and scrolls instead of taking over the panel`() {
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _, _ -> false }
        val root = renderer.render(panelLayout(PanelFixtures.noReviewFixes()))
        PanelRenderer.collectButtons(root)
            .filter { it.text?.startsWith("▶") == true }
            .forEach { it.doClick() }
        val height = 460
        layoutOffscreen(root, 320, height)

        val scrolls = collectScrollPanes(root)
        val footer = scrolls.find { sp ->
            PanelRenderer.collectButtons(sp.viewport.view as javax.swing.JComponent)
                .any { it.text?.endsWith(" Support") == true }
        }
        assertTrue(footer != null, "a scroll pane of its own holds the footer sections")
        assertTrue(
            footer!!.height <= height * 0.55 + 1,
            "the footer took ${footer.height} of $height",
        )
        assertTrue(
            (footer.viewport.view as javax.swing.JComponent).preferredSize.height > footer.viewport.extentSize.height,
            "the capped footer does not scroll, so its tail is unreachable",
        )
        val body = scrolls.first { it !== footer }
        assertTrue(body.height > 0, "the body keeps room above the footer")
    }

    private fun collectScrollPanes(c: java.awt.Container): List<javax.swing.JScrollPane> {
        val found = mutableListOf<javax.swing.JScrollPane>()
        if (c is javax.swing.JScrollPane) found.add(c)
        for (child in c.components) if (child is java.awt.Container) found.addAll(collectScrollPanes(child))
        return found
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
