package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PanelModelTest {
    @Test
    fun noReviewInventoryAndSetup() {
        val state = ReviewState(
            situation = Situation.NO_REVIEW,
            branches = listOf(
                BranchRecord("review-saved/f", saved = true, current = false, orphan = false, mode = ReviewMode.WALK),
            ),
            config = EffectiveConfig(base = null, remote = "origin"),
        )
        val m = buildPanelModel(state, PanelInputs(busy = false))
        assertTrue(m.noBaseConfigured)
        assertEquals(1, m.reviews.size)
        assertTrue(m.reviews[0].resumable)
        assertEquals("origin", m.configuredRemote)
    }

    @Test
    fun walkCurrentAndWhyLoading() {
        val state = ReviewState(
            situation = Situation.REVIEW,
            state = StateRecord(
                branch = "review/f",
                source = "f",
                tip = "abc",
                mode = ReviewMode.WALK,
                walkthrough = WalkthroughStatus.APPLIED,
                position = 1,
                total = 2,
                recorded = 2,
                current = toPathRef("a.kt"),
            ),
            entries = listOf(
                EntryRecord(1, toPathRef("a.kt"), essential = true, annotated = true),
                EntryRecord(2, toPathRef("b.kt"), essential = false, annotated = true),
            ),
        )
        val m = buildPanelModel(state, PanelInputs(busy = false))
        assertEquals(1, m.position)
        assertTrue(m.atFirst)
        assertFalse(m.atLast)
        assertEquals("a.kt", m.current?.display)
        assertEquals(WhyState.LOADING, m.why?.state)
    }

    @Test
    fun finishConflictLocksNav() {
        val state = ReviewState(
            situation = Situation.FINISH_CONFLICT,
            state = StateRecord(
                branch = "review/f",
                source = "f",
                tip = "abc",
                mode = ReviewMode.STEP,
                walkthrough = WalkthroughStatus.NONE,
                position = 2,
                total = 3,
                recorded = 3,
                current = "deadbeef",
            ),
            entries = listOf(
                EntryRecord(1, "aaa", banked = false),
                EntryRecord(2, "bbb", banked = true),
                EntryRecord(3, "ccc", banked = false),
            ),
        )
        val m = buildPanelModel(state, PanelInputs(busy = true))
        assertTrue(m.navigationLocked)
        assertFalse(m.atFirst)
        assertFalse(m.atLast)
        assertTrue(m.busy)
    }

    @Test
    fun resumableSourceAt() {
        val branches = listOf(
            BranchRecord("review-saved/f", saved = true, current = false, orphan = false, mode = ReviewMode.WALK),
            BranchRecord("review/f", saved = false, current = true, orphan = false, mode = ReviewMode.WALK),
        )
        assertNull(resumableSourceAt(branches, 0)) // active same source
        assertNull(resumableSourceAt(branches, "x"))
    }

    // --- PanelDraft (012) --------------------------------------------------------

    private fun stateWithDrafts(situation: Situation, stdout: String): ReviewState = ReviewState(
        situation = situation,
        config = EffectiveConfig(base = "main", remote = "origin"),
        drafts = parseConfigPorcelain(stdout).drafts,
    )

    @Test
    fun draftsArePopulatedOnlyInNoReview() {
        val out =
            "draft\tfeature/checkout\t/repo/.git/review-walkthrough/feature/checkout.md\t3\t9\tlocal\tdelta"
        val shown = buildPanelModel(stateWithDrafts(Situation.NO_REVIEW, out), PanelInputs(busy = false))
        assertEquals(
            listOf(
                PanelDraft(
                    branch = "feature/checkout",
                    path = "/repo/.git/review-walkthrough/feature/checkout.md",
                    annotated = 3,
                    total = 9,
                    startable = true,
                    spent = false,
                ),
            ),
            shown.drafts,
        )

        // Una review en curso es siempre lo más importante que el panel tiene
        // para decir; el borrador de otra rama no le compite el cuerpo.
        for (situation in listOf(Situation.FINISH_PENDING, Situation.ERROR, Situation.OUT_OF_RANGE)) {
            assertTrue(
                buildPanelModel(stateWithDrafts(situation, out), PanelInputs(busy = false)).drafts.isEmpty(),
                situation.name,
            )
        }
    }

    @Test
    fun aRowWithUnknownFlagsIsNotStartable() {
        val out = "draft\tfeature/x\t/repo/.git/review-walkthrough/feature/x.md\t0\t2\tunknown\tunknown"
        val model = buildPanelModel(stateWithDrafts(Situation.NO_REVIEW, out), PanelInputs(busy = false))
        assertFalse(model.drafts.single().startable)
    }

    @Test
    fun draftAtValidatesTheIndexThatComesFromThePanel() {
        val drafts = parseConfigPorcelain(
            "draft\tfeature/x\t/repo/.git/review-walkthrough/feature/x.md\t0\t2\tremote\tfull",
        ).drafts
        assertEquals("feature/x", draftAt(drafts, 0)?.src)
        assertNull(draftAt(drafts, 1))
        assertNull(draftAt(drafts, -1))
        assertNull(draftAt(drafts, "0"))
        assertNull(draftAt(drafts, null))
    }
}
