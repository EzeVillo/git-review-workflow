package com.ezevillo.gitreview.domain

import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
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

    // Init and build are the ROW's buttons: their subject is the file the row
    // names, exactly as Create is each guide's.
    private fun initLabel(model: PanelModel): String? =
        row(model)?.controls?.find { it.id == ControlId.WALKTHROUGH_INIT }?.label

    @Test
    fun `the row lives in the Walkthrough section, above the guides`() {
        val section = panelLayout(PanelFixtures.noReviewWalkthroughStale())
            .blocks
            .filterIsInstance<Block.ToolsSection>()
            .first { it.title == "Walkthrough" }
        val kinds = section.blocks.map { it::class.simpleName }
        // Nothing loose above the row: the section is three rows and no more.
        assertEquals(listOf("WalkthroughRow", "GuideRows"), kinds)
    }

    @Test
    fun `the row is named after the branch it annotates`() {
        // The section is already called Walkthrough; saying it again in the row
        // added no fact, and the two prefixed buttons said it a third time.
        val r = row(PanelFixtures.noReviewWalkthroughStale())!!
        assertTrue(r.name.startsWith("feature/checkout"), "expected the branch in ${r.name}")
    }

    @Test
    fun `the two verbs are buttons of the row`() {
        val r = row(PanelFixtures.noReviewWalkthroughStale())!!
        assertEquals(
            listOf("Update", "Build", "Copy for agent"),
            r.controls.filter { it.emphasis != Emphasis.ICON }.map { it.label },
        )
        // And nowhere else in the section: a loose row above would say the word
        // a third time in four centimetres.
        val loose = panelLayout(PanelFixtures.noReviewWalkthroughStale())
            .blocks
            .filterIsInstance<Block.ToolsSection>()
            .flatMap { it.blocks }
            .filterIsInstance<Block.Row>()
            .flatMap { it.controls }
            .map { it.id }
        assertFalse(ControlId.WALKTHROUGH_INIT in loose)
        assertFalse(ControlId.WALKTHROUGH_BUILD in loose)
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
        // And no progress pair: 0/0 is "nothing here", not "finished". Asked of
        // the digits, not of the slash -- the row is named after a branch now,
        // and feature/checkout has one of those.
        assertFalse(
            r.name.contains(Regex("""\d+/\d+""")),
            "unexpected progress pair in ${r.name}",
        )
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
        assertEquals("Update", initLabel(PanelFixtures.noReviewWalkthroughStale()))
        assertEquals("Init", initLabel(PanelFixtures.noReviewWalkthroughAbsent()))
    }

    @Test
    fun `with no record from the CLI the row is still drawn, in unknown`() {
        // Init and build hang off this row, so a row that disappears takes the
        // two verbs with it. `unknown` is what the CLI itself calls "cannot be
        // told", so nothing is invented: no badge, no path, both file controls
        // off, and the two verbs still there.
        val r = row(PanelFixtures.noReviewNoWalkthroughRecord())!!
        assertEquals("Walkthrough", r.name)
        assertEquals("state unknown", r.badge)
        assertFalse(control(r, ControlId.OPEN_WALKTHROUGH)!!.enabled)
        assertFalse(control(r, ControlId.COPY_WALKTHROUGH_PROMPT)!!.enabled)
        assertTrue(control(r, ControlId.WALKTHROUGH_INIT)!!.enabled)
        assertTrue(control(r, ControlId.WALKTHROUGH_BUILD)!!.enabled)
    }

    @Test
    fun `the row controls are not product actions`() {
        // Their subject is the row: without it they have no subject at all, so
        // they stay out of the action matrix and out of the Tools menu.
        val r = row(PanelFixtures.noReviewWalkthroughStale())!!
        assertNotNull(control(r, ControlId.OPEN_WALKTHROUGH)!!.index)
        assertNotNull(control(r, ControlId.COPY_WALKTHROUGH_PROMPT)!!.index)
    }

    @Test
    fun `a walkthrough that came in with a merge is not stale`() {
        // Nothing about it fell behind: it belongs to a range that closed. The two
        // have to stay apart or the panel offers reconciling another PR's prose.
        val r = row(PanelFixtures.noReviewWalkthroughSuperseded())!!
        assertEquals("from a merged PR", r.badge)
    }

    @Test
    fun `the button says start over on a superseded walkthrough`() {
        // The CLI starts over on its own there, so the button says what will
        // happen instead of promising a reconciliation that does not occur.
        assertEquals("Start over", initLabel(PanelFixtures.noReviewWalkthroughSuperseded()))
    }

    @Test
    fun `a superseded walkthrough can still be opened and copied`() {
        // The file is right there; what changed is whose it is.
        val r = row(PanelFixtures.noReviewWalkthroughSuperseded())!!
        assertTrue(control(r, ControlId.OPEN_WALKTHROUGH)!!.enabled)
        assertTrue(control(r, ControlId.COPY_WALKTHROUGH_PROMPT)!!.enabled)
    }
}
