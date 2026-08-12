package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class ResolveCommandTest {
    @Test
    fun emptyPathUsesGitReview() {
        val r = resolveCommand("status", listOf("--porcelain"), null, "linux")
        assertEquals("git", r.command)
        assertEquals(listOf("review", "status", "--porcelain"), r.args)
    }

    @Test
    fun posixPathDirect() {
        val r = resolveCommand("start", listOf("--", "f"), "/opt/bin/git-review", "linux")
        assertEquals("/opt/bin/git-review", r.command)
        assertEquals(listOf("start", "--", "f"), r.args)
    }

    @Test
    fun windowsShWithoutNativeExt() {
        val r = resolveCommand("next", emptyList(), "C:\\repo\\bin\\git-review", "win32")
        assertEquals("sh", r.command)
        assertEquals(listOf("C:\\repo\\bin\\git-review", "next"), r.args)
    }

    @Test
    fun windowsExeDirect() {
        val r = resolveCommand("next", emptyList(), "C:\\git-review.exe", "win32")
        assertEquals("C:\\git-review.exe", r.command)
        assertEquals(listOf("next"), r.args)
    }

    @Test
    fun timeouts() {
        assertEquals(READ_TIMEOUT_MS, timeoutForClass("status", emptyList()))
        assertEquals(LOCAL_MUTATION_TIMEOUT_MS, timeoutForClass("finish", emptyList()))
        assertEquals(NETWORK_MUTATION_TIMEOUT_MS, timeoutForClass("start", emptyList()))
        assertEquals(NETWORK_MUTATION_TIMEOUT_MS, timeoutForClass("forget", listOf("--delta", "--stale")))
        assertEquals(LOCAL_MUTATION_TIMEOUT_MS, timeoutForClass("forget", listOf("--saved", "--all")))
        assertEquals(SUPPORT_GIT_TIMEOUT_MS, timeoutMs(InvocationClass.SUPPORT_GIT))
    }
}
