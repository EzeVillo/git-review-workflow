package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.*
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test

class ContinueReplyTest {
    private val guard = "a".repeat(40)
    private val body = "state\treview/feature\tfeature\tdeadbeef\twhole\tnone\ncapability\tsave-state\nguard\t$guard\n"
    private val wire = "continue-state\t1\n${body}continue-state\tcomplete\n"
    private val inventory = "capability\tcontinue-state\ncontinue-guard\t$guard\nbranch\treview-saved/feature\t1\t0\t0\twhole\n"

    @Test fun completeReplyPublishesWithoutPrimaryQueriesAndPreservesCapabilities() {
        val cli = FakeCliRunner()
        val manager = ReviewStateManager(cli) { null }
        val pending = manager.refreshPrimary("/repo",wire)
        assertTrue(cli.calls.isEmpty())
        assertEquals(Situation.REVIEW,manager.current.situation)
        assertEquals(guard,manager.current.guard)
        assertTrue(manager.current.saveState)
        assertTrue(manager.current.comments?.loading == true)
        manager.completeComments(pending)
        assertEquals(listOf("comments"),cli.verbs)
    }
    @Test fun onlyContinueMaySkipAnInactivePreflightWithTheInventoryToken() {
        val cli = FakeCliRunner().answer("status","",2).answer("list",inventory)
        val manager = ReviewStateManager(cli) { null }
        manager.refresh("/repo")
        assertEquals(guard,manager.current.continueGuard)
        val token = captureToken(manager.current)
        assertFalse(tokenStillValid(token,manager.current.copy(continueGuard="b".repeat(40))))
        cli.calls.clear()
        manager.readForMutation("/repo",continueAction=true)
        assertTrue(cli.calls.isEmpty())
        manager.readForMutation("/repo")
        assertEquals(listOf("--version","status","list","config"),cli.verbs)
    }
    @Test fun ambiguousGuardsAndIncompleteRepliesKeepTheLegacyRead() {
        assertEquals(guard,parseContinueGuard(inventory.replace("\n","\r\n")))
        for (bad in listOf("",inventory+inventory,inventory.replace(guard,"bad"),inventory.replace(guard,guard+" "),inventory.replace("capability\tcontinue-state\n",""))) assertNull(parseContinueGuard(bad))
        assertTrue(isContinueReply(wire.replace("\n","\r\n")))
        for (bad in listOf("",body,wire.replace("continue-state\tcomplete\n",""),wire+"continue-state\tcomplete\n",wire.replace(body,body+body),wire.replace("review/feature","main"))) {
            assertFalse(isContinueReply(bad))
            val cli = FakeCliRunner().answer("status","",2)
            ReviewStateManager(cli) { null }.refreshPrimary("/repo",bad)
            assertEquals(listOf("--version","status","list","config"),cli.verbs)
        }
    }
}
