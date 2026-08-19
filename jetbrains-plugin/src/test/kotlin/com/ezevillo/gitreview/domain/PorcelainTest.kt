package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PorcelainTest {
    @Test
    fun parseWholeStatus() {
        val out = """
            state	review/feature	feature	abc123	whole	none
            entry	1	src/a.kt
            entry	2	src/b.kt
            base	main
        """.trimIndent()
        val r = parsePorcelain(out)
        assertEquals(ReviewMode.WHOLE, r.state.mode)
        assertEquals(2, r.entries.size)
        assertEquals("main", r.base)
        assertTrue(r.entries[0].id is PathRef)
    }

    @Test
    fun parseWalkStatus() {
        val out = """
            state	review/feature	feature	deadbeef	walk	applied	2	5	5	"src/foo.kt"	1
            entry	1	src/a.kt	0	1
            entry	2	"src/foo.kt"	1	1
            keys
        """.trimIndent()
        val r = parsePorcelain(out)
        assertEquals(ReviewMode.WALK, r.state.mode)
        assertEquals(2, r.state.position)
        assertEquals(true, r.state.essential)
        assertEquals(true, r.keysOnly)
        assertNull(r.draft)
        assertTrue((r.entries[1].id as PathRef).display.contains("foo"))
    }

    /** 011: registro de presencia, sin campos; no desplaza nada del resto. */
    @Test
    fun parseWalkStatusOnTheReviewersDraft() {
        val out = """
            state	review/feature	feature	deadbeef	walk	applied	2	5	5	"src/foo.kt"	0
            entry	1	src/a.kt	0	1
            entry	2	"src/foo.kt"	0	1
            draft
        """.trimIndent()
        val r = parsePorcelain(out)
        assertEquals(true, r.draft)
        assertNull(r.keysOnly)
        assertEquals(ReviewMode.WALK, r.state.mode)
        assertEquals(2, r.state.position)
        assertEquals(5, r.state.total)
        assertEquals(2, r.entries.size)
    }

    @Test
    fun draftAndKeysCoexist() {
        val out = """
            state	review/feature	feature	deadbeef	walk	applied	1	1	1	src/a.kt	1
            entry	1	src/a.kt	1	1
            keys
            draft
        """.trimIndent()
        val r = parsePorcelain(out)
        assertEquals(true, r.draft)
        assertEquals(true, r.keysOnly)
    }

    @Test
    fun parseStepWithSubjectTab() {
        val out = "state\treview/f\tf\tabc\tstep\tnone\t1\t2\t2\tabc1234\n" +
            "entry\t1\tabc1234\t0\n" +
            "subject\t1\tfix with\ttab\n" +
            "author\t1\tAda\n"
        val r = parsePorcelain(out)
        assertEquals("fix with\ttab", r.subjects?.get(1))
        assertEquals("Ada", r.authors?.get(1))
    }

    @Test
    fun parseFinishConflict() {
        val out = """
            state	review/f	f	abc	whole	none
            finish	conflict	1
            readonly
        """.trimIndent()
        val r = parsePorcelain(out)
        assertEquals(true, r.finish?.onto)
        assertEquals(true, r.readonly)
    }

    @Test
    fun parseListAndSourceOf() {
        val out = """
            branch	review-saved/feature	1	0	0	walk	3	5
            finish	review-saved/feature	pending	0
            branch	review/other	0	1	0	step	1	2
        """.trimIndent()
        val branches = parseListPorcelain(out)
        assertEquals(2, branches.size)
        assertEquals("feature", sourceOf(branches[0]))
        assertEquals("pending", branches[0].finish?.state)
        assertTrue(branches[0].saved)
        assertFalse(branches[1].saved)
    }

    @Test
    fun emptyListIsValid() {
        assertTrue(parseListPorcelain("").isEmpty())
    }

    // --- el campo de ruta del registro draft (012) -------------------------------

    @Test
    fun theDraftRecordCarriesTheAbsolutePathOfTheDraftInForce() {
        val out = """
            state	review/feature	feature	deadbeef	walk	applied	1	1	1	src/a.kt	0
            entry	1	src/a.kt	0	1
            draft	/repo/.git/review-walkthrough/feature.md
        """.trimIndent()
        val r = parsePorcelain(out)
        assertEquals(true, r.draft)
        assertEquals("/repo/.git/review-walkthrough/feature.md", r.draftPath)
    }

    @Test
    fun aDraftRecordWithoutItsFieldStillMarksTheDraft() {
        // Una CLI anterior a 012 emite el registro pelado, y eso no puede apagar
        // la marca: la presencia es la presencia.
        val out = """
            state	review/feature	feature	deadbeef	walk	applied	1	1	1	src/a.kt	0
            entry	1	src/a.kt	0	1
            draft
        """.trimIndent()
        val r = parsePorcelain(out)
        assertEquals(true, r.draft)
        assertNull(r.draftPath)
    }
}
