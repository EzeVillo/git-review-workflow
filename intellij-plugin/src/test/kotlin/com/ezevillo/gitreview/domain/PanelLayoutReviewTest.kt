package com.ezevillo.gitreview.domain

import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PanelLayoutReviewTest {
    @Test
    fun `walk layout sequence has file diff nav and why`() {
        val layout = panelLayout(PanelFixtures.reviewWalk())
        val controls = layout.collectControls().filter { it.id !in titleIds }
        val ids = controls.map { it.id }
        assertTrue(ControlId.SHOW_WHY in ids)
        assertTrue(ControlId.OPEN_ENTRY in ids)
        assertTrue(ControlId.OPEN_CHANGE in ids)
        assertTrue(ControlId.PREV in ids)
        assertTrue(ControlId.NEXT in ids)
        val showWhy = controls.first { it.id == ControlId.SHOW_WHY }
        assertEquals("open in editor", showWhy.label)
        assertEquals(Emphasis.LINK, showWhy.emphasis)
        val prev = controls.first { it.id == ControlId.PREV }
        assertEquals("Previous entry", prev.accessibleName)
        assertEquals(Emphasis.ICON, prev.emphasis)
        val next = controls.first { it.id == ControlId.NEXT }
        assertEquals("Next entry", next.accessibleName)
        assertTrue(layout.blocks.any { it is Block.IdentityBar })
        assertTrue(layout.blocks.any { it is Block.Why })
    }

    @Test
    fun `step layout has diff only and no why`() {
        val layout = panelLayout(PanelFixtures.reviewStep())
        val body = layout.collectControls().filter { it.id !in titleIds }
        assertFalse(body.any { it.id == ControlId.SHOW_WHY })
        assertFalse(body.any { it.id == ControlId.OPEN_ENTRY })
        assertTrue(body.any { it.id == ControlId.OPEN_CHANGE && it.label == "Diff" })
        assertTrue(layout.blocks.none { it is Block.Why })
        val title = layout.blocks.filterIsInstance<Block.EntryTitle>().first()
        assertEquals("Fix the thing", title.text)
        // Inventario del commit actual (file rows), como whole.
        val files = layout.blocks.filterIsInstance<Block.FileRows>().first()
        assertEquals(2, files.rows.size)
        assertEquals("src/a.kt", files.rows[0].display)
        assertTrue(files.rows[0].lastOpened)
        val heading = layout.blocks.filterIsInstance<Block.Heading>().first()
        assertEquals("2 files in this commit", heading.text)
    }

    @Test
    fun `first entry disables prev last disables next`() {
        val first = panelLayout(PanelFixtures.reviewWalk(atFirst = true, atLast = false, position = 1))
        val prev = first.collectControls().first { it.id == ControlId.PREV }
        val next = first.collectControls().first { it.id == ControlId.NEXT }
        assertFalse(prev.enabled)
        assertTrue(next.enabled)

        val last = panelLayout(PanelFixtures.reviewWalk(atFirst = false, atLast = true, position = 3))
        assertTrue(last.collectControls().first { it.id == ControlId.PREV }.enabled)
        assertFalse(last.collectControls().first { it.id == ControlId.NEXT }.enabled)
    }

    @Test
    fun `busy disables mutators`() {
        val layout = panelLayout(PanelFixtures.reviewWalk(busy = true))
        val prev = layout.collectControls().first { it.id == ControlId.PREV }
        val next = layout.collectControls().first { it.id == ControlId.NEXT }
        assertFalse(prev.enabled)
        assertFalse(next.enabled)
        // Title actions except refresh absent when busy
        assertEquals(listOf(ControlId.REFRESH), layout.titleActions.map { it.id })
    }

    @Test
    fun `badge precedence key over uncovered over edits`() {
        val layout = panelLayout(PanelFixtures.reviewWalk())
        val head = layout.blocks.filterIsInstance<Block.EntryHead>().first()
        assertEquals("key", head.badge)
    }

    @Test
    fun `without why present no open in editor`() {
        val layout = panelLayout(
            PanelFixtures.reviewWalk(why = PanelWhy(WhyState.ABSENT)),
        )
        assertFalse(layout.collectControls().any { it.id == ControlId.SHOW_WHY })
    }

    @Test
    fun `empty cursor message`() {
        val layout = panelLayout(PanelFixtures.reviewWalkEmptyCursor())
        val empty = layout.blocks.filterIsInstance<Block.EmptyMessage>().first()
        assertEquals("The cursor does not point at any entry in the sequence.", empty.text)
    }

    private val titleIds = setOf(
        ControlId.REFRESH,
        ControlId.FINISH_REVIEW,
        ControlId.SAVE_REVIEW,
        ControlId.ABORT_REVIEW,
        ControlId.PREVIEW_EDITS,
    )
}
