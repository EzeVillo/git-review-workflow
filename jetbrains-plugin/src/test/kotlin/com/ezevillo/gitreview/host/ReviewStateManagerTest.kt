package com.ezevillo.gitreview.host

import com.ezevillo.gitreview.domain.CLI_PROBE_RETRIES
import com.ezevillo.gitreview.domain.MIN_CLI_VERSION
import com.ezevillo.gitreview.domain.ReviewMode
import com.ezevillo.gitreview.domain.Situation
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * El pipeline de refresh: sonda de version -> `status --porcelain` -> `list` y
 * `config` cuando hacen falta. Es la unica fuente de ReviewState del panel, y no
 * lo cubria nadie: la unica prueba del paquete `host` arrancaba un proceso de
 * verdad y se salteaba sola cuando la CLI no estaba en el PATH.
 */
class ReviewStateManagerTest {
    private fun manager(cli: CliRunner) = ReviewStateManager(cli, gitReviewPath = { null })

    @Test
    fun anActiveReviewIsParsedIntoTheState() {
        val cli = FakeCliRunner().answer("status", WALK_STATUS)
        val state = manager(cli).refresh("/repo")

        assertEquals(Situation.REVIEW, state.situation)
        assertEquals(ReviewMode.WALK, state.state?.mode)
        assertEquals(3, state.entries.size)
        assertEquals(listOf("--version", "status"), cli.verbs)
        assertTrue(cli.calls.all { it.cwd == "/repo" })
        assertEquals(listOf("--porcelain"), cli.calls.last().args)
    }

    @Test
    fun aFinishRecordMakesItAConflict() {
        val cli = FakeCliRunner().answer("status", WALK_STATUS + "\nfinish\tconflict\t0")
        val state = manager(cli).refresh("/repo")

        assertEquals(Situation.FINISH_CONFLICT, state.situation)
        assertNotNull(state.finish)
        assertEquals(ReviewMode.WALK, state.state?.mode)
    }

    /**
     * Exit 2 es "no hay review", y recien ahi el pipeline paga el inventario y la
     * config: pedirlos en cada refresh serian dos procesos por tecla.
     */
    @Test
    fun noReviewAlsoReadsTheInventoryAndTheConfig() {
        val cli = FakeCliRunner()
            .fails("status", "no review", exitCode = 2)
            .answer("list", "branch\treview-saved/feature\t1\t0\t0\twalk\t2\t5")
            .answer("config", "config\tbase\tmain\nconfig\tremote\torigin\ncandidate\tfeature\tremote\t1")
        val state = manager(cli).refresh("/repo")

        assertEquals(Situation.NO_REVIEW, state.situation)
        assertEquals(1, state.branches.size)
        assertTrue(state.branches[0].saved)
        assertEquals("main", state.config?.base)
        assertEquals("origin", state.config?.remote)
        assertEquals(1, state.candidates?.size)
        assertEquals(listOf("--version", "status", "list", "config"), cli.verbs)
    }

    @Test
    fun aPendingFinishInTheInventoryBecomesFinishPending() {
        val cli = FakeCliRunner()
            .fails("status", "no review", exitCode = 2)
            .answer(
                "list",
                "branch\treview/feature\t0\t0\t0\twhole\t1\t1\nfinish\treview/feature\tpending\t0",
            )
            .answer("config", "config\tremote\torigin")
        val state = manager(cli).refresh("/repo")

        assertEquals(Situation.FINISH_PENDING, state.situation)
        assertEquals("pending", state.branches[0].finish?.state)
    }

    /**
     * Un inventario ilegible no convierte "no hay review" en una pantalla de
     * error: la situacion la fija el exit code del status y nada mas.
     */
    @Test
    fun anUnreadableInventoryOrConfigStillYieldsNoReview() {
        val cli = FakeCliRunner()
            .fails("status", "no review", exitCode = 2)
            .fails("list", "boom")
            .fails("config", "boom")
        val state = manager(cli).refresh("/repo")

        assertEquals(Situation.NO_REVIEW, state.situation)
        assertTrue(state.branches.isEmpty())
        assertTrue(state.fixes.isEmpty())
        assertNull(state.config)
    }

