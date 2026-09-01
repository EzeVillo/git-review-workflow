package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Table-driven argv parity for mutative actions.
 */
class ActionArgvParityTest {
    @Test
    fun productActionCountIs27() {
        assertEquals(27, PRODUCT_ACTIONS.size)
    }

    @Test
    fun startArgv() {
        val intent = ReviewIntent(
            branch = "feature/checkout",
            layout = ReviewLayout.STEP,
            range = ReviewRange.DELTA,
            source = ReviewSource.LOCAL,
        )
        val a = actionToArgv(
            "startReview",
            ActionParams.Start(intent, "main"),
        )
        assertEquals("start", a.verb)
        assertEquals(listOf("--step", "--delta", "--local", "--", "feature/checkout"), a.args)
        assertTrue(a.network)
    }

    @Test
    fun continueSaveAbortNav() {
        assertEquals(ActionArgv("continue", listOf("feature/x")), actionToArgv("continueReview", ActionParams.Continue("feature/x")))
        assertEquals(ActionArgv("save", emptyList()), actionToArgv("saveReview"))
        assertEquals(ActionArgv("abort", emptyList()), actionToArgv("abortReview"))
        assertEquals(ActionArgv("next", emptyList()), actionToArgv("next"))
        assertEquals(ActionArgv("prev", emptyList()), actionToArgv("prev"))
    }

    @Test
    fun finishFamily() {
        assertEquals(ActionArgv("finish", emptyList()), actionToArgv("finishReview", ActionParams.FinishOnto(false)))
        assertEquals(ActionArgv("finish", listOf("--onto-source")), actionToArgv("finishReview", ActionParams.FinishOnto(true)))
        assertEquals(ActionArgv("finish", listOf("--abort")), actionToArgv("undoFinish", ActionParams.UndoFinish(false)))
        assertEquals(ActionArgv("finish", listOf("--abort", "--force")), actionToArgv("undoFinish", ActionParams.UndoFinish(true)))
        assertEquals(ActionArgv("finish", listOf("--resume")), actionToArgv("resumeFinish", ActionParams.ResumeFinish(false)))
        assertEquals(
            ActionArgv("finish", listOf("--resume", "--onto-source")),
            actionToArgv("resumeFinish", ActionParams.ResumeFinish(true)),
        )
    }

    @Test
    fun housekeepingArgv() {
        assertEquals(
            ActionArgv("clean", listOf("f")),
            actionToArgv("cleanReview", ActionParams.Housekeeping(HousekeepingAction(HousekeepingKind.CLEAN_ONE, "f"))),
        )
        assertEquals(
            ActionArgv("clean", listOf("--keep-fixes", "f")),
            actionToArgv("cleanReview", ActionParams.Housekeeping(HousekeepingAction(HousekeepingKind.CLEAN_KEEP_FIXES, "f"))),
        )
        assertEquals(
            ActionArgv("clean", emptyList()),
            actionToArgv("cleanReview", ActionParams.Housekeeping(HousekeepingAction(HousekeepingKind.CLEAN_ALL))),
        )
        assertEquals(
            ActionArgv("forget", listOf("--saved", "f")),
            actionToArgv("forgetReview", ActionParams.Housekeeping(HousekeepingAction(HousekeepingKind.FORGET_SAVED_ONE, "f"))),
        )
        assertEquals(
            ActionArgv("forget", listOf("--saved", "--all")),
            actionToArgv("forgetReview", ActionParams.Housekeeping(HousekeepingAction(HousekeepingKind.FORGET_SAVED_ALL))),
        )
        assertEquals(
            ActionArgv("forget", listOf("--delta", "f")),
            actionToArgv("forgetReview", ActionParams.Housekeeping(HousekeepingAction(HousekeepingKind.FORGET_DELTA_ONE, "f"))),
        )
        assertEquals(
            ActionArgv("forget", listOf("--delta", "--all")),
            actionToArgv("forgetReview", ActionParams.Housekeeping(HousekeepingAction(HousekeepingKind.FORGET_DELTA_ALL))),
        )
        val stale = actionToArgv(
            "forgetReview",
            ActionParams.Housekeeping(HousekeepingAction(HousekeepingKind.FORGET_DELTA_STALE)),
        )
        assertEquals(listOf("--delta", "--stale"), stale.args)
        assertTrue(stale.network)
    }

