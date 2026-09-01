package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Los fallbacks por accion: lo UNICO que le llega al revisor cuando la CLI muere
 * sin decir nada. Con stderr no aparecen (FR-024), asi que la unica manera de
 * que alguien note que uno esta mal es que le pase justo ese dia.
 *
 * Un solo caso estaba cubierto. Aca se recorren los diecisiete pares
 * (accion, params) que el despachador puede armar, porque la falla que importa
 * no es que falte un texto: es que dos acciones distintas devuelvan el mismo, y
 * eso solo se ve mirandolas juntas.
 */
class FailureFallbackTest {
    /** Cada par (accion, params) que puede llegar, con el texto que le toca. */
    private val expected: List<Triple<String, ActionParams, String>> = listOf(
        Triple("abortReview", ActionParams.Empty, UserCopy.ABORT_FAILED),
        Triple("saveReview", ActionParams.Empty, UserCopy.SAVE_FAILED),
        Triple("continueReview", ActionParams.Empty, UserCopy.CONTINUE_FAILED),
        Triple("finishReview", ActionParams.Empty, UserCopy.FINISH_FAILED),
        Triple("undoFinish", ActionParams.UndoFinish(false), UserCopy.UNDO_ABORT_FAILED),
        Triple("undoFinish", ActionParams.UndoFinish(true), UserCopy.FORCE_UNDO_FAILED),
        Triple("resumeFinish", ActionParams.Empty, UserCopy.RESUME_FAILED),
        Triple("compareReview", ActionParams.Empty, UserCopy.COMPARE_FAILED),
        Triple("walkthroughInit", ActionParams.WalkthroughInit(false), UserCopy.WALKTHROUGH_INIT_FAILED),
        Triple("walkthroughInit", ActionParams.WalkthroughInit(true), UserCopy.WALKTHROUGH_FORCE_FAILED),
        Triple("walkthroughBuild", ActionParams.Empty, UserCopy.WALKTHROUGH_BUILD_FAILED),
        Triple("previewEdits", ActionParams.Empty, UserCopy.PREVIEW_FAILED),
        Triple("previewEditsStat", ActionParams.Empty, UserCopy.PREVIEW_FAILED),
        Triple("setBase", ActionParams.Empty, "Could not save the setting."),
        Triple("setRemote", ActionParams.Empty, "Could not save the setting."),
        Triple("next", ActionParams.Empty, "Could not move to the next entry."),
        Triple("prev", ActionParams.Empty, "Could not move to the previous entry."),
        Triple("startReview", ActionParams.Empty, UserCopy.START_FAILED),
    )

    @Test
    fun everyActionGetsItsOwnSentence() {
        for ((action, params, text) in expected) {
            assertEquals(text, UserCopy.failureFallback(action, params), "$action / $params")
        }
    }

    /**
     * Ninguno nombra un comando ni un flag: el que apretó el botón no escribió
     * ningún argv, y decírselo justo cuando no hay nada más que leer es la
     * definición de un mensaje inútil.
     */
    @Test
    fun noneOfThemNamesACommandOrAFlag() {
        for ((action, params, _) in expected + genericCases()) {
            val text = UserCopy.failureFallback(action, params)
            assertFalse(text.contains("git review"), "$action: $text")
            assertFalse(text.contains("--"), "$action: $text")
            assertFalse(text.contains("`"), "$action: $text")
            // Y dicen qué NO pasó, en pasado y en una oración.
            assertTrue(text.endsWith("."), "$action: $text")
        }
    }

    /**
     * Los dos pares que dependen de un flag no se colapsan: forzar el undo
     * descarta trabajo mas nuevo, y forzar el init pisa prosa escrita a mano.
     * Que los dos textos digan lo mismo es como se pierde esa diferencia.
     */
    @Test
    fun theForcedVariantsDoNotShareTheirTextWithTheGentleOnes() {
        assertFalse(UserCopy.UNDO_ABORT_FAILED == UserCopy.FORCE_UNDO_FAILED)
        assertFalse(UserCopy.WALKTHROUGH_INIT_FAILED == UserCopy.WALKTHROUGH_FORCE_FAILED)
        // Y sin params se elige la variante suave, nunca la destructiva.
        assertEquals(UserCopy.UNDO_ABORT_FAILED, UserCopy.failureFallback("undoFinish"))
        assertEquals(UserCopy.WALKTHROUGH_INIT_FAILED, UserCopy.failureFallback("walkthroughInit"))
        // Un params del tipo equivocado tampoco escala a la variante forzada.
        assertEquals(
            UserCopy.UNDO_ABORT_FAILED,
            UserCopy.failureFallback("undoFinish", ActionParams.WalkthroughInit(true)),
        )
        assertEquals(
            UserCopy.WALKTHROUGH_INIT_FAILED,
            UserCopy.failureFallback("walkthroughInit", ActionParams.UndoFinish(true)),
        )
    }

    /**
     * Limpiar y olvidar comparten la entrada porque comparten el argv, y ahi el
     * texto lo decide el VERBO que va a correr -- no el id de la accion, que en
     * los dos casos es el mismo.
     */
    @Test
    fun cleaningAndForgettingAreToldApartByTheirVerb() {
        fun fallbackFor(kind: HousekeepingKind) = UserCopy.failureFallback(
            "cleanReview",
            ActionParams.Housekeeping(HousekeepingAction(kind, "f")),
        )
        for (kind in HousekeepingKind.entries) {
            val want = if (kind.name.startsWith("CLEAN")) "Could not clean up." else "Could not forget that."
            assertEquals(want, fallbackFor(kind), kind.name)
        }
        // El mismo id con el otro nombre contesta igual: lo que manda es el kind.
        assertEquals(
            "Could not forget that.",
            UserCopy.failureFallback(
                "forgetReview",
                ActionParams.Housekeeping(HousekeepingAction(HousekeepingKind.FORGET_SAVED_ALL)),
            ),
        )
        // Sin el kind no se puede saber cuál era, y "clean up" es lo que cubre
        // las dos: el botón que lo dispara vive en el bloque de limpieza.
        assertEquals("Could not clean up.", UserCopy.failureFallback("cleanReview"))
        assertEquals("Could not clean up.", UserCopy.failureFallback("forgetReview"))
    }

    @Test
    fun anUnknownActionFallsBackToTheGenericOne() {
        assertEquals("Something went wrong.", UserCopy.failureFallback("noSuchAction"))
    }

    /**
     * Y ninguno de los específicos es el genérico: es la única forma de que
     * agregar una acción sin su texto se note.
     */
    @Test
    fun noSpecificActionQuietlyReturnsTheGenericSentence() {
        for ((action, params, _) in expected) {
            assertFalse(
                UserCopy.failureFallback(action, params) == "Something went wrong.",
                "$action has no fallback of its own",
            )
        }
    }

    private fun genericCases(): List<Triple<String, ActionParams, String>> = listOf(
        Triple("cleanReview", ActionParams.Empty, "Could not clean up."),
        Triple("forgetReview", ActionParams.Empty, "Could not clean up."),
    )
}
