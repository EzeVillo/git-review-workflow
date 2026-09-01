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
 * La unica llamada que el pipeline de refresh y las mutaciones le hacen a la
 * CLI, como interfaz.
 *
 * El unico implementador de produccion es [CliInvoker], que arranca un proceso
 * de verdad. La costura existe para que lo que decide a partir de las respuestas
 * --[ReviewStateManager], sobre todo-- se pueda ejercitar sin proceso: un
 * proceso real por caso seria lento y, para un timeout o una CLI ausente,
 * estaria probando la maquina y no el pipeline. Es la misma costura que el
 * cliente de Visual Studio tiene desde el principio (`FakeCliInvoker`).
 */
interface CliRunner {
    fun invoke(
        verb: String,
        args: List<String>,
        cwd: String,
        network: Boolean = false,
        timeoutMs: Long = timeoutForClass(verb, args),
    ): InvokeResult
}

/**
 * Spawns git-review via [GeneralCommandLine] with forced UTF-8 capture.
 * Domain-facing: no UI.
 */
class CliInvoker(
    private val gitReviewPath: () -> String?,
    private val askpassCommand: () -> String = { resolveAskpassCommand() },
    private val logger: Logger = Logger.getInstance(CliInvoker::class.java),
) : CliRunner {
    override fun invoke(
        verb: String,
        args: List<String>,
        cwd: String,
        network: Boolean,
        timeoutMs: Long,
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

            // La unica variable que este plugin le impone a la CLI, y va en
            // TODA invocacion. Apaga las notas que un panel no necesita: las
            // que ofrecen un comando --aca es un boton-- y las que describen
            // algo que ya viaja como registro porcelain --aca es una fila--.
            // Un solo lugar, porque del otro lado no hay filtro posible:
            // distinguir una nota de otra seria leer salida humana, que el
            // contrato de invocacion prohibe. Lo que NO es advice sigue
            // llegando entero (una entrada que el PR ya no cambia, un cursor
            // que se movio). Ver advice_enabled en bin/git-review-lib.sh; una
            // CLI vieja la ignora y solo imprime de mas.
            cmd.withEnvironment("GIT_REVIEW_ADVICE", "0")

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
