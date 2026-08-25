package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * US4 (012): lo que queda del camino del borrador dentro del asistente, y su
 * paridad con la de la extensión (`vscode-extension/test/unit/draftFlow.spec.ts`).
 * Los casos son deliberadamente los mismos: si una de las dos se desvía, se ve
 * acá.
 */
class DraftFlowTest {

    @Test
    fun initialStateSkipsCreationWhenResuming() {
        assertEquals(DraftFlowState.Create(force = false), initialDraftFlowState(DraftStep.CREATE))
        // RESUME no invoca nada: el archivo se usa tal cual está.
        assertEquals(DraftFlowState.Done, initialDraftFlowState(DraftStep.RESUME))
    }

    @Test
    fun updateIsTheSameCommandAsCreateAndStartOverIsTheOneWithForce() {
        // El verbo actualiza en vez de negarse, así que reconciliar no necesita
        // ningún flag: lo único que distingue a las dos ramas del picker es que
        // una tira lo escrito y la otra no.
        assertEquals(DraftFlowState.Create(force = false), initialDraftFlowState(DraftStep.UPDATE))
        assertEquals(DraftFlowState.Create(force = true), initialDraftFlowState(DraftStep.START_OVER))
    }

    @Test
    fun creatingGreenEndsTheWizard() {
        assertEquals(
            DraftFlowState.Done,
            advanceDraftFlow(DraftFlowState.Create(), DraftFlowEvent.Created(ok = true)),
        )
    }

    @Test
    fun theMachineHasThreeStatesAndNoneWaits() {
        // El bucle de 011 (Open / Wait / Build / Reload / PickKeys) se retiró
        // entero: lo que hacía vive en el panel, sobre un estado que sobrevive a
        // cerrar el IDE. Si alguno volviera, este test lo dice.
        val kinds = setOf(
            initialDraftFlowState(DraftStep.CREATE)::class.simpleName,
            initialDraftFlowState(DraftStep.RESUME)::class.simpleName,
            advanceDraftFlow(DraftFlowState.Create(), DraftFlowEvent.Created(ok = true))::class.simpleName,
            advanceDraftFlow(DraftFlowState.Create(), DraftFlowEvent.Created(ok = false))::class.simpleName,
        )
        assertEquals(setOf("Create", "Done", "Back"), kinds)
    }

    @Test
    fun aFailedCreationGoesBackWithTheReason() {
        assertEquals(
            DraftFlowState.Back("a draft already exists; use --force"),
            advanceDraftFlow(
                DraftFlowState.Create(),
                DraftFlowEvent.Created(ok = false, error = "a draft already exists; use --force"),
            ),
        )
    }

    @Test
    fun aFailureWithoutStderrGoesBackWithoutInventingAReason() {
        assertEquals(
            DraftFlowState.Back(),
            advanceDraftFlow(DraftFlowState.Create(), DraftFlowEvent.Created(ok = false)),
        )
    }

    @Test
    fun doneAndBackAreTerminal() {
        assertEquals(
            DraftFlowState.Done,
            advanceDraftFlow(DraftFlowState.Done, DraftFlowEvent.Created(ok = true)),
        )
        val back = DraftFlowState.Back("boom")
        assertEquals(back, advanceDraftFlow(back, DraftFlowEvent.Created(ok = true)))
    }

    // --- ofertas ----------------------------------------------------------------

    @Test
    fun keysAreOnlyOfferedWhenTheCliReportsThem() {
        assertFalse(offersIncludeKeys(null))
        assertFalse(offersIncludeKeys(emptyList()))
        assertFalse(offersIncludeKeys(listOf(ReadingOffer(OfferId.WALK, OfferRank.RECOMMENDED))))
        assertTrue(
            offersIncludeKeys(
                listOf(
                    ReadingOffer(OfferId.WALK, OfferRank.RECOMMENDED),
                    ReadingOffer(OfferId.KEYS, OfferRank.AVAILABLE),
                ),
            ),
        )
    }

