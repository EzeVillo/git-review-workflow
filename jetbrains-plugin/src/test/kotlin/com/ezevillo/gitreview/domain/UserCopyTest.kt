package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Locks the English copy that must stay byte-aligned with the VS Code extension.
 */
class UserCopyTest {
    @Test
    fun `abort confirm matches VS Code`() {
        assertEquals("Cancel the review of feature/x?", UserCopy.abortTitle("feature/x"))
        assertEquals(
            "This returns to the branch you started the review from; your uncommitted edits will be discarded.",
            UserCopy.ABORT_DETAIL,
        )
        assertEquals("Cancel Review", UserCopy.ABORT_BUTTON)
    }

    @Test
    fun `save confirm matches VS Code`() {
        assertEquals("Save the review of feature/x for later?", UserCopy.saveTitle("feature/x"))
        assertEquals("Save for Later", UserCopy.SAVE_BUTTON)
    }

    @Test
    fun `continue confirm matches VS Code`() {
        assertEquals("Continue the saved review of feature/x?", UserCopy.continueTitle("feature/x"))
        assertEquals(
            "This switches to review/feature/x and restores your edits in the working tree.",
            UserCopy.continueDetail("feature/x"),
        )
        assertEquals("Continue", UserCopy.CONTINUE_BUTTON)
    }

    @Test
    fun `finish success toasts match VS Code`() {
        assertEquals(
            "review-fixes/feature/x is ready. Undo is available if you need it.",
            UserCopy.finishSuccess("review-fixes/feature/x", FinishOutcome.PENDING),
        )
        assertEquals(
            "feature/x is ready.",
            UserCopy.finishSuccess("feature/x", FinishOutcome.NO_EDITS),
        )
        assertEquals("review-fixes/a", UserCopy.finishDestination(false, "a"))
        assertEquals("a", UserCopy.finishDestination(true, "a"))
    }

    @Test
    fun `undo force gate copy matches VS Code`() {
        assertEquals("Undo this finish?", UserCopy.UNDO_TITLE)
        assertEquals("Discard Work and Undo", UserCopy.UNDO_FORCE_BUTTON)
        assertTrue(UserCopy.UNDO_FORCE_DETAIL.contains("cannot be undone"))
    }

    /**
     * El asistente ya no confirma: `start` se niega solo con el arbol sucio y
     * una review empezada se cancela con un boton del panel, asi que la quinta
     * pantalla solo repetia las cuatro respuestas y agregaba el comando.
     *
     * Lo que sobrevive de ella es la frase, mudada al paso que ahora ejecuta.
     */
    @Test
    fun `the last wizard step names the branch it is about to review`() {
        assertEquals(
            "Start reviewing feature/x — how do you want to read it?",
            UserCopy.startLayoutTitle("feature/x"),
        )
        // El paso de una fila del bloque de borradores no tiene rama que nombrar
        // y se queda con el titulo llano.
        assertEquals("Start a review — how to read it", UserCopy.START_LAYOUT_TITLE)
    }

    @Test
    fun `stale and failure fallbacks match VS Code`() {
        // Uno solo para los ocho comandos. Eran diez, y cada uno nombraba el
        // verbo que no corrio -- que es el boton que el revisor acaba de
        // apretar, no un dato nuevo. El texto entero se afirma porque es copy
        // compartida byte a byte con userCopy.ts y UserCopy.cs.
        assertEquals(
            "The repository changed while you were deciding, so nothing happened.",
            UserCopy.STALE,
        )
        // No nombra ningun verbo del producto: eso es lo que lo hace servir para
        // los ocho, y lo que se rompe si alguien lo vuelve a especializar.
        listOf("finish", "save", "undo", "start", "cancel", "resume", "discard").forEach {
            assertFalse(UserCopy.STALE.contains(it), "STALE nombra el verbo '$it'")
        }
        // Los fallbacks son lo UNICO que llega cuando la CLI muere sin stderr, y
        // decian el argv que no anduvo -- un comando que quien usa el panel no
        // escribio, justo cuando no hay nada mas que leer.
        assertEquals("Could not cancel the review.", UserCopy.failureFallback("abortReview"))
        assertEquals(
            "Could not undo the finish, even discarding the newer work.",
            UserCopy.failureFallback("undoFinish", ActionParams.UndoFinish(true)),
        )
        assertEquals("Could not move to the next entry.", UserCopy.failureFallback("next"))
        assertEquals("Could not save the setting.", UserCopy.failureFallback("setBase"))
        assertEquals(
            "Another operation is already in progress",
            UserCopy.DISCARD_BUSY,
        )
    }

    @Test
    fun `housekeeping confirmCopy stays aligned`() {
        val clean = confirmCopyFor(HousekeepingAction(HousekeepingKind.CLEAN_ONE, "feature/x"))
        assertEquals("Delete the leftovers from reviewing feature/x?", clean.title)
        assertEquals("Delete", clean.button)

        val discard = confirmCopyFor(HousekeepingAction(HousekeepingKind.FORGET_SAVED_ONE, "feature/x"))
        assertEquals("Delete the paused review of feature/x?", discard.title)
        assertEquals("Delete", discard.button)

        // Los tres de --delta dicen la CONSECUENCIA, y la dicen con la etiqueta
        // que el asistente usa para el rango: quien vaya a apretar esto la
        // eligio alguna vez ahi. "Removes the last-reviewed tip" describia un
        // ref que ninguna superficie del producto nombra.
        val delta = confirmCopyFor(HousekeepingAction(HousekeepingKind.FORGET_DELTA_ONE, "feature/x"))
        assertEquals("Forget where you got to on feature/x?", delta.title)
        assertTrue(delta.detail.contains("\"only what is new\""))
        assertFalse(delta.detail.contains("--delta"))
    }

    @Test
    fun `flattenCliMessage joins non-empty lines`() {
        assertEquals("a b", flattenCliMessage("  a \n\n b  \n"))
        assertEquals("", flattenCliMessage("\n  \n"))
        assertEquals("only", firstCliLine("\n only \n two"))
        assertEquals(
            "fallback",
            cliErrorText("", "", "fallback"),
        )
        assertEquals(
            "err",
            cliErrorText("err\n", "out", "fallback"),
        )
    }

    @Test
    fun `picker empty-state messages match VS Code`() {
        assertEquals("No branches to pick a base from were found.", UserCopy.NO_BRANCHES_FOR_BASE)
        assertEquals("No remotes to pick from were found.", UserCopy.NO_REMOTES)
        assertEquals("No active review to preview.", UserCopy.NO_ACTIVE_PREVIEW)
        assertEquals(
            "This is a read-only compare review; there is nothing to finish. Use Cancel when done.",
            UserCopy.READONLY_FINISH,
        )
    }
}
