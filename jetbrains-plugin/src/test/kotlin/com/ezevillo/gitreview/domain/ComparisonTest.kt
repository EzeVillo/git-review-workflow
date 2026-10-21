package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test

class ComparisonTest {
    @Test fun pinnedEndpointsSurviveEveryModelProjection() {
        for (mode in listOf("whole", "walk", "step")) {
            val p = parsePorcelain(listOf(
                "state\treview/f\tf\t${"2".repeat(40)}\t$mode\tnone\t1\t1\t1\tapp.txt\t0",
                "comparison-target\trefs/remotes/upstream/f",
                "comparison\t${"1".repeat(40)}\t${"2".repeat(40)}",
                "comparison-base\trefs/heads/main",
            ).joinToString("\n"))
            val m = buildPanelModel(ReviewState(Situation.REVIEW, state = p.state, comparison = p.comparison), PanelInputs(false))
            assertNotNull(m.comparison)
            assertEquals(listOf("Base: main (1111111)", "Inspect: upstream/f (2222222)"), UserCopy.comparisonLines(m.comparison!!))
        }
        assertNull(parsePorcelain("state\treview/f\tf\tabc\twhole\tnone\ncomparison\tbad\tbad").comparison)
    }
}
