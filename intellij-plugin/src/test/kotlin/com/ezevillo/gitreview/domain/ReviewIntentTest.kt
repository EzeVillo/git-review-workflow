package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ReviewIntentTest {
    @Test
    fun intentToArgsOrder() {
        val intent = ReviewIntent(
            branch = "feature/x",
            layout = ReviewLayout.STEP,
            range = ReviewRange.DELTA,
            source = ReviewSource.LOCAL,
        )
        assertEquals(
            listOf("--step", "--delta", "--local", "--", "feature/x"),
            intentToArgs(intent, "main"),
        )
    }

    @Test
    fun walkRemoteFullUsesCurrentBranch() {
        val intent = ReviewIntent(
            layout = ReviewLayout.WALK,
            range = ReviewRange.FULL,
            source = ReviewSource.REMOTE,
        )
        assertEquals(listOf("--", "main"), intentToArgs(intent, "main"))
    }

    @Test
    fun wholeOffline() {
        val intent = ReviewIntent(
            branch = "f",
            layout = ReviewLayout.WHOLE,
            range = ReviewRange.FULL,
            source = ReviewSource.OFFLINE,
        )
        assertEquals(listOf("--no-walk", "--offline", "--", "f"), intentToArgs(intent, "main"))
    }

    @Test
    fun keysFlag() {
        val intent = ReviewIntent(
            branch = "f",
            layout = ReviewLayout.KEYS,
            range = ReviewRange.FULL,
            source = ReviewSource.REMOTE,
        )
        assertEquals(listOf("--keys", "--", "f"), intentToArgs(intent, "main"))
    }

    @Test
    fun validateDeltaRequiresRecord() {
        val intent = ReviewIntent(
            layout = ReviewLayout.WHOLE,
            range = ReviewRange.DELTA,
            source = ReviewSource.REMOTE,
        )
        assertTrue(validateIntent(intent, IntentValidationContext()) is IntentValidationResult.Fail)
        assertTrue(
            validateIntent(
                intent,
                IntentValidationContext(DeltaRecord("f", "abc", DeltaOrigin.REMOTE)),
            ) is IntentValidationResult.Ok,
        )
    }
}
