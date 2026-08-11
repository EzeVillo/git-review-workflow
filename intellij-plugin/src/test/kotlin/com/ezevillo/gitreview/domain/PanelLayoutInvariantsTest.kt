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
    fun `index is allowed only on inventory row controls`() {
        // The rule the panel relies on to route a click back to the row it came
        // from: an index identifies a row of the inventory, and nothing else. It
        // is checked in PanelLayout's init, so a violation is an exception on the
        // render path rather than a red test — which is why it needs one here.
        val indexed = Control(
            id = ControlId.CONTINUE_REVIEW,
            label = "Resume",
            accessibleName = "Resume",
            emphasis = Emphasis.SECONDARY,
            index = 0,
        )
        val row = InventoryRow(
            name = "review-saved/feature",
            badges = listOf("saved"),
            meta = "walk [1/3]",
            controls = listOf(indexed),
        )
        // Hosted by an InventoryRows block: legal, and it survives being nested
        // in a ToolsSection, which is where the inventory actually lives.
        PanelLayout(
            situation = Situation.NO_REVIEW,
            blocks = listOf(Block.ToolsSection("Reviews", listOf(Block.InventoryRows(listOf(row))))),
            titleActions = emptyList(),
        )

        // The same control anywhere else is not: a plain Row, or a title action.
        assertThrows(IllegalArgumentException::class.java) {
            PanelLayout(
                situation = Situation.NO_REVIEW,
                blocks = listOf(Block.Row(listOf(indexed))),
                titleActions = emptyList(),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            PanelLayout(
                situation = Situation.NO_REVIEW,
                blocks = emptyList(),
                titleActions = listOf(indexed),
            )
        }
        // FileRows carries its position on the row (FileRow.index), never on a
        // control, so having one in the layout does not license an indexed
        // control the way it used to.
        assertThrows(IllegalArgumentException::class.java) {
            PanelLayout(
                situation = Situation.REVIEW,
                blocks = listOf(
                    Block.FileRows(listOf(FileRow(display = "src/a.kt", index = 0, lastOpened = false))),
                    Block.Row(listOf(indexed)),
                ),
                titleActions = emptyList(),
            )
        }
    }

    @Test
    fun `inventory controls must carry an index`() {
        assertThrows(IllegalArgumentException::class.java) {
            InventoryRow(
                name = "review/feature",
                badges = emptyList(),
                meta = "walk [1/3]",
                controls = listOf(
                    Control(ControlId.CONTINUE_REVIEW, "Resume", "Resume", Emphasis.SECONDARY),
                ),
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
