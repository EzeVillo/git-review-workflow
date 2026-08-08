package com.ezevillo.gitreview.domain

import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PanelLayoutSkeletonTest {
    @Test
    fun `skeleton keeps silhouette with disabled controls`() {
        val layout = panelLayout(PanelFixtures.reviewWalk(why = PanelWhy(WhyState.LOADING)), loading = true)
        assertTrue(layout.blocks.any { it is Block.IdentityBar && it.skeleton })
        assertTrue(layout.blocks.any { it is Block.Why && it.state == WhyState.LOADING })
        val bodyControls = layout.collectControls().filter {
            it.id == ControlId.OPEN_ENTRY || it.id == ControlId.OPEN_CHANGE ||
                it.id == ControlId.PREV || it.id == ControlId.NEXT
        }
        assertTrue(bodyControls.isNotEmpty())
        assertTrue(bodyControls.all { !it.enabled })
    }

    @Test
    fun `skeleton delay constant is under 200ms for SC-008`() {
        assertTrue(SKELETON_DELAY_MS <= 200)
        assertEquals(120L, SKELETON_DELAY_MS)
        assertEquals(800L, WHY_CEILING_MS)
    }

    @Test
    fun `step skeleton has no why block`() {
        val layout = panelLayout(PanelFixtures.reviewStep(), loading = true)
        assertFalse(layout.blocks.any { it is Block.Why })
    }
}
