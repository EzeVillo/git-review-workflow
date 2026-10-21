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
            listOf("Walkthrough", "Compare", "Settings", "Support"),
            sections.map { it.title },
        )
        // Compare names what it does and goes below the sections that are
        // about the review you are about to do; init and build live in the
        // section named after the noun they share with the two authoring
        // guides -- and inside it, in the row whose file they act on.
        val walkthrough = sections[0]
        assertTrue(walkthrough.blocks.flatMap { controlsOf(it) }.any { it.id == ControlId.WALKTHROUGH_INIT })
        assertTrue(walkthrough.blocks.flatMap { controlsOf(it) }.any { it.id == ControlId.WALKTHROUGH_BUILD })
        assertTrue(walkthrough.blocks.flatMap { controlsOf(it) }.none { it.id == ControlId.COMPARE_REVIEW })
        val compare = sections[1]
        assertTrue(compare.blocks.flatMap { controlsOf(it) }.any { it.id == ControlId.COMPARE_REVIEW })
        assertTrue(compare.blocks.flatMap { controlsOf(it) }.none { it.id == ControlId.WALKTHROUGH_INIT })
        val support = sections[3]
        val supportControls = support.blocks.flatMap { controlsOf(it) }
        assertEquals(listOf(1, 1, 1, 1), support.blocks.map { controlsOf(it).size })
        assertEquals(listOf("Star on GitHub", "Report a bug", "Sponsor", "Contact"), supportControls.map { it.label })
        assertEquals(listOf(SupportLinks.STAR, SupportLinks.BUG, SupportLinks.SPONSOR, SupportLinks.CONTACT),
            supportControls.map { it.supportLinkId })
        assertTrue(supportControls.all { it.id == ControlId.OPEN_SUPPORT })
        assertEquals("https://github.com/sponsors/EzeVillo", SupportLinks.urlFor(SupportLinks.SPONSOR))
        assertEquals("mailto:ezevillodev@gmail.com", SupportLinks.urlFor(SupportLinks.CONTACT))
        assertEquals(null, SupportLinks.urlFor("unknown"))
    }

    /**
     * The reading orders you finished with are still about the review you are
     * about to do; Compare mounts two revisions that have nothing to do with
     * it, so it sits below them.
     */
    @Test
    fun `compare sits below the reading orders you finished with`() {
        val sections = panelLayout(PanelFixtures.noReviewSpentDraft())
            .blocks.filterIsInstance<Block.ToolsSection>()
        assertEquals(
            listOf("Walkthrough", "Reading orders you finished with", "Compare", "Settings", "Support"),
            sections.map { it.title },
        )
    }

    @Test
    fun `a review has no tools sections at all`() {
        // Everything hanging off `walkthrough` -- the author's two verbs and the two
        // authoring guides -- belongs to whoever is standing on THEIR OWN PR, and in
        // here you are standing on somebody else's.
        assertTrue(panelLayout(PanelFixtures.reviewWalk()).blocks.none { it is Block.ToolsSection })
        assertTrue(panelLayout(PanelFixtures.reviewStep()).blocks.none { it is Block.ToolsSection })
        assertTrue(panelLayout(PanelFixtures.reviewWhole()).blocks.none { it is Block.ToolsSection })
    }

    // The walkthrough row counts: the two verbs are ITS buttons, not a loose row
    // above it -- see the section's note in the canonical.
    private fun controlsOf(b: Block): List<Control> = when (b) {
        is Block.Row -> b.controls
        is Block.WalkthroughRow -> b.row.controls
        is Block.GuideRows -> b.rows.flatMap { it.controls }
        else -> emptyList()
    }
}
