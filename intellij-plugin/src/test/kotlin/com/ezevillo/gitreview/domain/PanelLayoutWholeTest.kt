package com.ezevillo.gitreview.domain

import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PanelLayoutWholeTest {
    @Test
    fun `300 files produce 300 FileRows no truncation`() {
        val layout = panelLayout(PanelFixtures.reviewWhole(300))
        val files = layout.blocks.filterIsInstance<Block.FileRows>().first()
        assertEquals(300, files.rows.size)
        val heading = layout.blocks.filterIsInstance<Block.Heading>().first()
        assertEquals("300 files in this review", heading.text)
        val allDiff = layout.collectControls().first { it.id == ControlId.OPEN_ALL_CHANGES }
        assertEquals("Diff", allDiff.label)
        assertEquals("Open every change in this review at once", allDiff.tooltip)
        assertTrue(files.rows.first().lastOpened)
    }

    @Test
    fun `singular file heading`() {
        val layout = panelLayout(PanelFixtures.reviewWhole(1))
        val heading = layout.blocks.filterIsInstance<Block.Heading>().first()
        assertEquals("1 file in this review", heading.text)
    }

    @Test
    fun `empty range message`() {
        val layout = panelLayout(PanelFixtures.reviewWholeEmpty())
        val empty = layout.blocks.filterIsInstance<Block.EmptyMessage>().first()
        assertEquals("This review's range does not touch any files.", empty.text)
        assertTrue(layout.blocks.none { it is Block.FileRows })
    }
}
