package com.ezevillo.gitreview.domain

import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PanelLayoutFooterTest {
    @Test
    fun `no-review ready ends with four tools sections`() {
        val layout = panelLayout(PanelFixtures.noReviewReady())
        val sections = layout.blocks.filterIsInstance<Block.ToolsSection>()
        assertEquals(
            listOf("Other actions", "Walkthrough", "Settings", "Support"),
            sections.map { it.title },
        )
        // Compare stayed where it was; init and build moved to the section named
        // after the noun they share with the two authoring guides.
        val other = sections[0]
        assertTrue(other.blocks.flatMap { controlsOf(it) }.any { it.id == ControlId.COMPARE_REVIEW })
        assertTrue(other.blocks.flatMap { controlsOf(it) }.none { it.id == ControlId.WALKTHROUGH_INIT })
        val walkthrough = sections[1]
        assertTrue(walkthrough.blocks.flatMap { controlsOf(it) }.any { it.id == ControlId.WALKTHROUGH_INIT })
        assertTrue(walkthrough.blocks.flatMap { controlsOf(it) }.any { it.id == ControlId.WALKTHROUGH_BUILD })
        val support = sections[3]
        val supportControls = support.blocks.flatMap { controlsOf(it) }
        assertTrue(supportControls.any { it.id == ControlId.OPEN_SUPPORT && it.label == "Star on GitHub" && it.supportLinkId == SupportLinks.STAR })
        assertTrue(supportControls.any { it.id == ControlId.OPEN_SUPPORT && it.label == "Report a bug" && it.supportLinkId == SupportLinks.BUG })
        assertEquals(2, supportControls.count { it.id == ControlId.OPEN_SUPPORT })
    }

    @Test
    fun `review has no tools sections when there are no guides`() {
        val layout = panelLayout(PanelFixtures.reviewWalk())
        assertTrue(layout.blocks.none { it is Block.ToolsSection })
    }

    @Test
    fun `the guides are the only tools section a review has`() {
        // Init and build do not belong here -- they are the author's, standing on
        // their own PR -- and neither does the rest of the footer.
        val sections = panelLayout(PanelFixtures.reviewWalkGuides())
            .blocks.filterIsInstance<Block.ToolsSection>()
        assertEquals(listOf("Walkthrough"), sections.map { it.title })
        assertTrue(sections[0].blocks.all { it is Block.GuideRows })
    }

    private fun controlsOf(b: Block): List<Control> = when (b) {
        is Block.Row -> b.controls
        else -> emptyList()
    }
}
