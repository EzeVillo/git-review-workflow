package com.ezevillo.gitreview.host

import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test

class RefreshGateTest {
    @Test fun signalsDuringMutationAreCoveredByItsFinalRead() {
        val gate = RefreshGate()
        gate.mutationChanged(true)
        repeat(4) { gate.request(); assertFalse(gate.tryStart()) }
        gate.primaryStarting()
        gate.mutationChanged(false)
        assertFalse(gate.tryStart())
    }

    @Test fun aChangeAfterThePrimaryStartsGetsOneFollowupWithoutParallelReads() {
        val gate = RefreshGate()
        gate.mutationChanged(true)
        gate.primaryStarting()
        repeat(4) { gate.request() }
        assertFalse(gate.tryStart())
        gate.mutationChanged(false)
        assertTrue(gate.tryStart())
        assertFalse(gate.tryStart())
        gate.finished()
        assertFalse(gate.tryStart())
    }

    @Test fun abortingWithoutAPrimaryAndQueuedOrInflightReadsKeepTheirSignals() {
        val gate = RefreshGate()
        gate.request()
        gate.mutationChanged(true)
        assertFalse(gate.tryStart())
        gate.mutationChanged(false)
        assertTrue(gate.tryStart())
        gate.request()
        gate.mutationChanged(true)
        gate.finished()
        assertFalse(gate.tryStart())
        gate.mutationChanged(false)
        assertTrue(gate.tryStart())
        gate.request()
        assertFalse(gate.tryStart())
        gate.finished()
        assertTrue(gate.tryStart())
    }
}
