package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test

class CommentsTest {
    @Test fun copyPathBelongsOnlyToExistingLocalDocumentsInEveryContext() {
        for (kind in listOf("review", "compare")) for (state in listOf("active", "result", "repository")) {
            val report = parseComments("comments-context\tc\t$kind\t$state\tg\tFeature\ncomments-document\t/absent\tc\tlocal\tabsent\tabsent\ncomments-document\t/local\tc\tlocal\tpresent\tunreadable\ncomments-document\t/shared\tc\tshared\tpresent\ts")
            val base = if (state == "active") com.ezevillo.gitreview.fixtures.PanelFixtures.reviewWhole() else com.ezevillo.gitreview.fixtures.PanelFixtures.noReviewReady()
            val model = base.copy(comments = report)
            val controls = panelLayout(model).collectControls()
            val copy = controls.single { it.id == ControlId.COPY_COMMENT_PATH }
            assertEquals(1, copy.index)
            assertEquals(Emphasis.ICON, copy.emphasis)
            assertEquals("Copy path", copy.accessibleName)
            assertEquals("Copy this document's path", copy.tooltip)
            assertTrue(copy.enabled)
            assertEquals(ControlId.OPEN_COMMENTS, controls[controls.indexOf(copy) - 1].id)
            assertFalse(panelLayout(model.copy(busy = true)).collectControls().single { it.id == ControlId.COPY_COMMENT_PATH }.enabled)
        }
    }
    @Test fun mainPanelKeepsIndependentEmptyStatesAfterReading() {
        val base = com.ezevillo.gitreview.fixtures.PanelFixtures.noReviewReady()
        for (setup in listOf(false, true)) {
            val layout = panelLayout(base.copy(noBaseConfigured = setup, comments = parseComments("")))
            val section = layout.blocks.filterIsInstance<Block.ToolsSection>().single { it.title == CommentsCopy.title }
            val rows = section.blocks.filterIsInstance<Block.GuideRows>().flatMap { it.rows }
            assertEquals(listOf("Local", "Shared"), rows.map { it.name })
            assertEquals(listOf("No local comments.", "No shared comments."), rows.map { it.badge })
            assertTrue(rows.all { it.controls.isEmpty() })
        }
    }
    @Test fun missingKindStaysVisibleBesideExistingDocumentWithoutChangingItsIndex() {
        for (kind in listOf("local", "shared")) {
            val report = parseComments("comments-context\tc\treview\tresult\tg\tFeature\ncomments-document\t/l\tc\tlocal\tabsent\tabsent\ncomments-document\t/s\tc\t$kind\tpresent\tr")
            val layout = panelLayout(com.ezevillo.gitreview.fixtures.PanelFixtures.noReviewReady().copy(comments = report))
            val section = layout.blocks.filterIsInstance<Block.ToolsSection>().single { it.title == CommentsCopy.title }
            val rows = section.blocks.filterIsInstance<Block.GuideRows>().flatMap { it.rows }
            assertEquals(2, rows.size)
            assertTrue(rows.any { it.badge == if (kind == "local") CommentsCopy.emptyShared else CommentsCopy.emptyLocal })
            assertEquals(1, layout.collectControls().single { it.id == ControlId.OPEN_COMMENTS }.index)
        }
    }
    @Test fun unreadAndFailedQueriesNeverClaimThereAreNoComments() {
        val base = com.ezevillo.gitreview.fixtures.PanelFixtures.noReviewReady()
        assertTrue(panelLayout(base).blocks.filterIsInstance<Block.ToolsSection>().none { it.title == CommentsCopy.title })
        val report = parseComments("comments-diagnostic\t\tread\tCannot read comments")
        val section = panelLayout(base.copy(comments = report)).blocks.filterIsInstance<Block.ToolsSection>().single { it.title == CommentsCopy.title }
        assertTrue(section.blocks.none { it is Block.GuideRows })
        assertEquals("Cannot read comments", section.blocks.filterIsInstance<Block.Stderr>().single().text)
    }
    @Test fun exactSelectionSurvivesCaptureWireAndHistoricalOffsets() {
        val text = "a😀\tZ\nlast"
        val coordinates = commentSelectionCoordinates(1, 0, 0, 1)
        assertEquals(CommentCoordinates(1, 2, 2, 1), coordinates)
        val capture = CommentCapture("file", "head", 1, 2, false, hasSelection = true, startColumn = 2, endColumn = 1)
        assertEquals(listOf("--path", "file", "--side", "head", "--start-line", "1", "--end-line", "2", "--start-column", "2", "--end-column", "1"), capture.locationArgs(CommentScope.SELECTION))
        assertFalse(capture.locationArgs(CommentScope.FILE).contains("--start-column"))
        val report = parseComments("comment-entry\t1\t1\t1\tfile\ncomment-scope\t1\tselection\thead\ncomment-path\t1\thead\tfile\ncomment-location\t1\thead\t1\t2\ncomment-columns\t1\thead\t2\t1")
        assertEquals("file:1:2–2:1 · New version", presentComment(report, report.records("comment-entry").single()).location)
        val columns = report.records("comment-columns").single()
        val offsets = commentTextOffsets(text, 1, 2, columns[2].toInt(), columns[3].toInt())
        assertEquals("😀\tZ\n", text.substring(offsets.first, offsets.second))
        assertEquals(1 to 3, commentTextOffsets(text, 1, 1, 2, 4))
        assertEquals(0 to 5, commentTextOffsets(text, 1, 1))
        assertThrows(IllegalArgumentException::class.java) { commentTextOffsets(text, 1, 1, 2, 9) }
        assertThrows(IllegalArgumentException::class.java) { commentTextOffsets(text, 1, 1, 2) }
    }
    @Test fun watchersUseOnlyTheTwoReportedDocumentParentsAndExactSaves() {
        val report=parseComments("comments-document\t/git/session/local.md\tc\tlocal\tabsent\tabsent\ncomments-document\t/git/result/shared.md\tc\tshared\tpresent\tr")
        val state=ReviewState(Situation.REVIEW,comments=report)
        assertEquals(setOf("/git/session","/git/result"),draftWatchDirs(state).toSet())
        assertTrue(isReportedGuide(report.documents.map {it.path},"/git/session/local.md"))
        assertFalse(isReportedGuide(report.documents.map {it.path},"/git/session/other.md"))
        assertTrue(draftWatchDirs(ReviewState(Situation.REVIEW)).isEmpty())
    }
    @Test fun resultsFollowWalkthroughAndKeepDocumentsIndependent() {
        val report=parseComments("comments-context\tc\treview\tresult\tg\tFeature\ncomments-document\t/l\tc\tlocal\tpresent\tl\ncomments-document\t/s\tc\tshared\tabsent\tabsent\ncomments-delivery\tc\tpending\tDestination changed")
        val layout=panelLayout(com.ezevillo.gitreview.fixtures.PanelFixtures.noReviewReady().copy(comments=report))
        val sections = layout.blocks.filterIsInstance<Block.ToolsSection>().map { it.title }
        assertTrue(sections.indexOf(CommentsCopy.title) > sections.indexOf("Walkthrough"))
        assertTrue(sections.indexOf(CommentsCopy.title) < sections.indexOf("Compare"))
        val controls=layout.collectControls()
        assertEquals(1,controls.count { it.id==ControlId.OPEN_COMMENTS })
        assertEquals(1,controls.count { it.id==ControlId.PREPARE_SHARED_COMMENTS })
        assertEquals(0,controls.count { it.id==ControlId.ADD_COMMENT })
    }
    @Test fun repositorySharedHasOnlyReadingControlsOutsideReview() {
        val report = parseComments("comments-context\tc\treview\trepository\tg\tFeature\ncomments-document\t/repo/.review/comments.md\tc\tshared\tpresent\ts")
        val layout = panelLayout(com.ezevillo.gitreview.fixtures.PanelFixtures.noReviewReady().copy(comments = report))
        val controls = layout.collectControls().map { it.id }
        assertTrue(ControlId.OPEN_COMMENTS in controls)
        assertTrue(ControlId.OPEN_COMMENT_DIFF in controls)
        assertFalse(ControlId.ADD_COMMENT in controls)
        assertFalse(ControlId.DELETE_COMMENTS in controls)
        assertFalse(ControlId.RENUMBER_COMMENTS in controls)
    }
    @Test fun sharedFixtureCoversEveryRecordAndExactCustody() {
        val text = java.io.File(System.getProperty("git.review.monorepo.root"), "tests/fixtures/comments/client-records.tsv").readText()
        val report = parseComments(text)
        assertEquals(4, report.documents.size)
        assertNull(report.documents[0].count); assertEquals(0, report.documents[1].count)
        val tags = report.rows.map { it.tag }.toSet()
        for (tag in listOf("comments-owner","comments-context","comments-guard","comments-document","comments-count","comments-diagnostic","comments-identity","comments-candidate","comments-delivery","comments-capture","comment-entry","comment-body","comment-scope","comment-version","comment-path","comment-location","comment-unversioned","comment-diagnostic","comment-diff","comment-blob","comments-delivery-file")) assertTrue(tag in tags, tag)
        assertFalse("future-tag" in tags)
        assertEquals(listOf("/private/local.md", "/private/shared.md"), commentsOwnedBy(report, setOf("review/feature/comments")).map { it.path })
        assertTrue(commentsOwnedBy(report,setOf("review/other")).isEmpty())
        assertEquals("old%2525name",report.records("comment-path").single()[2])
    }
    @Test fun activeDocumentsAppearIndividuallyAndDeleteUsesOriginalIndex() {
        val report = parseComments("comments-guard\tg\ncomments-context\tc\treview\tactive\tg\tFeature\ncomments-document\t/l\tc\tlocal\tabsent\tabsent\ncomments-document\t/s\tc\tshared\tpresent\tr\ncomments-count\t/s\t0")
        val layout = panelLayout(com.ezevillo.gitreview.fixtures.PanelFixtures.reviewWhole().copy(comments = report))
        val rows = layout.blocks.filterIsInstance<Block.GuideRows>().flatMap { it.rows }.filter { it.name in setOf(CommentsCopy.local, CommentsCopy.shared) }
        assertEquals(listOf(CommentsCopy.shared), rows.map { it.name })
        val deletes = layout.collectControls().filter { it.id == ControlId.DELETE_COMMENTS }
        assertEquals(listOf(1), deletes.map { it.index })
        assertTrue(requiresConfirmation(ControlId.DELETE_COMMENTS))
        assertTrue(layout.collectControls().none { it.id == ControlId.INIT_COMMENTS })
        assertEquals(listOf("delete", "--document", "shared", "--context", "c", "--expect-context", "g", "--expect-document", "r"), commentsArgv(report, "delete", "shared", "c"))
    }
    @Test fun retainedResultsHaveDeleteControl() {
        val report=parseComments("comments-context\tc\treview\tresult\tg\tFeature\ncomments-document\t/l\tc\tlocal\tpresent\tr")
        val layout=panelLayout(com.ezevillo.gitreview.fixtures.PanelFixtures.noReviewReady().copy(comments=report))
        assertEquals(1,layout.collectControls().count { it.id==ControlId.DELETE_COMMENTS })
        assertEquals(1,layout.collectControls().count { it.id==ControlId.OPEN_COMMENTS })
    }
    private val wire = "comments-guard\tstep1\ncomments-context\tc1\treview\tactive\tstep1\tFeature\ncomments-context\tc2\tcompare\tresult\tg2\tOther\ncomments-document\t/l\tc1\tlocal\tpresent\tunreadable\ncomments-document\t/s\tc1\tshared\tabsent\tabsent\textra\ncomments-diagnostic\t/l\tread\tCannot read\ncomments-count\t/s\t0\ncomments-count\t/l\tbad\ncomments-delivery\tc1\tpending\tChanged\nfuture-tag\tignored"
    @Test fun documentsStayIndependentAndUnreadableIsNotZero() {
        val report = parseComments(wire)
        assertEquals("step1", report.guard)
        assertEquals(listOf("c1", "c2"), report.records("comments-context").map { it[0] })
        assertEquals(listOf("local", "shared"), report.documents.map { it.kind })
        assertNull(report.documents[0].count)
        assertEquals(0, report.documents[1].count)
        assertEquals("unreadable", report.documents[0].revision)
        assertEquals("pending", report.records("comments-delivery").single()[1])
    }
    @Test fun physicalOrdinalIsIndependentOfVisibleNumber() {
        val report = parseComments("comment-entry\t2\t7\t12\tSecond\ncomment-entry\t1\t7\t2\tFirst\ncomment-diff\t2\tB1\tH1\ncomment-blob\told\tbase\tpresent\tblob1\ncomment-blob\tnew\thead\tabsent")
        assertEquals(listOf("2", "1"), report.records("comment-entry").map { it[0] })
        assertEquals(listOf("2", "B1", "H1"), report.records("comment-diff").single())
        assertEquals("absent", report.records("comment-blob")[1][2])
    }
}
