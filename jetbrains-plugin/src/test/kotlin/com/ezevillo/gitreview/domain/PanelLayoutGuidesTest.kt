package com.ezevillo.gitreview.domain

import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The authoring-guide rows of the empty state.
 *
 * What these pin down is the rule the block is built on: both rows are always
 * drawn and the state changes the enabled, never the presence — except Discard,
 * which the shared row does not have at all, because removing a tracked file is
 * `git rm` plus a commit and not this button's decision.
 */
class PanelLayoutGuidesTest {
    private fun guideRows(model: PanelModel): List<GuideRow> =
        panelLayout(model)
            .blocks
            .filterIsInstance<Block.ToolsSection>()
            .flatMap { it.blocks }
            .filterIsInstance<Block.GuideRows>()
            .flatMap { it.rows }

    private fun control(row: GuideRow, id: ControlId): Control? = row.controls.find { it.id == id }

    @Test
    fun `the guide rows live in the Walkthrough section, in the CLI's order`() {
        val layout = panelLayout(PanelFixtures.noReviewGuides())
        val walkthrough = layout.blocks
            .filterIsInstance<Block.ToolsSection>()
            .first { it.title == "Walkthrough" }
        val rows = walkthrough.blocks.filterIsInstance<Block.GuideRows>().flatMap { it.rows }
        assertEquals(listOf("Repository guide", "Your guide"), rows.map { it.name })
    }

    @Test
    fun `a guide in force can be opened but not created`() {
        val team = guideRows(PanelFixtures.noReviewGuides())[0]
        assertEquals("in force", team.badge)
        assertTrue(control(team, ControlId.OPEN_GUIDE)!!.enabled)
        assertFalse(control(team, ControlId.CREATE_GUIDE)!!.enabled)
    }

    @Test
    fun `an absent guide can be created but not opened`() {
        val own = guideRows(PanelFixtures.noReviewGuides())[1]
        assertEquals("absent", own.badge)
        assertFalse(control(own, ControlId.OPEN_GUIDE)!!.enabled)
        assertTrue(control(own, ControlId.CREATE_GUIDE)!!.enabled)
        // Nothing to discard, but the control is still drawn: off says why in its
        // tooltip, and a row that changes shape with its state stops lining up.
        assertFalse(control(own, ControlId.DISCARD_GUIDE)!!.enabled)
    }

    @Test
    fun `an empty guide is opened and discarded, not created`() {
        // Empty is not absent: the file is there, so the offer is to fill it.
        val own = guideRows(PanelFixtures.noReviewGuideEmpty())[1]
        assertEquals("empty", own.badge)
        assertTrue(control(own, ControlId.OPEN_GUIDE)!!.enabled)
        assertFalse(control(own, ControlId.CREATE_GUIDE)!!.enabled)
        assertTrue(control(own, ControlId.DISCARD_GUIDE)!!.enabled)
    }

    @Test
    fun `only the reviewer's row offers Discard`() {
        // The shared guide is tracked: removing it is git rm plus a commit, a
        // decision about what goes into the PR. The CLI refuses --delete --team
        // from its side.
        val rows = guideRows(PanelFixtures.noReviewGuides())
        assertTrue(rows[0].controls.none { it.id == ControlId.DISCARD_GUIDE })
        assertTrue(rows[1].controls.any { it.id == ControlId.DISCARD_GUIDE })
    }

    @Test
    fun `both rows carry the same controls whatever their state`() {
        val a = guideRows(PanelFixtures.noReviewGuides())
        val b = guideRows(PanelFixtures.noReviewGuideEmpty())
        assertEquals(a[0].controls.map { it.id }, b[0].controls.map { it.id })
        assertEquals(a[1].controls.map { it.id }, b[1].controls.map { it.id })
    }

    @Test
    fun `every guide control carries its row index`() {
        // The index is the only thing the panel sends back; the host re-resolves
        // the row against its own state before invoking anything.
        guideRows(PanelFixtures.noReviewGuides()).forEachIndexed { index, row ->
            for (c in row.controls) {
                assertEquals(index, c.index, "${c.id.wire} lost its index")
            }
        }
    }

    @Test
    fun `Open points at the path the CLI reported`() {
        val team = guideRows(PanelFixtures.noReviewGuides())[0]
        assertEquals("/repo/.review/walkthrough-guide.md", control(team, ControlId.OPEN_GUIDE)!!.tooltip)
    }

    @Test
    fun `a busy panel disables what mutates and leaves Open alone`() {
        // Opening reads; creating and discarding invoke the CLI.
        val model = PanelFixtures.noReviewGuideEmpty().copy(busy = true)
        val own = panelLayout(model)
            .blocks
            .filterIsInstance<Block.ToolsSection>()
            .flatMap { it.blocks }
            .filterIsInstance<Block.GuideRows>()
            .flatMap { it.rows }[1]
        assertTrue(control(own, ControlId.OPEN_GUIDE)!!.enabled)
        assertFalse(control(own, ControlId.DISCARD_GUIDE)!!.enabled)
    }

    @Test
    fun `no guide records means no block at all`() {
        // The degradation against a CLI that does not know the record: the rows
        // disappear and Init/Build stay where they are.
        val layout = panelLayout(PanelFixtures.noReviewReady())
        assertTrue(layout.blocks.filterIsInstance<Block.ToolsSection>().any { it.title == "Walkthrough" })
        assertTrue(guideRows(PanelFixtures.noReviewReady()).isEmpty())
    }
}
