package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.*
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test

class SessionCommentSaveTest {
    private val state = ReviewState(Situation.REVIEW, state = StateRecord("review/x", "x", "tip", ReviewMode.WHOLE, WalkthroughStatus.NONE))
    private val report = "comments-owner\tc\tx\treview/x\ncomments-document\t/private.md\tc\tlocal\tpresent\tr\n" +
        "comments-owner\tother\tother\treview/other\ncomments-document\t/other.md\tother\tlocal\tpresent\tr"

    @Test fun cleanEditorSkipsBothInventoryAndSaveWithoutChangingTheAction() {
        val cli = FakeCliRunner().fails("comments", "must not run")
        val saved = saveSessionComments(cli,"/repo",state,"abortReview",ActionParams.Empty,{false}) { throw AssertionError("must not save") }
        assertTrue(saved)
        assertTrue(cli.calls.isEmpty())
    }

    @Test fun dirtyOrUnknownEditorsStillResolveAndSaveOnlyTheOwnedDocuments() {
        for (dirty in listOf(true,null)) {
            val cli = FakeCliRunner().answer("comments",report)
            var paths = emptyList<String>()
            assertTrue(saveSessionComments(cli,"/repo",state,"finishReview",ActionParams.Empty,{dirty}) { paths = it; true })
            assertEquals(listOf("comments"),cli.verbs)
            assertEquals(listOf("status","--porcelain","--all"),cli.calls.single().args)
            assertEquals(listOf("/private.md"),paths)
        }
    }

    @Test fun uncertaintyFailuresAndSelectiveSaveFailuresCannotPretendTheBuffersWereSaved() {
        val cli = FakeCliRunner().answer("comments",report)
        assertTrue(saveSessionComments(cli,"/repo",state,"saveReview",ActionParams.Empty,{error("unknown")}) { true })
        assertEquals(listOf("comments"),cli.verbs)
        assertFalse(saveSessionComments(cli,"/repo",state,"saveReview",ActionParams.Empty,{true}) { false })
        cli.fails("comments","query failed")
        assertFalse(saveSessionComments(cli,"/repo",state,"saveReview",ActionParams.Empty,{true}) { throw AssertionError("must not save") })
    }
}
