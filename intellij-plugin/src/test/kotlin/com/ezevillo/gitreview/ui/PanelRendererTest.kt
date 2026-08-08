package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.ControlId
import com.ezevillo.gitreview.domain.panelLayout
import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import javax.swing.JButton

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
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _ -> false }
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
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _ -> false }
        val buttons = PanelRenderer.collectButtons(renderer.render(layout))
        val names = buttons.mapNotNull { it.accessibleContext?.accessibleName ?: it.toolTipText }
        assertTrue(names.any { it == "Previous entry" })
        assertTrue(names.any { it == "Next entry" })
    }

    @Test
    fun `section open state survives re-render`() {
        val renderer = PanelRenderer(PreviewPanelChrome()) { _, _ -> false }
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
    fun `file rows are single click buttons`() {
        val layout = panelLayout(PanelFixtures.reviewWhole(3))
        val renderer = PanelRenderer(PreviewPanelChrome()) { id, index ->
            assertEquals(ControlId.OPEN_CHANGE, id)
            assertTrue(index != null)
            false
        }
        val buttons = PanelRenderer.collectButtons(renderer.render(layout))
        val fileBtn = buttons.find { it.text == "file1.kt" }
        assertTrue(fileBtn != null)
        fileBtn!!.doClick()
    }
}
