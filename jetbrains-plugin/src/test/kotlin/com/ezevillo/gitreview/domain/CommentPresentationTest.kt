package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test

class CommentPresentationTest {
    @Test fun `prose preserves paragraphs and one layer of escapes on original side`() {
        val report = parseComments("comment-entry\t2\t7\t4\tFile\ncomment-scope\t2\tselection\tbase\ncomment-path\t2\tbase\told%25name\ncomment-location\t2\tbase\t3\t5\ncomment-body\t2\t    100%25 and %2509\ncomment-body\t2\t\ncomment-body\t2\tSecond%09paragraph")
        val view = presentComment(report, report.records("comment-entry").single())
        assertEquals("    100% and %09\n\nSecond\tparagraph", view.body)
        assertEquals("old%name:3–5 · Previous version", view.location)
        assertEquals(2, view.ordinal)
        assertTrue(view.canOpenDiff)
        assertEquals("7. File · old%name:3–5 · Previous version", view.label)
    }
    @Test fun `manual entry does not acquire general scope from missing metadata`() {
        val report = parseComments("comment-entry\t1\t1\t1\tManual\ncomment-entry\t2\t1\t4\tGeneral\ncomment-scope\t2\tgeneral\t\ncomment-body\t2\tWhole review")
        assertEquals(CommentsCopy.locationUnavailable, presentComment(report, report.records("comment-entry")[0]).location)
        assertFalse(presentComment(report, report.records("comment-entry")[0]).canOpenDiff)
        assertFalse(presentComment(report, report.records("comment-entry")[1]).canOpenDiff)
        assertEquals(CommentsCopy.general, presentComment(report, report.records("comment-entry")[1]).location)
    }

    @Test fun `long preview is bounded without losing prose or hiding warnings in history`() {
        val body = "🙂".repeat(161)
        val report = parseComments("comment-entry\t1\t1\t1\tsrc/file.kt\ncomment-scope\t1\tselection\thead\ncomment-path\t1\thead\tsrc/file.kt\ncomment-location\t1\thead\t3\t7\ncomment-version\t1\tabcdef123456\t123456abcdef\ncomment-unversioned\t1\ncomment-body\t1\t" + body)
        val view = presentComment(report, report.records("comment-entry").single())
        assertEquals(body, view.body)
        assertEquals("🙂".repeat(159) + "…", view.preview)
        assertEquals("1. src/file.kt:3–7 · New version", view.label)
        assertEquals("Original changes · abcdef12 → 123456ab", view.version)
        assertEquals(CommentsCopy.originalUnversioned, view.warning)
    }
}
