package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class MiscDomainTest {
    @Test
    fun mutationLockDiscardsSecond() {
        val lock = MutationLock()
        var discarded = false
        lock.onDidDiscard { discarded = true }
        val first = lock.run {
            val second = lock.run { 2 }
            assertNull(second)
            1
        }
        assertEquals(1, first)
        assertTrue(discarded)
        assertFalse(lock.isBusy)
    }

    @Test
    fun staleGuard() {
        val state = ReviewState(
            situation = Situation.REVIEW,
            state = StateRecord("review/f", "f", "tip1", ReviewMode.WHOLE, WalkthroughStatus.NONE),
        )
        val token = captureToken(state)
        assertTrue(tokenStillValid(token, state))
        assertFalse(
            tokenStillValid(
                token,
                state.copy(state = state.state!!.copy(tip = "tip2")),
            ),
        )
    }

    @Test
    fun soleTarget() {
        assertNull(pickSoleTarget(emptyList<String>()))
        assertEquals("a", pickSoleTarget(listOf("a")))
        assertNull(pickSoleTarget(listOf("a", "b")))
    }

    @Test
    fun cliProbe() {
        assertTrue(shouldProbeCli(Situation.CLI_MISSING, true))
        assertFalse(shouldProbeCli(Situation.CLI_MISSING, false))
        assertFalse(shouldProbeCli(Situation.REVIEW, true))
        assertEquals(10_000, CLI_PROBE_INTERVAL_MS)
    }

    @Test
    fun sourcePreference() {
        assertEquals(ReviewSource.REMOTE, resolveDefaultSource(SourcePreferenceLevels()))
        assertEquals(
            ReviewSource.LOCAL,
            resolveDefaultSource(SourcePreferenceLevels(workspaceValue = "local", globalValue = "offline")),
        )
        assertEquals(
            ReviewSource.OFFLINE,
            resolveDefaultSource(SourcePreferenceLevels(globalValue = "offline")),
        )
    }

    @Test
    fun installHint() {
        assertEquals(NPM_INSTALL_CMD, npmCommandFor(CliInstallKind.INSTALL))
        assertEquals(NPM_UPDATE_CMD, npmCommandFor(CliInstallKind.UPDATE))
    }

    @Test
    fun startFailure() {
        assertEquals(
            StartFailureCategory.NETWORK,
            classifyStartFailure("fatal: Could not resolve host github.com"),
        )
        assertEquals(
            StartFailureCategory.REPOSITORY,
            classifyStartFailure("error: working tree is dirty"),
        )
    }

    @Test
    fun finishOutcome() {
        val pending = ReviewState(
            situation = Situation.FINISH_PENDING,
            branches = listOf(
                BranchRecord(
                    "review-fixes/f",
                    saved = false,
                    current = true,
                    orphan = false,
                    finish = BranchFinish("pending", false),
                ),
            ),
        )
        assertEquals(FinishOutcome.PENDING, finishOutcome(pending, "review-fixes/f"))
        assertEquals(FinishOutcome.NO_EDITS, finishOutcome(pending, "other"))
    }

    @Test
    fun entryArg() {
        val entries = listOf(EntryRecord(1, "a"), EntryRecord(2, "b"))
        assertEquals(entries[1], resolveEntryArg(null, entries, 2))
        assertEquals(entries[0], resolveEntryArg(entries[0], entries, 2))
        assertNull(resolveEntryArg("nope", entries, 1))
    }

    @Test
    fun layoutOffersFallback() {
        val items = buildLayoutItems(null)
        assertEquals(2, items.size)
        assertEquals(ReviewLayout.STEP, items[0].layout)
    }

    @Test
    fun cliLogFormat() {
        assertEquals("git review status", formatCommandLine("git", listOf("review", "status")))
        assertTrue(shellQuoteArg("a b").startsWith("\""))
        val end = formatCliEnd(CliLogEnd(0, durationMs = 12, stderr = ""))
        assertEquals(listOf("← exit 0  12ms"), end)
    }

    @Test
    fun housekeepingArgs() {
        assertEquals(
            listOf("--keep-fixes", "f"),
            argsForHousekeeping(HousekeepingAction(HousekeepingKind.CLEAN_KEEP_FIXES, "f")),
        )
        assertTrue(housekeepingNeedsNetwork(HousekeepingAction(HousekeepingKind.FORGET_DELTA_STALE)))
    }
}
