package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.commentsArgv
import com.ezevillo.gitreview.domain.parseComments
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.concurrent.TimeUnit

class CommentsTeamIT {
    @Test fun realInvokerPreservesRepliesAndIsolatesBranchesAcrossMergeStrategies(@TempDir directory: File) {
        val source = File(System.getProperty("git.review.monorepo.root"))
        val script = File(source, "tests/helpers/comments-team-history.sh")
        val cli = CliInvoker({ File(source, "bin/git-review").absolutePath })
        for (strategy in listOf("ff", "merge", "squash")) {
            val root = File(directory, strategy).apply { mkdirs() }
            val cwd = File(root, "reviewer").absolutePath
            fun history(phase: String) {
                val log = File(root, "fixture-$phase.log")
                val process = ProcessBuilder(listOf("sh", script.absolutePath, phase, root.absolutePath, strategy))
                    .redirectErrorStream(true).redirectOutput(log).start()
                assertTrue(process.waitFor(30, TimeUnit.SECONDS), "Git fixture timed out")
                assertEquals(0, process.exitValue(), log.readText())
            }
            fun review(verb: String, vararg args: String): String {
                val result = cli.invoke(verb, args.toList(), cwd)
                assertEquals(0, result.exitCode, result.stderr)
                return result.stdout
            }
            fun report() = parseComments(review("comments", "status", "--porcelain"))
            fun add(kind: String, text: String) {
                val result = cli.invokeWithInput("comments", commentsArgv(report(), "add", kind) + "--stdin", cwd, text)
                assertEquals(0, result.exitCode, result.stderr)
            }
            history("init")
            review("start", "--no-walk", "feature/team")
            add("local", "Private reviewer sentinel")
            add("shared", "Reviewer question")
            val context = report().documents.single { it.kind == "shared" }.context
            review("finish")
            assertFalse(File(cwd, ".review/comments.md").readText().contains("Private reviewer sentinel"))
            history("publish")
            review("clean", "feature/team")
            review("start", "--no-walk", "feature/team")
            review("comments", "init", "--document", "shared")
            val shared = report().documents.single { it.kind == "shared" }
            assertEquals(context, shared.context)
            assertFalse(report().records("comments-diagnostic").any { it[1] == "source-conflict" })
            assertTrue(File(shared.path).readText().contains("Author response"))
            assertTrue(File(cwd, ".review/comments.md").readText().contains("Author response"))
            File(cwd, ".review/comments.md").copyTo(File(shared.path), overwrite = true)
            assertTrue(File(shared.path).readText().contains("Author response"))
            review("finish")
            assertFalse(report().records("comments-diagnostic").any { it[1] == "source-conflict" })
            history("merge")
            for (branch in listOf("before-merge", "after-merge")) {
                review("start", "--no-walk", branch)
                assertEquals("fresh", report().records("comments-identity").single()[0])
                add("shared", "Independent question")
                val fresh = report().documents.single { it.kind == "shared" && it.context != context }
                assertTrue(File(fresh.path).readText().contains("Independent question"))
                assertFalse(File(fresh.path).readText().contains("Author response"))
                review("abort")
            }
        }
    }
}
