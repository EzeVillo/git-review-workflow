package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class NameStatusTest {
    @Test
    fun addModifyDelete() {
        val out = "A\u0000new.kt\u0000M\u0000edit.kt\u0000D\u0000gone.kt\u0000"
        val c = parseNameStatus(out)
        assertEquals(3, c.size)
        assertNull(c[0].before)
        assertEquals("new.kt", c[0].after)
        assertEquals("edit.kt", c[1].before)
        assertEquals("edit.kt", c[1].after)
        assertEquals("gone.kt", c[2].before)
        assertNull(c[2].after)
    }

    @Test
    fun rename() {
        val out = "R100\u0000old.kt\u0000new.kt\u0000"
        val c = parseNameStatus(out)
        assertEquals(1, c.size)
        assertEquals("new.kt", c[0].path)
        assertEquals("old.kt", c[0].before)
        assertEquals("new.kt", c[0].after)
    }
}
