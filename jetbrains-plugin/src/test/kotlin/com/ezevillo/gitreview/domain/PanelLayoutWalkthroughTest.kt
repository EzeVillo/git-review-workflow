package com.ezevillo.gitreview.domain

import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The author's own walkthrough row in the empty state.
 *
 * What these pin down is the reason the row exists: a walkthrough is written
 * once, when the PR is finished, and then the PR keeps moving. The row says so
 * without anybody remembering to ask -- and says it cautiously, because what the
 * CLI compares on every refresh is cheap and approximate.
 */
class PanelLayoutWalkthroughTest {
    private fun row(model: PanelModel): GuideRow? =
        panelLayout(model)
            .blocks
            .filterIsInstance<Block.ToolsSection>()
            .flatMap { it.blocks }
            .filterIsInstance<Block.WalkthroughRow>()
            .map { it.row }
            .firstOrNull()

    private fun control(row: GuideRow, id: ControlId): Control? = row.controls.find { it.id == id }

    private fun initLabel(model: PanelModel): String? =
        panelLayout(model)
            .blocks
            .filterIsInstance<Block.ToolsSection>()
            .flatMap { it.blocks }
            .filterIsInstance<Block.Row>()
            .flatMap { it.controls }
            .find { it.id == ControlId.WALKTHROUGH_INIT }
            ?.label

    @Test
    fun `the row lives in the Walkthrough section, above the guides`() {
        val section = panelLayout(PanelFixtures.noReviewWalkthroughStale())
            .blocks
            .filterIsInstance<Block.ToolsSection>()
            .first { it.title == "Walkthrough" }
        val kinds = section.blocks.map { it::class.simpleName }
        assertEquals(listOf("Row", "WalkthroughRow", "GuideRows"), kinds)
    }

    @Test
    fun `a stale walkthrough suggests looking, it does not pass a verdict`() {
        // The exact answer is build's; this badge is the cheap half.
        val r = row(PanelFixtures.noReviewWalkthroughStale())!!
        assertEquals("may be out of date", r.badge)
    }

    @Test
    fun `the row carries how much of the reading order is written`() {
        val r = row(PanelFixtures.noReviewWalkthroughStale())!!
        assertTrue(r.name.contains("4/6"), "expected the progress pair in ${r.name}")
    }

    @Test
    fun `an absent walkthrough leaves both row controls off`() {
        val r = row(PanelFixtures.noReviewWalkthroughAbsent())!!
        assertEquals("none", r.badge)
        assertFalse(control(r, ControlId.OPEN_WALKTHROUGH)!!.enabled)
        assertFalse(control(r, ControlId.COPY_WALKTHROUGH_PROMPT)!!.enabled)
        // And no progress pair: 0/0 is "nothing here", not "finished".
        assertFalse(r.name.contains("/"), "unexpected progress pair in ${r.name}")
    }

    @Test
    fun `an existing walkthrough can be opened and handed to an agent`() {
        val r = row(PanelFixtures.noReviewWalkthroughStale())!!
        val open = control(r, ControlId.OPEN_WALKTHROUGH)!!
        assertTrue(open.enabled)
        // Open points at the path the CLI reported, never one rebuilt here.
        assertEquals("/repo/.review/walkthrough.md", open.tooltip)
        assertTrue(control(r, ControlId.COPY_WALKTHROUGH_PROMPT)!!.enabled)
    }

    @Test
    fun `the init button says Update over a walkthrough that exists`() {
        // The same verb creates and updates; "Init" over a file full of prose
        // promised what that verb precisely no longer does.
        assertEquals("Walkthrough: Update", initLabel(PanelFixtures.noReviewWalkthroughStale()))
        assertEquals("Walkthrough: Init", initLabel(PanelFixtures.noReviewWalkthroughAbsent()))
    }

    @Test
    fun `with no record from the CLI the row is not drawn`() {
        // The degradation against an older CLI: no row, no block, nothing breaks.
        assertNull(row(PanelFixtures.noReviewGuides()))
        assertEquals("Walkthrough: Init", initLabel(PanelFixtures.noReviewGuides()))
    }

    @Test
    fun `the row controls are not product actions`() {
        // Their subject is the row: without it they have no subject at all, so
        // they stay out of the action matrix and out of the Tools menu.
        val r = row(PanelFixtures.noReviewWalkthroughStale())!!
        assertNotNull(control(r, ControlId.OPEN_WALKTHROUGH)!!.index)
        assertNotNull(control(r, ControlId.COPY_WALKTHROUGH_PROMPT)!!.index)
    }
}