    @Test
    fun configAndWalkthroughPreviewCompare() {
        assertEquals(
            ActionArgv("config", listOf("base", "--", "main")),
            actionToArgv("setBase", ActionParams.SetConfig("base", "main")),
        )
        assertEquals(
            ActionArgv("config", listOf("remote", "--", "upstream")),
            actionToArgv("setRemote", ActionParams.SetConfig("remote", "upstream")),
        )
        assertEquals(ActionArgv("walkthrough", listOf("init")), actionToArgv("walkthroughInit", ActionParams.WalkthroughInit(false)))
        assertEquals(ActionArgv("walkthrough", listOf("init", "--force")), actionToArgv("walkthroughInit", ActionParams.WalkthroughInit(true)))
        assertEquals(ActionArgv("walkthrough", listOf("build")), actionToArgv("walkthroughBuild"))
        assertEquals(ActionArgv("preview", emptyList()), actionToArgv("previewEdits"))
        assertEquals(ActionArgv("preview", listOf("--stat")), actionToArgv("previewEditsStat"))
        assertEquals(
            ActionArgv("compare", listOf("--step", "--", "a", "b")),
            actionToArgv("compareReview", ActionParams.Compare(listOf("--step"), "a", "b")),
        )
    }

    /**
     * Los controles de FILA no son acciones del producto -- no van al conteo de
     * 27 ni al menu Tools -- pero arman argv igual, y el suyo es el que borra el
     * borrador de UNA rama o la guia propia. Nunca `--all` ni `--saved`: una
     * accion sobre una fila no toca las demas.
     */
    @Test
    fun rowControlsArgv() {
        val forget = actionToArgv("forgetDraft", ActionParams.ForgetDraft("feature/x"))
        assertEquals("forget", forget.verb)
        assertEquals(listOf("--draft", "--", "feature/x"), forget.args)
        assertFalse(forget.network)

        // El verbo es walkthrough; guide es el primer argumento, como draft.
        assertEquals(
            ActionArgv("walkthrough", listOf("guide")),
            actionToArgv("createGuide", ActionParams.CreateGuide(false)),
        )
        assertEquals(
            ActionArgv("walkthrough", listOf("guide", "--team")),
            actionToArgv("createGuide", ActionParams.CreateGuide(true)),
        )
        // Borrar es siempre la propia: la compartida es un archivo trackeado, y
        // sacarla es git rm mas un commit. Nunca --team aca.
        val delete = actionToArgv("deleteGuide", ActionParams.DeleteGuide)
        assertEquals(ActionArgv("walkthrough", listOf("guide", "--delete")), delete)
        assertFalse(delete.args.contains("--team"))
    }

    /**
     * Las ocho acciones de lectura o de UI no mutan nada, y su argv vacio es lo
     * que lo dice: una que empezara a devolver un verbo lo mandaria a correr sin
     * confirmacion ni lock de mutacion.
     */
    @Test
    fun readOnlyActionsCarryNoArgv() {
        val readOnly = listOf(
            "openEntry", "openChange", "openAllChanges", "showWhy",
            "goToEntry", "refresh", "installCli", "showCliLog",
        )
        for (action in readOnly) {
            assertEquals(ActionArgv("", emptyList()), actionToArgv(action), action)
        }
        // Y son exactamente las que no mutan: el resto de las 27 arma un verbo.
        val mutating = PRODUCT_ACTIONS - readOnly.toSet()
        assertEquals(19, mutating.size)
    }

    /**
     * Las 27 estan cubiertas: cada una arma su argv o es de lectura, y ninguna
     * queda en el `else`. Un id nuevo en la lista sin entrada en la tabla
     * explota aca y no en el panel de alguien.
     */
    @Test
    fun everyProductActionIsMapped() {
        val params = mapOf(
            "startReview" to ActionParams.Start(
                ReviewIntent("feature", ReviewLayout.WALK, ReviewRange.FULL, ReviewSource.REMOTE),
                "main",
            ),
            "continueReview" to ActionParams.Continue("feature"),
            "compareReview" to ActionParams.Compare(emptyList(), "a", "b"),
            "setBase" to ActionParams.SetConfig("base", "main"),
            "setRemote" to ActionParams.SetConfig("remote", "origin"),
            "cleanReview" to ActionParams.Housekeeping(HousekeepingAction(HousekeepingKind.CLEAN_ALL)),
            "discardInventory" to ActionParams.Housekeeping(HousekeepingAction(HousekeepingKind.CLEAN_ONE, "f")),
            "forgetReview" to ActionParams.Housekeeping(HousekeepingAction(HousekeepingKind.FORGET_SAVED_ALL)),
        )
        for (action in PRODUCT_ACTIONS) {
            val argv = actionToArgv(action, params[action] ?: ActionParams.Empty)
            assertTrue(argv.verb.isNotEmpty() || argv.args.isEmpty(), action)
        }
    }

    @Test
    fun anUnknownActionIsRefusedInsteadOfGuessed() {
        val e = assertThrows(IllegalArgumentException::class.java) { actionToArgv("noSuchAction") }
        assertTrue(e.message.orEmpty().contains("noSuchAction"), e.message)
    }
}