    // --- argv (paridad con reviewIntent.ts) -------------------------------------

    @Test
    fun draftArgvMatchesTheContract() {
        assertEquals(
            listOf("draft", "--", "feature/x"),
            draftArgs("feature/x", ReviewSource.REMOTE, ReviewRange.FULL, build = false),
        )
        assertEquals(
            listOf("draft", "--build", "--local", "--delta", "--", "feature/x"),
            draftArgs("feature/x", ReviewSource.LOCAL, ReviewRange.DELTA, build = true),
        )
        assertEquals(
            listOf("draft", "--offline", "--", "feature/x"),
            draftArgs("feature/x", ReviewSource.OFFLINE, ReviewRange.FULL, build = false),
        )
        // Los controles de la fila nunca llevan --force, --from ni --stdout:
        // validan y arrancan sobre lo que hay escrito.
        val args = draftArgs("feature/x", ReviewSource.REMOTE, ReviewRange.FULL, build = true)
        assertFalse(args.contains("--force"))
        assertFalse(args.contains("--from"))
        assertFalse(args.contains("--stdout"))
        // --force sólo cuando el revisor eligió empezar de cero en el picker.
        assertEquals(
            listOf("draft", "--force", "--local", "--delta", "--", "feature/x"),
            draftArgs("feature/x", ReviewSource.LOCAL, ReviewRange.DELTA, build = false, force = true),
        )
    }

    @Test
    fun theThreeStepsOfValidateAndStartCarryTheSameFlags() {
        // Salen de los campos source/range del registro `draft`, no de los
        // defaults: con los defaults, un borrador hecho con --delta o --local
        // cubre otro conjunto de paths y --build muere por deriva, siempre.
        assertEquals(
            listOf("draft", "--build", "--local", "--delta", "--", "feature/x"),
            draftArgs("feature/x", ReviewSource.LOCAL, ReviewRange.DELTA, build = true),
        )
        assertEquals(
            listOf("--porcelain", "--local", "--delta", "--", "feature/x"),
            draftConfigArgs("feature/x", ReviewSource.LOCAL, ReviewRange.DELTA),
        )
        assertEquals(
            listOf("--delta", "--local", "--", "feature/x"),
            intentToArgs(
                ReviewIntent(
                    branch = "feature/x",
                    layout = ReviewLayout.WALK,
                    range = ReviewRange.DELTA,
                    source = ReviewSource.LOCAL,
                ),
                "feature/x",
            ),
        )
    }

    @Test
    fun discardNamesOneBranchAndNeverAllOrSaved() {
        assertEquals(listOf("--draft", "--", "feature/x"), forgetDraftArgs("feature/x"))
        val argv = actionToArgv("forgetDraft", ActionParams.ForgetDraft("feature/x"))
        assertEquals("forget", argv.verb)
        assertEquals(listOf("--draft", "--", "feature/x"), argv.args)
        assertFalse(argv.args.contains("--all"))
        assertFalse(argv.args.contains("--saved"))
    }

    // --- el texto del portapapeles ----------------------------------------------

    @Test
    fun theAgentPromptIsTheCanonicalTextWithThisRowsPath() {
        assertEquals(
            "Fill in the reading order at /repo/.git/review-walkthrough/feature/x.md. " +
                "The instructions are inside the file, in the comment at the top. " +
                "Do not change the file list or the numbering rules.",
            UserCopy.draftAgentPrompt("/repo/.git/review-walkthrough/feature/x.md"),
        )
    }

    @Test
    fun theAgentPromptNamesNoModelServiceOrAssistant() {
        val text = UserCopy.draftAgentPrompt("/x.md").lowercase()
        for (word in listOf("copilot", "openai", "claude", "chatgpt", "http")) {
            assertFalse(text.contains(word), word)
        }
    }
}
