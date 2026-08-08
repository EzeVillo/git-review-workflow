package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class ConfigPorcelainTest {
    @Test
    fun parseFull() {
        val out = """
            config	base	main
            config	remote	origin
            candidate	feature	remote	1
            candidate	feature	local	0
            remote-candidate	origin	1
            delta	feature	abc	remote
            offer	walk	recommended
            offer	step	available
        """.trimIndent()
        val r = parseConfigPorcelain(out)
        assertEquals("main", r.config.base)
        assertEquals("origin", r.config.remote)
        assertEquals(2, r.candidates.size)
        assertEquals(1, r.remotes.size)
        assertEquals(1, r.deltas?.size)
        assertEquals(2, r.offers?.size)
        assertEquals("abc", deltaForSource(r.deltas, "remote")?.tip)
        assertNull(deltaForSource(r.deltas, "local"))
    }

    @Test
    fun remoteDefaultsToOrigin() {
        val r = parseConfigPorcelain("")
        assertEquals("origin", r.config.remote)
        assertNull(r.config.base)
    }
}
