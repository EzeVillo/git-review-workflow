package com.ezevillo.gitreview.diff

import com.ezevillo.gitreview.domain.CommitChange
import com.ezevillo.gitreview.domain.SUPPORT_GIT_TIMEOUT_MS
import com.ezevillo.gitreview.domain.parseNameStatus
import com.ezevillo.gitreview.host.CliInvoker
import com.ezevillo.gitreview.host.InvokeResult
import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.execution.process.CapturingProcessHandler
import java.nio.charset.StandardCharsets
import java.util.concurrent.TimeUnit

/**
 * Runs support-git name-status for whole-range or single-commit diffs.
 */
object RangeChanges {
    fun nameStatusHead(cwd: String, gitExecutable: String = "git"): List<CommitChange> {
        val result = runGit(
            gitExecutable,
            listOf("diff", "--name-status", "-z", "--no-renames", "HEAD"),
            cwd,
        )
        if (result.exitCode != 0 || result.timedOut) return emptyList()
        return parseNameStatus(result.stdout)
    }

    fun nameStatusCommit(cwd: String, sha: String, gitExecutable: String = "git"): List<CommitChange> {
        // --no-commit-id is required: without it, -z output starts with
        // `<sha>\0M\0path\0…` and parseNameStatus treats the status letter "M"
        // as a path (empty panes titled "M"). Same argv as VS Code openEntry.
        val result = runGit(
            gitExecutable,
            listOf("diff-tree", "-r", "-z", "--no-commit-id", "--name-status", "--root", sha),
            cwd,
        )
        if (result.exitCode != 0 || result.timedOut) return emptyList()
        return parseNameStatus(result.stdout)
    }

    /**
     * Raw bytes of [path] as of [ref], or `null` when git cannot produce them
     * (path absent at that ref, bad ref, timeout). Bytes and not text: the blob may
     * not be UTF-8, and the diff viewer decodes it with the file's own charset.
     */
    fun showBytes(cwd: String, ref: String, path: String, gitExecutable: String = "git"): ByteArray? {
        return try {
            val cmd = GeneralCommandLine(gitExecutable)
                .withParameters("--no-pager", "show", "$ref:$path")
                .withWorkDirectory(cwd)
                .withCharset(StandardCharsets.UTF_8)
            val process = cmd.createProcess()
            // Drained on the side: a full stderr pipe would block the process while we
            // are still reading stdout.
            val drain = Thread { runCatching { process.errorStream.readAllBytes() } }
            drain.isDaemon = true
            drain.start()
            val bytes = process.inputStream.readAllBytes()
            if (!process.waitFor(SUPPORT_GIT_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                process.destroyForcibly()
                return null
            }
            if (process.exitValue() != 0) null else bytes
        } catch (_: Exception) {
            null
        }
    }

    private fun runGit(git: String, args: List<String>, cwd: String): InvokeResult {
        return try {
            val cmd = GeneralCommandLine(git)
                .withParameters(args)
                .withWorkDirectory(cwd)
                .withCharset(StandardCharsets.UTF_8)
            val handler = CapturingProcessHandler(cmd)
            val output = handler.runProcess(SUPPORT_GIT_TIMEOUT_MS.toInt())
            if (output.isTimeout) {
                handler.destroyProcess()
                InvokeResult(output.stdout, output.stderr, null, timedOut = true)
            } else {
                InvokeResult(output.stdout, output.stderr, output.exitCode)
            }
        } catch (e: Exception) {
            InvokeResult("", e.message ?: e.toString(), null, errorCode = e.javaClass.simpleName)
        }
    }
}
