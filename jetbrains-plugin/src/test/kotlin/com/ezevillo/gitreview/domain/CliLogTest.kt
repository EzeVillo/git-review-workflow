package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * El log de invocaciones: lo unico que queda cuando algo sale mal y el panel ya
 * no tiene nada que mostrar. Formatear mal el final de una invocacion no rompe
 * ninguna review, y por eso es exactamente el codigo que nadie mira hasta que lo
 * necesita.
 */
class CliLogTest {
    @Test
    fun anArgumentIsQuotedOnlyWhenReadingItBackWouldBeAmbiguous() {
        assertEquals("status", shellQuoteArg("status"))
        assertEquals("--porcelain", shellQuoteArg("--porcelain"))
        // Vacio: sin comillas desapareceria de la linea.
        assertEquals("\"\"", shellQuoteArg(""))
        assertEquals("\"feature x\"", shellQuoteArg("feature x"))
        assertEquals("\"a\\\"b\"", shellQuoteArg("a\"b"))
        assertEquals("\"C:\\\\repo\"", shellQuoteArg("C:\\repo"))
        assertEquals("\"a\tb\"", shellQuoteArg("a\tb"))
    }

    @Test
    fun theCommandLineQuotesTheArgumentsAndNotTheCommand() {
        assertEquals("git review status", formatCommandLine("git", listOf("review", "status")))
        assertEquals(
            "git review start -- \"feature x\"",
            formatCommandLine("git", listOf("review", "start", "--", "feature x")),
        )
        assertEquals("git", formatCommandLine("git", emptyList()))
    }

    /**
     * Las cuatro salidas de una invocacion, y ninguna se lee como otra: un
     * timeout no es un exit code, y un spawn que fallo no es un exit code
     * tampoco.
     */
    @Test
    fun eachEndingHasItsOwnLine() {
        assertEquals(
            listOf("← timed out after 5000ms (killed)"),
            formatCliEnd(CliLogEnd(exitCode = null, durationMs = 5000, stderr = "", timedOut = true)),
        )
        assertEquals(
            listOf("← spawn failed ProcessNotCreatedException  7ms"),
            formatCliEnd(
                CliLogEnd(exitCode = null, errorCode = "ProcessNotCreatedException", durationMs = 7, stderr = ""),
            ),
        )
        assertEquals(
            listOf("← exit 0  12ms"),
            formatCliEnd(CliLogEnd(exitCode = 0, durationMs = 12, stderr = "")),
        )
        assertEquals(
            listOf("← exit null  3ms"),
            formatCliEnd(CliLogEnd(exitCode = null, durationMs = 3, stderr = "")),
        )
    }

    /**
     * El timeout gana sobre todo lo demas: un proceso que se mato por tiempo
     * puede traer errorCode y stderr, y decir "spawn failed" ahi manda a buscar
     * el problema al lugar equivocado.
     */
    @Test
    fun aTimeoutIsReportedAsATimeoutAndNothingElse() {
        val end = formatCliEnd(
            CliLogEnd(
                exitCode = null,
                errorCode = "SomeException",
                durationMs = 30_000,
                stderr = "half a line",
                timedOut = true,
            ),
        )
        assertEquals(listOf("← timed out after 30000ms (killed)"), end)
    }

    /**
     * En verde el stderr no se copia: son las notas de la CLI, que el panel ya
     * dibuja. Con exit != 0 si, porque ahi es la unica explicacion que hay.
     */
    @Test
    fun stderrIsAppendedOnlyWhenTheInvocationFailed() {
        assertEquals(
            listOf("← exit 0  1ms"),
            formatCliEnd(CliLogEnd(exitCode = 0, durationMs = 1, stderr = "a note\n")),
        )
        assertEquals(
            listOf("← exit 1  2ms", "  fatal: bad", "  second line"),
            formatCliEnd(CliLogEnd(exitCode = 1, durationMs = 2, stderr = "fatal: bad\r\nsecond line\n")),
        )
        // Un fallo mudo no agrega una linea vacia sangrada.
        assertEquals(
            listOf("← exit 1  2ms"),
            formatCliEnd(CliLogEnd(exitCode = 1, durationMs = 2, stderr = "   \n")),
        )
    }

    /**
     * Un stderr enorme se corta: el buffer del log tiene 500 lineas, y una sola
     * invocacion no se las puede llevar todas.
     */
    @Test
    fun aHugeStderrIsTruncatedAndSaysSo() {
        val lines = formatCliEnd(
            CliLogEnd(exitCode = 1, durationMs = 1, stderr = "x".repeat(STDERR_MAX + 500)),
        )
        assertEquals(listOf("← exit 1  1ms", "  " + "x".repeat(STDERR_MAX), "  … (truncated)"), lines)

        // Justo en el limite no se toca.
        val exact = formatCliEnd(CliLogEnd(exitCode = 1, durationMs = 1, stderr = "y".repeat(STDERR_MAX)))
        assertEquals(2, exact.size)
        assertTrue(exact[1].endsWith("y"))
    }
}
