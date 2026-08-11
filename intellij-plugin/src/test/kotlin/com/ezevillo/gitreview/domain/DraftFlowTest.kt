package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * US3 (011): la máquina del bucle del borrador, y su paridad con la de la
 * extensión (`vscode-extension/test/unit/draftFlow.spec.ts`). Los casos son
 * deliberadamente los mismos: si una de las dos se desvía, se ve acá.
 */
class DraftFlowTest {

    private fun run(start: DraftFlowState, events: List<DraftFlowEvent>): DraftFlowState =
        events.fold(start, ::advanceDraftFlow)

    @Test
    fun initialStateSkipsCreationWhenResuming() {
        assertEquals(DraftFlowState.Create, initialDraftFlowState(DraftStep.CREATE))
        assertEquals(DraftFlowState.Open, initialDraftFlowState(DraftStep.RESUME))
    }

    @Test
    fun happyPathWithoutKeysEndsInWalk() {
        val end = run(
            initialDraftFlowState(DraftStep.CREATE),
            listOf(
                DraftFlowEvent.Created(ok = true),
                DraftFlowEvent.Opened,
                DraftFlowEvent.Continue,
                DraftFlowEvent.Built(ok = true),
                DraftFlowEvent.Offers(
                    listOf(
                        ReadingOffer(OfferId.WALK, OfferRank.RECOMMENDED),
                        ReadingOffer(OfferId.STEP, OfferRank.AVAILABLE),
                    ),
                ),
            ),
        )
        assertEquals(DraftFlowState.Done(ReviewLayout.WALK), end)
    }

    @Test
    fun keysOfferAsksBeforeDeciding() {
        val asked = run(
            initialDraftFlowState(DraftStep.RESUME),
            listOf(
                DraftFlowEvent.Opened,
                DraftFlowEvent.Continue,
                DraftFlowEvent.Built(ok = true),
                DraftFlowEvent.Offers(
                    listOf(
                        ReadingOffer(OfferId.WALK, OfferRank.RECOMMENDED),
                        ReadingOffer(OfferId.KEYS, OfferRank.AVAILABLE),
                    ),
                ),
            ),
        )
        assertEquals(DraftFlowState.PickKeys, asked)
        assertEquals(
            DraftFlowState.Done(ReviewLayout.KEYS),
            advanceDraftFlow(asked, DraftFlowEvent.KeysPicked(true)),
        )
        assertEquals(
            DraftFlowState.Done(ReviewLayout.WALK),
            advanceDraftFlow(asked, DraftFlowEvent.KeysPicked(false)),
        )
        // Cerrar el selector vuelve atrás, sin error y sin borrar nada.
        assertEquals(
            DraftFlowState.Back(),
            advanceDraftFlow(asked, DraftFlowEvent.KeysPicked(null)),
        )
    }

    @Test
    fun failedBuildRetriesWithoutLimit() {
        var state = run(
            initialDraftFlowState(DraftStep.RESUME),
            listOf(
                DraftFlowEvent.Opened,
                DraftFlowEvent.Continue,
                DraftFlowEvent.Built(ok = false, error = "entry 3 still has the placeholder why"),
            ),
        )
        assertEquals(DraftFlowState.Wait("entry 3 still has the placeholder why"), state)

        state = run(
            state,
            listOf(DraftFlowEvent.Continue, DraftFlowEvent.Built(ok = false, error = "duplicate entry")),
        )
        assertEquals(DraftFlowState.Wait("duplicate entry"), state)

        state = run(state, listOf(DraftFlowEvent.Continue, DraftFlowEvent.Built(ok = true)))
        assertEquals(DraftFlowState.Reload, state)
    }

    @Test
    fun cancelKeepsTheDraftAndReportsNoError() {
        val state = run(
            initialDraftFlowState(DraftStep.RESUME),
            listOf(DraftFlowEvent.Opened, DraftFlowEvent.Cancel),
        )
        assertEquals(DraftFlowState.Back(), state)
        assertNull((state as DraftFlowState.Back).error)
    }

