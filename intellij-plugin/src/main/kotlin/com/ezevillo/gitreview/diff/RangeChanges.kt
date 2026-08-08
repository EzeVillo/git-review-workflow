package com.ezevillo.gitreview.diff

import com.ezevillo.gitreview.domain.CommitChange
import com.ezevillo.gitreview.domain.SUPPORT_GIT_TIMEOUT_MS
import com.ezevillo.gitreview.domain.parseNameStatus
import com.ezevillo.gitreview.host.CliInvoker
import com.ezevillo.gitreview.host.InvokeResult
import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.execution.process.CapturingProcessHandler
import java.nio.charset.StandardCharsets

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
        val result = runGit(
            gitExecutable,
            listOf("diff-tree", "-r", "-z", "--name-status", "--root", sha),
            cwd,
        )
        if (result.exitCode != 0 || result.timedOut) return emptyList()
        return parseNameStatus(result.stdout)
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