    /**
     * Exit 3 no imprime porcelain: parsearla igual es como el stderr accionable
     * ("undo the commits with git reset --soft, or abort") salia convertido en
     * "porcelain output has no state record" bajo un error generico.
     */
    @Test
    fun outOfRangeKeepsTheClisOwnDiagnosis() {
        val cli = FakeCliRunner().fails(
            "status",
            "HEAD moved: undo the commits with git reset --soft, or abort",
            exitCode = 3,
        )
        val state = manager(cli).refresh("/repo")

        assertEquals(Situation.OUT_OF_RANGE, state.situation)
        assertTrue(state.stderr.orEmpty().contains("git reset --soft"), state.stderr)
        assertNull(state.state)
    }

    /**
     * Una porcelain que el parser no puede leer es mas seguido una CLI que ya se
     * explico que un bug del tokenizador, y sobre lo primero el revisor puede
     * hacer algo.
     */
    @Test
    fun unparseablePorcelainShowsWhatTheCliSaidFirst() {
        val withStderr = FakeCliRunner()
            .answer("status", InvokeResult("garbage", "fatal: the repository is in a bad state", 0))
        val state = manager(withStderr).refresh("/repo")
        assertEquals(Situation.ERROR, state.situation)
        assertEquals("fatal: the repository is in a bad state", state.stderr)

        // Sin nada en stderr, el mensaje del parser es mejor que nada.
        val silent = FakeCliRunner().answer("status", "garbage")
        val fallback = manager(silent).refresh("/repo")
        assertEquals(Situation.ERROR, fallback.situation)
        assertTrue(fallback.stderr.orEmpty().isNotBlank())
    }

    @Test
    fun aStatusTimeoutIsItsOwnErrorNotAnEmptyReview() {
        val cli = FakeCliRunner().answer("status", InvokeResult("", "", null, timedOut = true))
        val state = manager(cli).refresh("/repo")

        assertEquals(Situation.ERROR, state.situation)
        assertTrue(state.stderr.orEmpty().contains("timed out"), state.stderr)
        // Y no se fue a pedir el inventario de una review que no leyo.
        assertEquals(listOf("--version", "status"), cli.verbs)
    }

    @Test
    fun aMissingCliIsReportedAsMissingNotAsAnError() {
        for (stderr in listOf(
            "git: 'review' is not a git command.",
            "sh: git-review: not found",
            "spawn git-review ENOENT",
        )) {
            val cli = FakeCliRunner().fails("--version", stderr, exitCode = 127)
            val state = manager(cli).refresh("/repo")

            assertEquals(Situation.CLI_MISSING, state.situation, stderr)
            assertEquals(stderr, state.stderr)
            // Nunca llego a preguntar por el status.
            assertEquals(listOf("--version"), cli.verbs)
        }
    }

    /**
     * Una sonda que se queda sin tiempo describe una CLI que esta y es lenta, que
     * es lo contrario de una que no esta: la pantalla de instalacion mandaria al
     * revisor a instalar lo que ya tiene instalado.
     */
    @Test
    fun aVersionProbeThatTimesOutIsNotAMissingCli() {
        val cli = FakeCliRunner().answer("--version", InvokeResult("", "", null, timedOut = true))
        val state = manager(cli).refresh("/repo")

        assertEquals(Situation.ERROR, state.situation)
        assertEquals(ReviewStateManager.VERSION_TIMEOUT, state.stderr)
    }

    /**
     * Un fallo que no nombra nada no es evidencia de nada, y la primera
     * invocacion de un arranque es la que mas chances tiene de producir uno. Se
     * reintenta antes de decirle nada al panel.
     */
    @Test
    fun aFailureWithoutEvidenceIsRetriedBeforeItIsBelieved() {
        val cli = FakeCliRunner().fails("--version", "", exitCode = 127)
        val state = manager(cli).refresh("/repo")

        assertEquals(Situation.CLI_MISSING, state.situation)
        assertEquals(1 + CLI_PROBE_RETRIES, cli.verbs.count { it == "--version" })
        assertFalse(cli.verbs.contains("status"))
    }

    /** La otra mitad: con evidencia no hay nada que esperar. */
    @Test
    fun evidenceOfAbsenceIsAnsweredOnTheFirstProbe() {
        val cli = FakeCliRunner().fails("--version", "sh: git-review: not found", exitCode = 127)
        val state = manager(cli).refresh("/repo")

        assertEquals(Situation.CLI_MISSING, state.situation)
        assertEquals(listOf("--version"), cli.verbs)
    }

