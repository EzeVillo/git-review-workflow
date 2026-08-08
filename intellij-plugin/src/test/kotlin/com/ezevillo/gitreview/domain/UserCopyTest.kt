package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
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

    @Test
    fun `start confirm uses layoutSummary`() {
        assertEquals(
            "Start reviewing feature/x, as a walkthrough?",
            UserCopy.startConfirmTitle("feature/x", ReviewLayout.WALK),
        )
        assertEquals(
            "git review start --step -- feature/x\nComparing against main.",
            UserCopy.startConfirmDetail(listOf("--step", "--", "feature/x"), "main"),
        )
        assertEquals("Start the review", UserCopy.START_CONFIRM_BUTTON)
    }

    @Test
    fun `stale and failure fallbacks match VS Code`() {
        assertEquals(
            "The review state changed before the cancellation ran; nothing was cancelled.",
            UserCopy.staleMessage("abortReview"),
        )
        assertEquals(
            "The review state changed before the force-undo ran; nothing was undone.",
            UserCopy.staleMessage("undoFinish", force = true),
        )
        assertEquals("git review abort failed.", UserCopy.failureFallback("abortReview"))
        assertEquals(
            "git review finish --abort --force failed.",
            UserCopy.failureFallback("undoFinish", ActionParams.UndoFinish(true)),
        )
        assertEquals(
            "Another operation is already in progress",
            UserCopy.DISCARD_BUSY,
        )
    }

    @Test
    fun `housekeeping confirmCopy stays aligned`() {
        val clean = confirmCopyFor(HousekeepingAction(HousekeepingKind.CLEAN_ONE, "feature/x"))
        assertEquals("Clean leftover review branches for feature/x?", clean.title)
        assertEquals("Clean", clean.button)

        val discard = confirmCopyFor(HousekeepingAction(HousekeepingKind.FORGET_SAVED_ONE, "feature/x"))
        assertEquals("Discard the saved review of feature/x?", discard.title)
        assertEquals("Discard", discard.button)
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
