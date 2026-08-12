package com.ezevillo.gitreview.domain

import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class TitleBarActionsTest {
    @Test
    fun `review has full title bar order`() {
        val actions = titleBarActions(PanelFixtures.reviewWalk())
        assertEquals(
            listOf(
                ControlId.REFRESH,
                ControlId.FINISH_REVIEW,
                ControlId.SAVE_REVIEW,
                ControlId.ABORT_REVIEW,
                ControlId.PREVIEW_EDITS,
            ),
            actions.map { it.id },
        )
        assertEquals(listOf("Refresh", "Finish", "Save", "Cancel", "Preview edits"), actions.map { it.label })
    }

    @Test
    fun `readonly omits Finish`() {
        val m = PanelFixtures.reviewWalk().copy(readonly = true)
        val ids = titleBarActions(m).map { it.id }
        assertFalse(ControlId.FINISH_REVIEW in ids)
        assertTrue(ControlId.SAVE_REVIEW in ids)
    }

    @Test
    fun `busy keeps only Refresh`() {
        val ids = titleBarActions(PanelFixtures.reviewWalk(busy = true)).map { it.id }
        assertEquals(listOf(ControlId.REFRESH), ids)
    }

    @Test
    fun `finish-conflict has Refresh Cancel Preview not Finish Save`() {
        val ids = titleBarActions(PanelFixtures.finishConflict()).map { it.id }
        assertEquals(
            listOf(ControlId.REFRESH, ControlId.ABORT_REVIEW, ControlId.PREVIEW_EDITS),
            ids,
        )
    }

    @Test
    fun `empty state only Refresh`() {
        val ids = titleBarActions(PanelFixtures.noReviewReady()).map { it.id }
        assertEquals(listOf(ControlId.REFRESH), ids)
    }
}
