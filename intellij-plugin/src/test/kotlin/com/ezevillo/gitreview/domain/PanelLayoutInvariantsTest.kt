package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PanelLayoutInvariantsTest {
    @Test
    fun `icon control requires accessible name`() {
        assertThrows(IllegalArgumentException::class.java) {
            Control(
                id = ControlId.PREV,
                label = null,
                accessibleName = "",
                emphasis = Emphasis.ICON,
            )
        }
    }

    @Test
    fun `null label requires ICON emphasis`() {
        assertThrows(IllegalArgumentException::class.java) {
            Control(
                id = ControlId.NEXT,
                label = null,
                accessibleName = "Next entry",
                emphasis = Emphasis.SECONDARY,
            )
        }
    }

    @Test
    fun `row rejects zero or three controls`() {
        assertThrows(IllegalArgumentException::class.java) {
            Block.Row(emptyList())
        }
        val c = Control(ControlId.SET_BASE, "A", "A", Emphasis.SECONDARY)
        assertThrows(IllegalArgumentException::class.java) {
            Block.Row(listOf(c, c, c))
        }
    }

    @Test
    fun `at most one PRIMARY per situation`() {
        val primary = Control(ControlId.START_REVIEW, "A", "A", Emphasis.PRIMARY)
        val primary2 = Control(ControlId.SET_BASE, "B", "B", Emphasis.PRIMARY)
        assertThrows(IllegalArgumentException::class.java) {
            PanelLayout(
                situation = Situation.NO_REVIEW,
                blocks = listOf(Block.Row(listOf(primary)), Block.Row(listOf(primary2))),
                titleActions = emptyList(),
            )
        }
    }

    @Test
    fun `excluded ids are not ControlId entries`() {
        val wires = ControlId.entries.map { it.wire }.toSet()
        for (ex in listOf("goToEntry", "forgetReview", "previewEditsStat", "showCliLog")) {
            assertTrue(ex !in wires, "excluded $ex must not be a ControlId")
            assertEquals(null, ControlId.fromWire(ex))
        }
    }

    @Test
    fun `requiresConfirmation matches destructive set`() {
        assertTrue(requiresConfirmation(ControlId.ABORT_REVIEW))
        assertTrue(requiresConfirmation(ControlId.DISCARD_INVENTORY))
        assertTrue(requiresConfirmation(ControlId.CLEAN_REVIEW))
        assertTrue(requiresConfirmation(ControlId.SAVE_REVIEW))
        assertTrue(!requiresConfirmation(ControlId.REFRESH))
        assertTrue(!requiresConfirmation(ControlId.NEXT))
        assertTrue(!requiresConfirmation(ControlId.FINISH_REVIEW))
    }
}
