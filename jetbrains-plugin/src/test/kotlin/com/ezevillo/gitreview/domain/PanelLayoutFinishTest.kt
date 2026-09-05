package com.ezevillo.gitreview.domain

import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PanelLayoutFinishTest {
    @Test
    fun `finish-pending banner explains when the edits join the branch`() {
        val layout = panelLayout(PanelFixtures.finishPending())
        val banner = layout.blocks.filterIsInstance<Block.Banner>().first()
        assertTrue(banner.paragraphs.first().startsWith("Your edits are staged and ready to commit to"))
        assertTrue(banner.paragraphs.first().endsWith("Commit them before switching branches."))
        // Commit y push se quedan -- ese paso vive en Source Control, o sea
        // fuera del panel --, pero los dos comandos que este texto nombraba son
        // los dos botones dibujados debajo de el.
        assertTrue(banner.paragraphs[1].contains("Commit and push them from Source Control"))
        assertFalse(banner.paragraphs[1].contains("--abort"))
        assertFalse(banner.paragraphs[1].contains("--keep-fixes"))
        val ids = banner.row.controls.map { it.id to it.emphasis }
        assertEquals(ControlId.CLEAN_REVIEW, ids[0].first)
        assertEquals(Emphasis.PRIMARY, ids[0].second)
        // "Clean" solo no decia que limpia; ahora dice ademas cual de los dos
        // cierra el ciclo.
        assertEquals("Keep edits & remove Undo", banner.row.controls[0].label)
        assertEquals(ControlId.UNDO_FINISH, ids[1].first)
        assertEquals("Undo Finish", banner.row.controls[1].label)
        assertTrue(banner.paragraphs[1].contains("You can still undo this finish."))
    }

    @Test
    fun `finish-conflict banner before notes and no nav`() {
        val layout = panelLayout(PanelFixtures.finishConflict())
        val types = layout.blocks.map { it::class.simpleName }
        val barIdx = types.indexOf("IdentityBar")
        val bannerIdx = types.indexOf("Banner")
        val noteIdx = types.indexOfFirst { it == "Note" }.let { if (it < 0) Int.MAX_VALUE else it }
        assertTrue(bannerIdx > barIdx)
        assertTrue(bannerIdx < noteIdx || noteIdx == Int.MAX_VALUE)
        assertFalse(layout.collectControls().any { it.id == ControlId.NEXT || it.id == ControlId.PREV })
        val banner = layout.blocks.filterIsInstance<Block.Banner>().first()
        assertEquals(listOf(ControlId.UNDO_FINISH, ControlId.RESUME_FINISH), banner.row.controls.map { it.id })
        assertEquals("Undo", banner.row.controls[0].label)
        assertEquals("Continue", banner.row.controls[1].label)
    }
}
