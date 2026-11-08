package com.ezevillo.gitreview.host
import com.ezevillo.gitreview.domain.*
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test

class SaveReplyTest {
    private val wire = "save-state\t1\nstatus\t2\nlist\tbranch\treview-saved/feature\t1\t0\t0\twalk\t2\t3\nconfig\tconfig\tbase\tmain\nconfig\tconfig\tremote\torigin\nsave-state\tcomplete\n"
    @Test fun publishesTheFinalSavedReviewWithoutAnyPrimaryQueries() {
        val cli = FakeCliRunner()
        val manager = ReviewStateManager(cli) { null }
        val pending = manager.refreshPrimary("/repo", wire)
        assertTrue(cli.calls.isEmpty())
        assertEquals(Situation.NO_REVIEW, manager.current.situation)
        assertTrue(manager.current.branches.single().saved)
        assertEquals(2, manager.current.branches.single().position)
        assertEquals("main", manager.current.config?.base)
        assertTrue(manager.current.comments?.loading == true)
        manager.completeComments(pending)
        assertEquals(listOf("comments"), cli.verbs)
    }
    @Test fun malformedOrIncompleteResponsesFallBackWithoutRepeatingSave() {
        for (bad in listOf("", wire.replace("save-state\tcomplete\n", ""), wire + "save-state\tcomplete\n",
            wire.replace("status\t2", "status\t0"), wire.replace("list\tbranch", "unknown\tbranch"),
            wire.replace("config\tconfig\tremote\torigin\n", ""))) {
            assertNull(parseSaveReply(bad))
            val cli = FakeCliRunner().answer("status", "", 2)
            ReviewStateManager(cli) { null }.refreshPrimary("/repo", bad)
            assertEquals(listOf("--version", "status", "list", "config"), cli.verbs)
        }
        assertNotNull(parseSaveReply(wire.replace("\n", "\r\n")))
        assertTrue(hasSaveState("capability\tsave-state\n"))
        assertFalse(hasSaveState("capability\tsave-state\ncapability\tsave-state\n"))
    }
}
