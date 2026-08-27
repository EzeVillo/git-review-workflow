package com.ezevillo.gitreview.domain

import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The "Edits you extracted" section: the branches a finish left behind.
 *
 * What these pin down is the rule the section is built on -- every row the CLI
 * reported is drawn, including the one that cannot be deleted --, that the
 * per-row control never names more than one branch, and that the bulk
 * "Discard all" control runs clean --fixes-only with NO branch, which by
 * clean's own scoping never reaches a live review session.
 */
class PanelLayoutFixesTest {
    private fun section(model: PanelModel): Block.ToolsSection? =
        panelLayout(model)
            .blocks
            .filterIsInstance<Block.ToolsSection>()
            .find { it.title == "Edits you extracted" }

    private fun rows(model: PanelModel): List<GuideRow> =
        section(model)?.blocks?.filterIsInstance<Block.FixesRows>()?.flatMap { it.rows } ?: emptyList()

    @Test
    fun `every branch the CLI reported gets a row, in its order`() {
        val rows = rows(PanelFixtures.noReviewFixes())
        assertEquals(
            listOf(
                "review-fixes/feature/checkout",
                "review-fixes/fix/quoting",
                "review-fixes/perf/index",
                "review-fixes/docs/readme",
            ),
            rows.map { it.name },
        )
    }

    @Test
    fun `the badge says each state and none folds into another`() {
        assertEquals(
            listOf("unmerged", "empty", "merged", "unknown"),
            rows(PanelFixtures.noReviewFixes()).map { it.badge },
        )
    }

    @Test
    fun `the branch you are on is drawn and its control is off`() {
        // Hiding it would leave a branch that exists with no surface naming it,
        // which is what this section came to fix; offering the button would
        // promise something the CLI skips.
        val current = rows(PanelFixtures.noReviewFixes())[1]
        val discard = current.controls.single()
        assertEquals(ControlId.DISCARD_FIXES, discard.id)
        assertFalse(discard.enabled)
        assertEquals("You are on this branch; switch away first", discard.tooltip)
    }

    @Test
    fun `every other row offers the discard, naming what it deletes`() {
        val rows = rows(PanelFixtures.noReviewFixes())
        for (row in listOf(rows[0], rows[2], rows[3])) {
            val discard = row.controls.single()
            assertEquals(ControlId.DISCARD_FIXES, discard.id)
            assertTrue(discard.enabled, "${row.name} should offer the discard")
            assertEquals("Delete this branch of edits", discard.tooltip)
            assertEquals(Emphasis.ICON, discard.emphasis)
        }
    }

    @Test
    fun `each row control is about exactly one branch`() {
        val controls = section(PanelFixtures.noReviewFixes())!!
            .blocks
            .filterIsInstance<Block.FixesRows>()
            .flatMap { it.rows }
            .flatMap { it.controls }
        assertTrue(controls.all { it.id == ControlId.DISCARD_FIXES })
        assertTrue(controls.all { it.index != null }, "every row control is about ONE row")
    }

    @Test
    fun `Discard all sits above the rows, with no row index`() {
        val discardAll = section(PanelFixtures.noReviewFixes())!!
            .blocks
            .filterIsInstance<Block.Row>()
            .flatMap { it.controls }
            .single { it.id == ControlId.DISCARD_ALL_FIXES }
        assertEquals("Discard all", discardAll.label)
        assertTrue(discardAll.enabled)
        assertNull(discardAll.index)
    }

    @Test
    fun `Discard all runs clean --fixes-only with no branch`() {
        // Unlike a bare `clean`, --fixes-only alone only ever enumerates
        // review-fixes/*, so it never reaches a live review/* session.
        val argv = actionToArgv(
            "cleanReview",
            ActionParams.Housekeeping(HousekeepingAction(HousekeepingKind.CLEAN_FIXES_ONE_ALL)),
        )
        assertEquals("clean", argv.verb)
        assertEquals(listOf("--fixes-only"), argv.args)
    }

    @Test
    fun `the bulk confirmation says the review in progress is not touched`() {
        val copy = confirmCopyFor(HousekeepingAction(HousekeepingKind.CLEAN_FIXES_ONE_ALL))
        assertTrue(copy.detail.contains("never committed anywhere else"))
        // El alcance se sigue afirmando -- es lo que hace seguro este boton --,
        // dicho por lo que el revisor tiene delante y no por el glob review/*.
        assertTrue(copy.detail.contains("reviewing right now is touched"))
        assertFalse(copy.detail.contains("git review clean"))
        assertEquals("Delete all", copy.button)
    }

    @Test
    fun `with no branches there is no section`() {
        assertEquals(null, section(PanelFixtures.noReviewReady()))
    }

    @Test
    fun `the section sits after the spent reading orders and before Compare`() {
        val titles = panelLayout(PanelFixtures.noReviewFixes())
            .blocks
            .filterIsInstance<Block.ToolsSection>()
            .map { it.title }
        assertEquals(
            listOf("Walkthrough", "Edits you extracted", "Compare", "Settings", "Support"),
            titles,
        )
    }

    @Test
    fun `the argv always carries --fixes-only, session or not`() {
        // A value re-read on every refresh cannot decide which branches a
        // command deletes: a late clean <x> would take a live review down.
        for (session in listOf(true, false)) {
            val argv = actionToArgv(
                "cleanReview",
                ActionParams.Housekeeping(
                    HousekeepingAction(
                        HousekeepingKind.CLEAN_FIXES_ONE,
                        "feature/x",
                        session = session,
                    ),
                ),
            )
            assertEquals("clean", argv.verb)
            assertEquals(listOf("--fixes-only", "feature/x"), argv.args)
        }
    }

    @Test
    fun `the confirmation says what dropping it costs`() {
        val unmerged = confirmCopyFor(
            HousekeepingAction(
                HousekeepingKind.CLEAN_FIXES_ONE,
                "feature/x",
                fixesState = FixesState.UNMERGED,
            ),
        )
        assertTrue(unmerged.detail.contains("the base branch does not have"))
        assertFalse(unmerged.detail.contains("undo the finish"))
        assertFalse(unmerged.detail.contains("git review clean"))
        assertEquals("Delete", unmerged.button)

        val empty = confirmCopyFor(
            HousekeepingAction(
                HousekeepingKind.CLEAN_FIXES_ONE,
                "feature/x",
                fixesState = FixesState.EMPTY,
                session = true,
            ),
        )
        assertTrue(empty.detail.contains("no work of yours is lost"))
        assertTrue(empty.detail.contains("You can still undo the finish afterwards."))
    }

    @Test
    fun `a state we do not understand reads as unknown, never as one of the three`() {
        val parsed = parseListFixes("fixes	review-fixes/feature/x	0	0	brand-new\n")
        assertEquals(listOf(FixesState.UNKNOWN), parsed.map { it.state })
    }
}