    @Test
    fun aSpawnFailureThatNamesTheAbsenceIsAMissingCli() {
        val cli = FakeCliRunner().answer(
            "--version",
            InvokeResult(
                stdout = "",
                stderr = "Cannot run program \"git\": CreateProcess error=2",
                exitCode = null,
                errorCode = "ProcessNotCreatedException",
            ),
        )
        val state = manager(cli).refresh("/repo")

        assertEquals(Situation.CLI_MISSING, state.situation)
        assertEquals(listOf("--version"), cli.verbs)
    }

    @Test
    fun aCliOlderThanTheMinimumStopsBeforeTheStatus() {
        val cli = FakeCliRunner().answer("--version", "0.5.9\n")
        val state = manager(cli).refresh("/repo")

        assertEquals(Situation.CLI_OUTDATED, state.situation)
        assertTrue(state.stderr.orEmpty().contains("0.5.9"), state.stderr)
        assertEquals(listOf("--version"), cli.verbs)
    }

    /**
     * Una build que imprime su version en otro lado no es una vieja: la sonda
     * sigue de largo y deja que el status decida. `isOutdated("")` da true.
     */
    @Test
    fun aSilentVersionProbeDoesNotBlockTheRefresh() {
        val cli = FakeCliRunner()
            .answer("--version", "")
            .answer("status", WALK_STATUS)
        val state = manager(cli).refresh("/repo")

        assertEquals(Situation.REVIEW, state.situation)
    }

    /**
     * git review toma una sola raiz, como el cwd de la CLI. Sin una sola no se
     * adivina cual quiso decir el revisor: se rechaza con el texto del canonico
     * y sin gastar un proceso.
     */
    @Test
    fun withoutASingleRootNothingIsInvoked() {
        val cli = FakeCliRunner()
        val state = manager(cli).refresh(null)

        assertEquals(Situation.ERROR, state.situation)
        assertEquals(ReviewStateManager.MULTI_ROOT_ERROR, state.stderr)
        assertTrue(cli.calls.isEmpty())
    }

    /**
     * El estado semilla es un placeholder, no una respuesta: hasta que un refresh
     * conteste, `current` no es algo que el panel deba dibujar.
     */
    @Test
    fun currentHoldsTheLastResolvedState() {
        val cli = FakeCliRunner().answer("status", WALK_STATUS)
        val mgr = manager(cli)

        assertEquals(Situation.ERROR, mgr.current.situation)
        assertEquals("not refreshed yet", mgr.current.stderr)

        val state = mgr.refresh("/repo")
        assertEquals(Situation.REVIEW, mgr.current.situation)
        assertEquals(state, mgr.current)
    }

    /**
     * La sonda de version corre en CADA refresh. No es una optimizacion perdida:
     * una CLI que se instala, se actualiza o se borra con el IDE abierto tiene
     * que verse en el refresh siguiente, y sin sonda el panel quedaria clavado en
     * la respuesta del arranque.
     */
    @Test
    fun everyRefreshProbesTheVersionAgain() {
        val cli = FakeCliRunner().answer("status", WALK_STATUS)
        val mgr = manager(cli)
        mgr.refresh("/repo")
        mgr.refresh("/repo")

        assertEquals(listOf("--version", "status", "--version", "status"), cli.verbs)
    }

    /**
     * Y por eso una CLI que aparece despues se ve sin reiniciar el IDE: el panel
     * sale de cli-missing solo.
     */
    @Test
    fun aCliThatShowsUpLaterIsPickedUpByTheNextRefresh() {
        val cli = FakeCliRunner().fails("--version", "sh: git-review: not found", exitCode = 127)
        val mgr = manager(cli)
        assertEquals(Situation.CLI_MISSING, mgr.refresh("/repo").situation)

        cli.answer("--version", MIN_CLI_VERSION + "\n").answer("status", WALK_STATUS)
        assertEquals(Situation.REVIEW, mgr.refresh("/repo").situation)
    }

    private companion object {
        const val WALK_STATUS =
            "state\treview/feature\tfeature\tdeadbeef\twalk\tapplied\t1\t3\t3\t\"src/a.kt\"\t1\n" +
                "entry\t1\tsrc/a.kt\t1\t1\n" +
                "entry\t2\tsrc/b.kt\t0\t1\n" +
                "entry\t3\tsrc/c.kt\t0\t0"
    }
}
