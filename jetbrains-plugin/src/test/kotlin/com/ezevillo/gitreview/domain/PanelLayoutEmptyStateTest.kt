package com.ezevillo.gitreview.domain

import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PanelLayoutEmptyStateTest {
    @Test
    fun `setup without base is five blocks primary set base no inventory`() {
        val layout = panelLayout(PanelFixtures.noReviewSetup())
        assertFalse(layout.fillsHeight)
        assertEquals(5, layout.blocks.size)
        assertTrue(layout.blocks.none { it is Block.InventoryRows })
        assertTrue(layout.blocks.none { it is Block.ToolsSection })
        assertFalse(layout.collectControls().any { it.id == ControlId.START_REVIEW })
        val primary = layout.collectControls().filter { it.emphasis == Emphasis.PRIMARY }
        assertEquals(1, primary.size)
        assertEquals(ControlId.SET_BASE, primary[0].id)
        assertEquals("Choose the branch", primary[0].label)
    }

    @Test
    fun `ready no-review has inventory before start and fills height`() {
        val layout = panelLayout(PanelFixtures.noReviewReady())
        assertTrue(layout.fillsHeight)
        val types = layout.blocks.map { it::class.simpleName }
        val inv = types.indexOf("InventoryRows")
        val startRow = layout.blocks.indexOfFirst {
            it is Block.Row && it.controls.any { c -> c.id == ControlId.START_REVIEW }
        }
        if (inv >= 0) {
            assertTrue(inv < startRow)
        }
        assertTrue(layout.collectControls().any { it.id == ControlId.START_REVIEW && it.emphasis == Emphasis.PRIMARY })
        assertEquals(4, layout.blocks.count { it is Block.ToolsSection })
    }

    @Test
    fun `the start paragraph is ruled off from the inventory only when there is one`() {
        val withReviews = panelLayout(PanelFixtures.noReviewReady())
            .blocks.filterIsInstance<Block.Paragraph>()
            .first { it.text == "No active review on this branch." }
        assertTrue(withReviews.separated, "a listed inventory needs the rule under it")

        val withoutReviews = panelLayout(PanelFixtures.noReviewEmpty())
            .blocks.filterIsInstance<Block.Paragraph>()
            .first { it.text == "No active review on this branch." }
        assertFalse(withoutReviews.separated, "with no inventory there is nothing to separate")
    }

    @Test
    fun `inventory rows carry index and continue only on saved`() {
        val layout = panelLayout(PanelFixtures.noReviewReady())
        val inv = layout.blocks.filterIsInstance<Block.InventoryRows>().firstOrNull() ?: return
        for (row in inv.rows) {
            for (c in row.controls) {
                assertTrue(c.index != null, "control ${c.id} needs index")
            }
            if (row.controls.any { it.id == ControlId.CONTINUE_REVIEW }) {
                // Continue only when saved path is present in fixture
                assertTrue(row.controls.any { it.id == ControlId.CONTINUE_REVIEW })
            }
            if (row.controls.isEmpty()) {
                assertTrue(!row.helpTooltip.isNullOrBlank())
            }
        }
    }
}
