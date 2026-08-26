package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class CliMessageTest {
    // El caso que motivo la funcion: apretar la oferta y no ver nada. El
    // resultado del verbo viaja por stdout y este camino leia solo stderr.
    @Test
    fun theVerbOutcomeCannotBeLostBecauseItComesOnStdout() {
        assertEquals(
            "updated the file: 1 kept, 1 added, 0 dropped",
            draftOutcomeText("updated the file: 1 kept, 1 added, 0 dropped\n", ""),
        )
    }

    @Test
    fun withANoteTheOutcomeComesFirst() {
        val msg = draftOutcomeText(
            "updated the file: 2 kept, 0 added, 0 dropped\n",
            "note: no authoring guide. Create one with:\n        git review walkthrough guide\n",
        )
        assertEquals(
            "updated the file: 2 kept, 0 added, 0 dropped — " +
                "note: no authoring guide. Create one with: git review walkthrough guide",
            msg,
        )
        // El separador va ENTRE los dos tramos, nunca adentro de uno.
        assertEquals(2, msg.split(" — ").size)
    }

    @Test
    fun anEmptyStreamLeavesNoDanglingSeparator() {
        assertEquals("note: solo la nota", draftOutcomeText("", "note: solo la nota"))
        assertEquals("", draftOutcomeText("", ""))
        assertEquals("", draftOutcomeText("  \n \n", "\n"))
    }
}
