package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Table-driven argv parity for mutative actions (SC-003 / FR-008 / T016d).
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
}
