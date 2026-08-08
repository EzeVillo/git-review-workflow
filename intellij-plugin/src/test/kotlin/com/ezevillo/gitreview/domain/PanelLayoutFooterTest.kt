package com.ezevillo.gitreview.domain

import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PanelLayoutFooterTest {
    @Test
    fun `no-review ready ends with three tools sections`() {
        val layout = panelLayout(PanelFixtures.noReviewReady())
        val sections = layout.blocks.filterIsInstance<Block.ToolsSection>()
        assertEquals(listOf("Other actions", "Settings", "Support"), sections.map { it.title })
        val other = sections[0]
        assertTrue(other.blocks.flatMap { controlsOf(it) }.any { it.id == ControlId.COMPARE_REVIEW })
        assertTrue(other.blocks.flatMap { controlsOf(it) }.any { it.id == ControlId.WALKTHROUGH_INIT })
        val support = sections[2]
        assertTrue(support.blocks.flatMap { controlsOf(it) }.any { it.id == ControlId.OPEN_SUPPORT && it.label == "Star on GitHub" })
    }

    @Test
    fun `review has no tools sections`() {
        val layout = panelLayout(PanelFixtures.reviewWalk())
        assertTrue(layout.blocks.none { it is Block.ToolsSection })
    }

    private fun controlsOf(b: Block): List<Control> = when (b) {
        is Block.Row -> b.controls
        else -> emptyList()
    }
}
