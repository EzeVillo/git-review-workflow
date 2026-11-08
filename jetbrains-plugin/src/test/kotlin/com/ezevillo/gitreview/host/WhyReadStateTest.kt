package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.*
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test

class WhyReadStateTest {
    private fun owner() = StateRecord("review/x", "x", "deadbeef", ReviewMode.WALK, WalkthroughStatus.APPLIED)

    @Test fun completionCannotOverwriteAReadThatSupersededIt() {
        val state = WhyReadState()
        val first = owner()
        val old = state.begin(first, PanelWhy(WhyState.LOADING))
        val second = owner()
        val fresh = state.begin(second, PanelWhy(WhyState.LOADING))
        assertFalse(state.complete(old, PanelWhy(WhyState.PRESENT, text = "old")))
        assertNull(state.valueFor(first))
        assertEquals(WhyState.LOADING, state.valueFor(second)?.state)
        assertTrue(state.complete(fresh, PanelWhy(WhyState.PRESENT, text = "new")))
        assertEquals("new", state.valueFor(second)?.text)
        assertFalse(state.complete(old, PanelWhy(WhyState.FAILED)))
        assertEquals("new", state.valueFor(second)?.text)
    }

    @Test fun rereadingTheSameEntryStillInvalidatesAnEarlierRequest() {
        val state = WhyReadState()
        val owner = owner()
        val old = state.begin(owner, PanelWhy(WhyState.LOADING))
        state.begin(owner, PanelWhy(WhyState.LOADING))
        assertFalse(state.complete(old, PanelWhy(WhyState.PRESENT, text = "outdated draft")))
        assertEquals(WhyState.LOADING, state.valueFor(owner)?.state)
    }
}