    @Test
    fun failedCreationGoesBackWithTheReason() {
        val state = advanceDraftFlow(
            DraftFlowState.Create,
            DraftFlowEvent.Created(ok = false, error = "a draft already exists; use --force"),
        )
        assertEquals(DraftFlowState.Back("a draft already exists; use --force"), state)
    }

    @Test
    fun eventsThatDoNotApplyLeaveTheStateAlone() {
        assertEquals(
            DraftFlowState.Wait(),
            advanceDraftFlow(DraftFlowState.Wait(), DraftFlowEvent.Built(ok = true)),
        )
        assertEquals(
            DraftFlowState.Create,
            advanceDraftFlow(DraftFlowState.Create, DraftFlowEvent.Continue),
        )
        assertEquals(
            DraftFlowState.Open,
            advanceDraftFlow(DraftFlowState.Open, DraftFlowEvent.Cancel),
        )
    }

    @Test
    fun doneAndBackAreTerminal() {
        val done = DraftFlowState.Done(ReviewLayout.WALK)
        assertEquals(done, advanceDraftFlow(done, DraftFlowEvent.Cancel))
        val back = DraftFlowState.Back("boom")
        assertEquals(back, advanceDraftFlow(back, DraftFlowEvent.Continue))
    }

    @Test
    fun offersIncludeKeysOnlyWhenReported() {
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

    @Test
    fun gitdirLinkIsReadForWorktreesAndSubmodules() {
        assertEquals("/repo/.git/worktrees/wt1", gitdirFromLink("gitdir: /repo/.git/worktrees/wt1\n"))
        assertEquals("../.git/modules/sub", gitdirFromLink("gitdir: ../.git/modules/sub"))
        assertEquals(
            "C:/repo/.git/worktrees/wt1",
            gitdirFromLink("gitdir:   C:/repo/.git/worktrees/wt1  \r\n"),
        )
        assertNull(gitdirFromLink(""))
        assertNull(gitdirFromLink("ref: refs/heads/main\n"))
        assertNull(gitdirFromLink("gitdir:\n"))
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
        // Nunca --force desde un cliente.
        assertFalse(
            draftArgs("feature/x", ReviewSource.REMOTE, ReviewRange.FULL, build = false)
                .contains("--force"),
        )
    }

    // --- aviso de espera (paridad con draftWaitMessage en draftFlow.ts) ----------

    @Test
    fun waitMessageAsksToFillTheDraftWhenItIsOnScreen() {
        assertEquals(
            "Fill in the reading order for feature/x, then continue.",
            UserCopy.draftWaitMessage("feature/x", null, null),
        )
        assertEquals(
            "The draft is not valid yet: no entries found",
            UserCopy.draftWaitMessage("feature/x", "no entries found", null),
        )
    }

    @Test
    fun waitMessageSaysWhereTheDraftIsWhenItCouldNotBeOpened() {
        // El caso real: el proyecto abierto es una subcarpeta del repo, <cwd>/.git
        // no existe, el borrador se escribio igual y la ruta solo va por el stdout
        // de la CLI, que ningun cliente muestra.
        assertEquals(
            "Fill in the reading order for feature/x, then continue. It could not be opened here" +
                " — the draft is at /repo/.git/review-walkthrough/feature/x.md.",
            UserCopy.draftWaitMessage(
                "feature/x",
                null,
                UnopenedDraft("/repo/.git/review-walkthrough/feature/x.md"),
            ),
        )
        // Y sigue diciendolo cuando el aviso vuelve con el motivo de un rechazo.
        assertEquals(
            "The draft is not valid yet: no entries found It could not be opened here" +
                " — the draft is at /repo/.git/review-walkthrough/feature/x.md.",
            UserCopy.draftWaitMessage(
                "feature/x",
                "no entries found",
                UnopenedDraft("/repo/.git/review-walkthrough/feature/x.md"),
            ),
        )
    }

    @Test
    fun waitMessageNamesTheRelativeFileWhenThePathCouldNotBeBuilt() {
        assertEquals(
            "Fill in the reading order for feature/x, then continue. It could not be opened here" +
                " — look for review-walkthrough/feature/x.md inside this repository's git directory.",
            UserCopy.draftWaitMessage("feature/x", null, UnopenedDraft(null)),
        )
    }
}
