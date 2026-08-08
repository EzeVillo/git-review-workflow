package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class SituationTest {
    @Test
    fun exitCodes() {
        assertEquals(Situation.REVIEW, situationForExitCode(0))
        assertEquals(Situation.NO_REVIEW, situationForExitCode(2))
        assertEquals(Situation.OUT_OF_RANGE, situationForExitCode(3))
        assertEquals(Situation.ERROR, situationForExitCode(1))
        assertEquals(Situation.ERROR, situationForExitCode(null))
    }

    @Test
    fun finishOverrides() {
        assertEquals(Situation.FINISH_CONFLICT, situationFor(0, true, false))
        assertEquals(Situation.FINISH_PENDING, situationFor(2, false, true))
        assertEquals(Situation.REVIEW, situationFor(0, false, true))
        assertEquals(Situation.OUT_OF_RANGE, situationFor(3, true, true))
    }

    @Test
    fun readable() {
        assertTrue(isReviewReadable(Situation.REVIEW))
        assertTrue(isReviewReadable(Situation.FINISH_CONFLICT))
        assertFalse(isReviewReadable(Situation.NO_REVIEW))
    }

    @Test
    fun idsRoundTrip() {
        for (s in Situation.entries) {
            assertEquals(s, Situation.fromId(s.id))
        }
    }
}
