package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class DraftWatchTest {
    private fun draft(path: String) = DraftRecord(
        src = "x",
        path = path,
        annotated = 0,
        total = 1,
        source = DraftSource.REMOTE,
        range = DraftRange.FULL,
        state = DraftState.FRESH,
    )

    private fun state(draftPath: String? = null, drafts: List<DraftRecord>? = null) =
        ReviewState(situation = Situation.NO_REVIEW, draftPath = draftPath, drafts = drafts)

    @Test
    fun nothingToWatchWithoutDrafts() {
        assertEquals(emptyList<String>(), draftWatchDirs(state()))
        assertEquals(emptyList<String>(), draftWatchDirs(state(drafts = emptyList())))
    }

    @Test
    fun oneDirectoryPerReportedPath() {
        assertEquals(
            listOf("/repo/.git/review-walkthrough", "/repo/.git/review-walkthrough/feature"),
            draftWatchDirs(
                state(
                    drafts = listOf(
                        draft("/repo/.git/review-walkthrough/feature/checkout.md"),
                        draft("/repo/.git/review-walkthrough/telemetry.md"),
                    ),
                ),
            ),
        )
    }

    @Test
    fun theActiveReviewDraftCountsToo() {
        assertEquals(
            listOf("/repo/.git/review-walkthrough/feature"),
            draftWatchDirs(state(draftPath = "/repo/.git/review-walkthrough/feature/x.md")),
        )
    }

    @Test
    fun oneDirectoryEvenWhenBothReportIt() {
        assertEquals(
            listOf("/repo/.git/review-walkthrough/feature"),
            draftWatchDirs(
                state(
                    draftPath = "/repo/.git/review-walkthrough/feature/x.md",
                    drafts = listOf(
                        draft("/repo/.git/review-walkthrough/feature/x.md"),
                        draft("/repo/.git/review-walkthrough/feature/y.md"),
                    ),
                ),
            ),
        )
    }

    @Test
    fun orderIsStableNotOrderOfAppearance() {
        val one = draftWatchDirs(state(drafts = listOf(draft("/r/b/x.md"), draft("/r/a/y.md"))))
        val other = draftWatchDirs(state(drafts = listOf(draft("/r/a/y.md"), draft("/r/b/x.md"))))
        assertEquals(listOf("/r/a", "/r/b"), one)
        assertEquals(one, other)
    }

    @Test
    fun windowsSeparatorsAreNormalised() {
        assertEquals(
            listOf("C:/repo/.git/review-walkthrough/feature"),
            draftWatchDirs(state(draftPath = "C:\\repo\\.git\\review-walkthrough\\feature\\x.md")),
        )
    }

    @Test
    fun aPathThatNamesNoDirectoryIsDropped() {
        assertEquals(emptyList<String>(), draftWatchDirs(state(draftPath = "")))
        assertEquals(emptyList<String>(), draftWatchDirs(state(draftPath = "   ")))
        assertEquals(emptyList<String>(), draftWatchDirs(state(draftPath = "x.md")))
        assertEquals(emptyList<String>(), draftWatchDirs(state(draftPath = "/x.md")))
    }

    @Test
    fun onlyMarkdownInsideAWatchedDirectory() {
        val dirs = listOf("/repo/.git/review-walkthrough/feature")
        assertTrue(isDraftFileEvent(dirs, "/repo/.git/review-walkthrough/feature/x.md"))
        // A sibling directory the CLI never reported is not ours.
        assertFalse(isDraftFileEvent(dirs, "/repo/.git/review-walkthrough/other/x.md"))
        // Nor is anything deeper, nor a non-markdown file git drops there.
        assertFalse(isDraftFileEvent(dirs, "/repo/.git/review-walkthrough/feature/deep/x.md"))
        assertFalse(isDraftFileEvent(dirs, "/repo/.git/review-walkthrough/feature/x.md.lock"))
        assertFalse(isDraftFileEvent(emptyList(), "/repo/.git/review-walkthrough/feature/x.md"))
    }

    @Test
    fun theMatchIgnoresCaseAndSeparators() {
        val dirs = listOf("C:/Repo/.git/review-walkthrough")
        assertTrue(isDraftFileEvent(dirs, "c:/repo/.git/review-walkthrough/x.MD"))
        assertTrue(isDraftFileEvent(dirs, "C:\\Repo\\.git\\review-walkthrough\\x.md"))
    }
}
