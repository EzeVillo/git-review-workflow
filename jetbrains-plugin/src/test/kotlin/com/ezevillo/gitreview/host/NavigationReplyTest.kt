package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.*
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class NavigationReplyTest {
    @Test fun inlineProsePreservesEscapesAndKeepsInvalidOrMissingDataUnknown() {
        val wire = "why\tpresent\t3\nwhy-line\t1\tcafé \\t \\\\n\nwhy-line\t2\t\nwhy-line\t3\tA\\rB  \n"
        assertEquals("café \t \\n\n\nA\rB  \n",parseInlineWhy(wire))
        assertEquals("",parseInlineWhy("why\tabsent\t0\n"))
        for (bad in listOf("", "why\tabsent\t1", "why\tpresent\t0", "why\tpresent\t2\nwhy-line\t1\tone",
            "why\tpresent\t1\nwhy-line\t2\tone", "why\tpresent\t1\nwhy-line\t1\tbad\\x",
            "why\tpresent\t1\nwhy-line\t1\tbad\\", "why\tabsent\t0\nwhy\tabsent\t0")) assertNull(parseInlineWhy(bad),bad)
    }

    @Test fun navigationCarriesTheProseInTheSameStatePublishedBeforeComments() {
        val cli = FakeCliRunner()
        val manager = ReviewStateManager(cli) {null}
        manager.refreshPrimary("/repo",reply()+"why\tpresent\t1\nwhy-line\t1\tfrom this snapshot\n")
        assertEquals("from this snapshot\n",manager.current.inlineWhy)
        assertEquals(WhyState.PRESENT,whyFromText(manager.current.inlineWhy!!).state)
        assertTrue(cli.calls.isEmpty())
    }
    private fun reply(guard: String = "a".repeat(40), position: Int = 1) =
        "state\treview/feature\tfeature\tdeadbeef\twalk\tapplied\t$position\t2\t2\ta.txt\t0\n" +
            "entry\t1\ta.txt\t0\t1\nentry\t2\tb.txt\t0\t1\n" +
            "capability\tnavigation-state\nguard\t$guard\nnavigation\tmoved\n"

    @Test fun navigationPublishesItsReplyWithoutAnotherVersionStatusOrCommentsRead() {
        val cli = FakeCliRunner()
        val manager = ReviewStateManager(cli) { null }
        val pending = manager.refreshPrimary("/repo", reply())
        assertTrue(cli.calls.isEmpty())
        assertEquals(1, manager.current.state?.position)
        assertTrue(manager.current.navigationState)
        assertTrue(manager.current.comments?.loading == true)
        manager.completeComments(pending)
        assertEquals(listOf("comments"), cli.verbs)
        assertFalse(manager.current.comments!!.loading)
    }

    @Test fun commentsFromAnEarlierNavigationCannotOverwriteTheNewerCursor() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val cli = object : CliRunner {
            override fun invoke(verb: String, args: List<String>, cwd: String, network: Boolean, timeoutMs: Long): InvokeResult {
                assertEquals("comments", verb)
                entered.countDown()
                check(release.await(5, TimeUnit.SECONDS))
                return InvokeResult("", "", 0)
            }
        }
        val manager = ReviewStateManager(cli) { null }
        val old = manager.refreshPrimary("/repo", reply())
        val thread = Thread { manager.completeComments(old) }
        thread.start()
        try {
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            manager.refreshPrimary("/repo", reply("b".repeat(40), 2))
            release.countDown()
            thread.join(5000)
            assertFalse(thread.isAlive)
            assertEquals(2, manager.current.state?.position)
            assertEquals("b".repeat(40), manager.current.guard)
            assertTrue(manager.current.comments?.loading == true)
        } finally { release.countDown(); thread.join(5000) }
    }

    @Test fun invalidOrOldRepliesUseTheFullPrimaryRead() {
        val cli = FakeCliRunner().answer("status", reply())
        val manager = ReviewStateManager(cli) { null }
        manager.refreshPrimary("/repo", reply().replace("navigation\tmoved", "navigation\tunknown"))
        assertEquals(listOf("--version", "status"), cli.verbs)
        assertFalse(isNavigationReply(reply() + "navigation\tmoved\n"))
        assertFalse(isNavigationReply(reply().replace("capability\tnavigation-state\n", "")))
        assertFalse(isNavigationReply(reply().replace("guard\t" + "a".repeat(40), "guard\tbad")))
    }
}
