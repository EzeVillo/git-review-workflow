package com.ezevillo.gitreview.domain

import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PanelLayoutDiagnosticsTest {
    @Test
    fun `cli-missing has install command and other options link`() {
        val layout = panelLayout(PanelFixtures.cliMissing())
        assertTrue(layout.blocks.any { it is Block.CodeCommand && it.command == NPM_INSTALL_CMD })
        val link = layout.collectControls().first { it.id == ControlId.INSTALL_CLI }
        assertEquals("Other install options", link.label)
        assertEquals(Emphasis.LINK, link.emphasis)
        assertTrue(layout.collectControls().any { it.id == ControlId.COPY_CLI_INSTALL && it.label == "Copy" })
    }

    @Test
    fun `cli-outdated uses update command`() {
        val layout = panelLayout(PanelFixtures.cliOutdated())
        assertTrue(layout.blocks.any { it is Block.CodeCommand && it.command == NPM_UPDATE_CMD })
    }

    @Test
    fun `out-of-range and error have How to fix it primary`() {
        for (model in listOf(PanelFixtures.outOfRange(), PanelFixtures.error())) {
            val layout = panelLayout(model)
            val help = layout.collectControls().first { it.id == ControlId.OUT_OF_RANGE_HELP }
            assertEquals("How to fix it", help.label)
            assertEquals(Emphasis.PRIMARY, help.emphasis)
            assertTrue(layout.blocks.any { it is Block.Stderr })
        }
    }
}
