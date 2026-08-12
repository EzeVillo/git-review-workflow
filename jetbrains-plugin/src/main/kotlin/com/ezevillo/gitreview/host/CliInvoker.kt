package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.ResolvedCommand
import com.ezevillo.gitreview.domain.formatCliEnd
import com.ezevillo.gitreview.domain.formatCommandLine
import com.ezevillo.gitreview.domain.resolveCommand
import com.ezevillo.gitreview.domain.timeoutForClass
import com.ezevillo.gitreview.domain.CliLogEnd
import com.intellij.execution.configurations.GeneralCommandLine
import com.intellij.execution.process.CapturingProcessHandler
import com.intellij.execution.process.ProcessOutput
import com.intellij.openapi.diagnostic.Logger
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path

data class InvokeResult(
    val stdout: String,
    val stderr: String,
    val exitCode: Int?,
    val errorCode: String? = null,
    val timedOut: Boolean = false,
)

/**
 * Spawns git-review via [GeneralCommandLine] with forced UTF-8 capture.
 * Domain-facing: no UI.
 */
class CliInvoker(
    private val gitReviewPath: () -> String?,
    private val askpassCommand: () -> String = { resolveAskpassCommand() },
    private val logger: Logger = Logger.getInstance(CliInvoker::class.java),
) {
    fun invoke(
        verb: String,
        args: List<String>,
        cwd: String,
        network: Boolean = false,
        timeoutMs: Long = timeoutForClass(verb, args),
    ): InvokeResult {
        val resolved = resolveCommand(verb, args, gitReviewPath())
        return invokeResolved(resolved, cwd, network, timeoutMs)
    }

    fun invokeResolved(
        resolved: ResolvedCommand,
        cwd: String,
        network: Boolean = false,
        timeoutMs: Long,
    ): InvokeResult {
        val start = System.currentTimeMillis()
        val line = formatCommandLine(resolved.command, resolved.args)
        logger.info("→ $line  (cwd=$cwd)")
        CliLogSink.append("→ $line  (cwd=$cwd)")

        return try {
            val cmd = GeneralCommandLine(resolved.command)
                .withParameters(resolved.args)
                .withWorkDirectory(cwd)
                .withCharset(StandardCharsets.UTF_8)
                .withParentEnvironmentType(GeneralCommandLine.ParentEnvironmentType.CONSOLE)

            if (network) {
                val askpass = askpassCommand()
                cmd.withEnvironment("GIT_TERMINAL_PROMPT", "0")
                cmd.withEnvironment("GIT_ASKPASS", askpass)
                cmd.withEnvironment("SSH_ASKPASS", askpass)
            }

            val handler = CapturingProcessHandler(cmd)
            val output: ProcessOutput = handler.runProcess(timeoutMs.toInt())
            val duration = System.currentTimeMillis() - start

            if (output.isTimeout) {
                handler.destroyProcess()
                val result = InvokeResult(
                    stdout = output.stdout,
                    stderr = output.stderr,
                    exitCode = null,
                    timedOut = true,
                )
                logEnd(result, duration)
                return result
            }

            val result = InvokeResult(
                stdout = output.stdout,
                stderr = output.stderr,
                exitCode = output.exitCode,
            )
            logEnd(result, duration)
            result
        } catch (e: Exception) {
            val duration = System.currentTimeMillis() - start
            val result = InvokeResult(
                stdout = "",
                stderr = e.message ?: e.toString(),
                exitCode = null,
                errorCode = e.javaClass.simpleName,
            )
            logEnd(result, duration)
            result
        }
    }

    private fun logEnd(result: InvokeResult, durationMs: Long) {
        val end = CliLogEnd(
            exitCode = result.exitCode,
            errorCode = result.errorCode,
            durationMs = durationMs,
            stderr = result.stderr,
            timedOut = result.timedOut,
        )
        for (line in formatCliEnd(end)) {
            when {
                line.startsWith("← timed out") || line.startsWith("← spawn") -> logger.warn(line)
                result.exitCode == 0 -> logger.info(line)
                else -> logger.warn(line)
            }
            CliLogSink.append(line)
        }
    }
}

/** In-memory ring buffer for "Show CLI Log" (domain-pure formatting). */
object CliLogSink {
    private const val MAX = 500
    private val lines = ArrayDeque<String>()

    @Synchronized
    fun append(line: String) {
        lines.addLast(line)
        while (lines.size > MAX) lines.removeFirst()
    }

    @Synchronized
    fun snapshot(): List<String> = lines.toList()

    @Synchronized
    fun clear() {
        lines.clear()
    }
}

/**
 * Multiplatform askpass no-op: a temp script that exits 0 with empty output.
 * On Windows uses a `.cmd`; elsewhere a shell script.
 */
fun resolveAskpassCommand(): String {
    val isWin = System.getProperty("os.name").lowercase().contains("win")
    val path = if (isWin) {
        writeTempAskpass(
            suffix = ".cmd",
            content = "@echo off\r\nexit /b 0\r\n",
        )
    } else {
        writeTempAskpass(
            suffix = ".sh",
            content = "#!/bin/sh\nexit 0\n",
        ).also {
            it.toFile().setExecutable(true)
        }
    }
    return path.toAbsolutePath().toString()
}

private fun writeTempAskpass(suffix: String, content: String): Path {
    val dir = Path.of(System.getProperty("java.io.tmpdir"), "git-review-askpass")
    Files.createDirectories(dir)
    val file = dir.resolve("askpass-noop$suffix")
    if (!Files.exists(file)) {
        Files.writeString(file, content, StandardCharsets.UTF_8)
    }
    return file
}
