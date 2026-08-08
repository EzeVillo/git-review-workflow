package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class UnquoteTest {
    @Test
    fun plainPathUnchanged() {
        assertEquals("src/main.kt", unquotePath("src/main.kt"))
    }

    @Test
    fun unquoteEscapedQuoteAndBackslash() {
        assertEquals("""a"b\c""", unquotePath("\"a\\\"b\\\\c\""))
    }

    @Test
    fun unquoteOctalUtf8() {
        // "caf\303\251" → café
        val raw = "\"caf\\303\\251\""
        assertEquals("café", unquotePath(raw))
    }

    @Test
    fun toPathRefKeepsRaw() {
        val ref = toPathRef("\"foo bar\"")
        assertEquals("\"foo bar\"", ref.raw)
        assertEquals("foo bar", ref.display)
    }
}
