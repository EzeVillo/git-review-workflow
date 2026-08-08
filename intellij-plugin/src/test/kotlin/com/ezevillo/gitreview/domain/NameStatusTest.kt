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

    /**
     * Documents the contract for callers: output must use `--no-commit-id`.
     * Without it, the first field is the full SHA and the first path becomes
     * the status letter "M" — the empty-pane "file M" bug in step Diff.
     */
    @Test
    fun leadingCommitIdCorruptsPaths() {
        val sha = "87aaafe84f16d9376bc57f08ab2e5ff1dbc0b588"
        val out = "$sha\u0000M\u0000src/edit.kt\u0000"
        val c = parseNameStatus(out)
        assertEquals(1, c.size)
        assertEquals("M", c[0].path)
        assertEquals("M", c[0].before)
        assertEquals("M", c[0].after)
    }

    @Test
    fun withoutLeadingCommitIdModifyIsPath() {
        val out = "M\u0000src/edit.kt\u0000"
        val c = parseNameStatus(out)
        assertEquals(1, c.size)
        assertEquals("src/edit.kt", c[0].path)
        assertEquals("src/edit.kt", c[0].before)
        assertEquals("src/edit.kt", c[0].after)
    }
}
