package com.ezevillo.gitreview.host

import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Light integration: real process if `git review --version` is on PATH.
 */
class CliInvokerIT {
    @Test
    fun versionWhenCliPresent() {
        val invoker = CliInvoker(gitReviewPath = { null })
        val cwd = File(".").absolutePath
        val result = invoker.invoke("--version", emptyList(), cwd)
        // Skip when CLI is missing (exit != 0 or spawn error) — unit suite stays green.
        assumeTrue(
            result.exitCode == 0 && !result.timedOut && result.errorCode == null,
            "git review not available; skip IT",
        )
        assertNotNull(result.stdout.trim().ifEmpty { null })
    }
}
