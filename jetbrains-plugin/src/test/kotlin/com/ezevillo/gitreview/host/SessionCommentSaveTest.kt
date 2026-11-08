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
    @Test fun activeClosuresUseOnlyValidatedSessionPathsAndLegacyStaysExplicit() {
        val guard = "a".repeat(40)
        val current = state.copy(guard = guard, commentsPaths = true)
        val wire = "comments-paths\t1\t$guard\t${"b".repeat(40)}\ncomments-path\tlocal\t/private.md\ncomments-path\tshared\t/shared.md\ncomments-paths\tcomplete\n"
        for (action in listOf("saveReview", "abortReview", "finishReview", "undoFinish", "resumeFinish")) {
            val cli = FakeCliRunner().answer("comments", wire)
            var paths = emptyList<String>()
            assertTrue(saveSessionComments(cli,"/repo",current,action,ActionParams.Empty,{true}) { paths=it; true })
            assertEquals(listOf("paths","--porcelain"),cli.calls.single().args)
            assertEquals(listOf("/private.md","/shared.md"),paths)
        }
        for (bad in listOf(wire.replace("complete", "truncated"), wire.replace(guard,"c".repeat(40)), wire+"comments-paths\tcomplete\n")) {
            val cli = FakeCliRunner().answer("comments",bad)
            assertFalse(saveSessionComments(cli,"/repo",current,"saveReview",ActionParams.Empty,{true}) { error("must not save") })
        }
        val legacy = FakeCliRunner().answer("comments", "comments-paths\t1\t$guard\tlegacy\ncomments-paths\tcomplete\n")
        assertTrue(saveSessionComments(legacy,"/repo",current,"saveReview",ActionParams.Empty,{true}) { true })
        assertEquals(listOf(listOf("paths","--porcelain"),listOf("status","--porcelain","--all")),legacy.calls.map { it.args })
    }
    @Test fun encodedPathsAreLiteralAndIncompleteReportsNeverAuthorizeSaving() {
        val guard="a".repeat(40)
        val wire="comments-paths\t1\t$guard\t${"b".repeat(40)}\ncomments-path\tlocal\t/Café + %252F%09%0D%0A%3E\ncomments-path\tshared\t/shared.md\ncomments-paths\tcomplete\n"
        assertEquals(listOf("/Café + %2F\t\r\n>","/shared.md"),parseCommentPaths(wire,guard)?.paths)
        assertNull(parseCommentPaths(wire.replace("%09","%GG"),guard))
        assertNull(parseCommentPaths(wire.replace("comments-path\tshared\t/shared.md\n",""),guard))
        assertTrue(hasCommentPaths("capability\tcomments-paths\n"))
        assertFalse(hasCommentPaths("capability\tcomments-paths\ncapability\tcomments-paths\n"))
    }

}
