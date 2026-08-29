package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class VersionTest {
    @Test
    fun compareEqual() {
        assertEquals(0, compareVersions("0.4.0", "0.4.0"))
    }

    @Test
    fun compareMajorMinorPatch() {
        assertTrue((compareVersions("0.4.0", "1.0.0") as Int) < 0)
        assertTrue((compareVersions("0.3.9", "0.4.0") as Int) < 0)
        assertTrue((compareVersions("0.4.0", "0.4.1") as Int) < 0)
        assertTrue((compareVersions("0.5.0", "0.4.0") as Int) > 0)
    }

    @Test
    fun invalidFormatReturnsNull() {
        assertNull(compareVersions("not-a-version", "0.4.0"))
        assertNull(compareVersions("0.4", "0.4.0"))
    }

    @Test
    fun isOutdatedAgainstMin() {
        assertFalse(isOutdated(MIN_CLI_VERSION))
        assertEquals("0.8.0", MIN_CLI_VERSION)
        assertTrue(isOutdated("0.2.1"))
        assertTrue(isOutdated("0.3.0"))
        assertTrue(isOutdated("0.3.9"))
        assertTrue(isOutdated("0.4.0"))
        assertTrue(isOutdated("0.4.9"))
        assertTrue(isOutdated("0.5.0"))
        assertTrue(isOutdated("0.5.9"))
        assertTrue(isOutdated("0.6.0"))
        assertTrue(isOutdated("0.6.9"))
        // 0.7.x no trae `walkthrough draft --porcelain`: mandarselo seria un
        // `unknown option`, o sea el borrador que no se escribe.
        assertTrue(isOutdated("0.7.0"))
        assertTrue(isOutdated("0.7.9"))
        assertFalse(isOutdated("0.8.1"))
        assertTrue(isOutdated("garbage"))
    }
}
