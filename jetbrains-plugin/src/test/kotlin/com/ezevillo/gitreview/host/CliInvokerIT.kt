package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.ResolvedCommand
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.nio.charset.StandardCharsets

/**
 * El unico lugar que arranca un proceso de verdad.
 *
 * Corre contra `git`, que tiene cualquiera que clone este repo: lo que cubre
 * --la captura UTF-8, el cwd, un ejecutable que no esta-- no se puede fingir sin
 * terminar probando el fake. Antes esto invocaba `git review --version` y se
 * salteaba solo (`assumeTrue`) cuando la CLI no estaba en el PATH, que es
 * justamente el caso de los runners donde nadie la instala: verde sin haber
 * corrido nada.
 */
class CliInvokerIT {
    private val invoker = CliInvoker(gitReviewPath = { null })

    private fun git(cwd: File, vararg args: String): InvokeResult =
        invoker.invokeResolved(ResolvedCommand("git", args.toList()), cwd.absolutePath, timeoutMs = 30_000)

    @Test
    fun aRealInvocationCapturesStdoutAndTheExitCode(@TempDir dir: File) {
        val result = git(dir, "--version")

        assertEquals(0, result.exitCode)
        assertNull(result.errorCode)
        assertFalse(result.timedOut)
        assertTrue(result.stdout.startsWith("git version"), result.stdout)
    }

    /**
     * El no-ASCII tiene que sobrevivir al pipe. Se fuerza UTF-8 en las dos
     * puntas porque la code page de la consola en Windows no lo es, y un asunto
     * o una ruta con acento vuelve mordida.
     */
    @Test
    fun outputIsCapturedAsUtf8(@TempDir dir: File) {
        initRepo(dir)
        File(dir, "café.txt").writeText("hola\n", StandardCharsets.UTF_8)
        assertEquals(0, git(dir, "add", "-A").exitCode)
        assertEquals(0, commit(dir, "añadir café").exitCode)

        val subject = git(dir, "log", "-1", "--format=%s")
        assertEquals(0, subject.exitCode)
        assertEquals("añadir café", subject.stdout.trim())
    }

    /** El cwd es el del argumento, no el del proceso que corre los tests. */
    @Test
    fun theWorkingDirectoryIsTheOneItWasGiven(@TempDir dir: File) {
        initRepo(dir)
        val top = git(dir, "rev-parse", "--show-toplevel")

        assertEquals(0, top.exitCode)
        assertEquals(
            dir.canonicalFile,
            File(top.stdout.trim()).canonicalFile,
        )
    }

    /**
     * Un fallo del comando no es una excepcion: vuelve como exit code y stderr,
     * que es lo que el pipeline de refresh lee para decidir la situacion.
     */
    @Test
    fun aFailingCommandComesBackAsAnExitCodeAndStderr(@TempDir dir: File) {
        val result = git(dir, "rev-parse", "--verify", "refs/heads/nope")

        assertNotNull(result.exitCode)
        assertFalse(result.exitCode == 0)
        assertNull(result.errorCode)
        assertFalse(result.timedOut)
    }

    /**
     * Un ejecutable que no existe es la OTRA forma del fallo, y se distingue: no
     * hay exit code, hay errorCode. Es la evidencia con la que el panel decide
     * decir que la CLI no esta.
     */
    @Test
    fun anExecutableThatIsNotThereIsReportedAsASpawnFailure(@TempDir dir: File) {
        val result = invoker.invokeResolved(
            ResolvedCommand("git-review-does-not-exist", listOf("--version")),
            dir.absolutePath,
            timeoutMs = 10_000,
        )

        assertNull(result.exitCode)
        assertNotNull(result.errorCode)
        assertFalse(result.timedOut)
        assertTrue(result.stdout.isEmpty())
    }

    /**
     * Toda invocacion queda en el log, con la linea de comando primero y el
     * final despues: es lo unico que le queda a quien reporta un problema.
     */
    @Test
    fun bothEndsOfTheInvocationReachTheLog(@TempDir dir: File) {
        CliLogSink.clear()
        git(dir, "--version")

        val log = CliLogSink.snapshot()
        assertEquals(2, log.size, log.toString())
        assertTrue(log[0].startsWith("→ git --version  (cwd="), log[0])
        assertTrue(log[1].startsWith("← exit 0"), log[1])
    }

    /**
     * El askpass no-op: lo que impide que una invocacion de red se cuelgue
     * esperando una credencial que en un IDE nadie va a tipear. Tiene que
     * EXISTIR y salir 0 en silencio -- un script que no corre deja el prompt de
     * git otra vez del otro lado.
     */
    @Test
    fun theAskpassScriptExistsAndExitsQuietly() {
        val path = resolveAskpassCommand()
        val file = File(path)

        assertTrue(file.isFile, path)
        assertTrue(file.length() > 0, path)
        val isWindows = System.getProperty("os.name").lowercase().contains("win")
        assertTrue(path.endsWith(if (isWindows) ".cmd" else ".sh"), path)
        if (!isWindows) assertTrue(file.canExecute(), path)

        // Se reusa en vez de reescribirse en cada invocacion de red.
        assertEquals(path, resolveAskpassCommand())

        val process = ProcessBuilder(if (isWindows) listOf("cmd", "/c", path) else listOf("sh", path))
            .redirectErrorStream(true)
            .start()
        val output = process.inputStream.readBytes().toString(StandardCharsets.UTF_8)
        assertEquals(0, process.waitFor())
        assertTrue(output.isBlank(), output)
    }

    private fun initRepo(dir: File) {
        assertEquals(0, git(dir, "init", "-q", "-b", "main").exitCode)
    }

    private fun commit(dir: File, message: String): InvokeResult = git(
        dir,
        "-c",
        "user.email=test@example.com",
        "-c",
        "user.name=Test",
        "commit",
        "-q",
        "-m",
        message,
    )
}
