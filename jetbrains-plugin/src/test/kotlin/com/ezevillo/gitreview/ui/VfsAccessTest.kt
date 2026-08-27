package com.ezevillo.gitreview.ui

import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Resolving a path against the VFS is the one platform call in this plugin that
 * fails *only* at runtime and only for some files: when the VFS has never seen the
 * file it creates the node and fires the creation event, which needs the write-intent
 * lock a panel button's ActionListener does not have. The files that take that branch
 * are exactly the ones this plugin is about -- the reviewer's draft and their own
 * authoring guide, both in the gitdir, which no editor indexes -- while the ones in
 * the working tree hit the cache and never complain. So a bad call reads as fine, is
 * green in every test here, and dies in the user's IDE the first time it matters.
 *
 * `host/EditorFiles.kt` is the single door: it resolves off the EDT and opens the
 * editor back on it. This keeps it single.
 */
class VfsAccessTest {
    @Test
    fun `the VFS is only reached through the one helper that goes off the EDT`() {
        val offenders = mainSources()
            .filter { it.name != HELPER }
            .flatMap { file ->
                file.readLines().mapIndexedNotNull { i, line ->
                    if (RESOLVERS.any { line.contains(it) } && !line.trimStart().startsWith("*")) {
                        "${file.name}:${i + 1}: ${line.trim()}"
                    } else {
                        null
                    }
                }
            }
        assertTrue(
            offenders.isEmpty(),
            "resolve paths through openInEditor/refreshAndFind in $HELPER, not directly — " +
                "a direct call on the EDT dies with \"Access is allowed from write thread only\" " +
                "for any file the VFS has not seen:\n${offenders.joinToString("\n")}",
        )
    }

    @Test
    fun `the helper itself is there`() {
        assertTrue(
            mainSources().any { it.name == HELPER },
            "$HELPER is gone — the test above would pass by having nothing to guard",
        )
    }

    private fun mainSources(): List<File> {
        val root = System.getProperty("git.review.monorepo.root")
        assertNotNull(root, "git.review.monorepo.root is not set — see build.gradle.kts")
        val dir = File(root, "jetbrains-plugin/src/main/kotlin")
        assertTrue(dir.isDirectory, "sources missing at ${dir.absolutePath}")
        return dir.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()
    }

    private companion object {
        const val HELPER = "EditorFiles.kt"

        /** Every LocalFileSystem entry point that can end in a VFS refresh. */
        val RESOLVERS = listOf(
            "refreshAndFindFileByPath",
            "refreshAndFindFileByIoFile",
            "refreshAndFindFileByNioFile",
            "findFileByPath",
            "findFileByIoFile",
            "findFileByNioFile",
        )
    }
}
