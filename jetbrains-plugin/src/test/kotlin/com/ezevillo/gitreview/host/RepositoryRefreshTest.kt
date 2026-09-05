package com.ezevillo.gitreview.host

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * MutationActions cannot be instantiated by the plain JUnit harness because it
 * reaches for a live IntelliJ Project. This source gate protects the integration
 * seam instead: every process invocation must notify Git4Idea before the panel
 * performs its own porcelain refresh.
 */
class RepositoryRefreshTest {
    @Test
    fun `the repository helper updates the sole Git repository`() {
        val source = source("vcs/RepositoryTargets.kt")
        assertTrue(source.contains("pickSoleGitRoot(project)?.repository?.update()"))
    }

    @Test
    fun `every completed mutation refreshes IntelliJ before the panel state`() {
        val source = source("host/MutationActions.kt")
        val invocations = source.split("service.cliInvoker.invoke(").drop(1)
        assertEquals(2, invocations.size, "new mutation invocation sites must join the same refresh path")
        invocations.forEach { afterInvocation ->
            val ideRefresh = afterInvocation.indexOf("refreshIdeRepository(project)")
            val panelRefresh = afterInvocation.indexOf("service.refreshNow()")
            assertTrue(ideRefresh >= 0, "a completed mutation did not refresh GitRepository")
            assertTrue(panelRefresh >= 0 && ideRefresh < panelRefresh, "refresh GitRepository before porcelain")
        }
    }

    private fun source(relative: String): String {
        val root = System.getProperty("git.review.monorepo.root")
        assertNotNull(root, "git.review.monorepo.root is not set — see build.gradle.kts")
        val file = File(root, "jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/$relative")
        assertTrue(file.isFile, "source missing at ${file.absolutePath}")
        return file.readText()
    }
}
