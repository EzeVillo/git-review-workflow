package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class ConfigPorcelainTest {
    @Test
    fun parseFull() {
        val out = """
            config	base	main
            config	remote	origin
            candidate	feature	remote	1
            candidate	feature	local	0
            remote-candidate	origin	1
            delta	feature	abc	remote
            offer	walk	recommended
            offer	step	available
        """.trimIndent()
        val r = parseConfigPorcelain(out)
        assertEquals("main", r.config.base)
        assertEquals("origin", r.config.remote)
        assertEquals(2, r.candidates.size)
        assertEquals(1, r.remotes.size)
        assertEquals(1, r.deltas?.size)
        assertEquals(2, r.offers?.size)
        assertEquals("abc", deltaForSource(r.deltas, "remote")?.tip)
        assertNull(deltaForSource(r.deltas, "local"))
    }

    /** 011: los ids nuevos se parsean, y el orden del selector los ubica. */
    @Test
    fun draftOffersParseAndOrder() {
        val out = """
            config	remote	origin
            offer	draft	available
            offer	step	available
            offer	whole	available
        """.trimIndent()
        val r = parseConfigPorcelain(out)
        assertEquals(
            listOf(OfferId.DRAFT, OfferId.STEP, OfferId.WHOLE),
            r.offers?.map { it.id },
        )
        val items = buildLayoutItems(r.offers)
        assertEquals(listOf("Build a reading order first", "Commit by commit", "Whole diff"), items.map { it.label })
        assertEquals(DraftStep.CREATE, items[0].draft)
        assertEquals(ReviewLayout.WALK, items[0].layout)
        assertNull(items[1].draft)
    }

    @Test
    fun draftResumeSitsBehindWalkRecommended() {
        val out = """
            config	remote	origin
            offer	walk	recommended
            offer	draft-resume	available
            offer	step	available
        """.trimIndent()
        val items = buildLayoutItems(parseConfigPorcelain(out).offers)
        assertEquals(
            listOf("Walkthrough (recommended)", "Finish the reading order you started", "Commit by commit"),
            items.map { it.label },
        )
        assertNull(items[0].draft)
        assertEquals(DraftStep.RESUME, items[1].draft)
        assertEquals("pick up the one you left half-written", items[1].description)
    }

    @Test
    fun unknownOfferIdsAreStillDropped() {
        val out = """
            config	remote	origin
            offer	drafts	available
            offer	draft_resume	available
            offer	draft	available
        """.trimIndent()
        assertEquals(listOf(OfferId.DRAFT), parseConfigPorcelain(out).offers?.map { it.id })
    }

    @Test
    fun remoteDefaultsToOrigin() {
        val r = parseConfigPorcelain("")
        assertEquals("origin", r.config.remote)
        assertNull(r.config.base)
    }

    @Test
    fun branchPickerCollapsesOriginsAndPutsCurrentFirst() {
        val candidates = listOf(
            CandidateBranch("main", "remote", current = false),
            CandidateBranch("feature/checkout", "remote", current = false),
            CandidateBranch("feature/checkout", "local", current = true),
            CandidateBranch("develop", "local", current = false),
        )
        val items = branchPickerItems(candidates)
        assertEquals(
            listOf("feature/checkout", "develop", "main"),
            items.map { it.name },
        )
        assertEquals(true, items[0].current)
        assertEquals(
            listOf("feature/checkout  (current)", "develop", "main"),
            items.map { branchPickerLabel(it) },
        )
    }

    @Test
    fun branchPickerEmptyWhenNoCandidates() {
        assertEquals(emptyList<CandidateBranch>(), branchPickerItems(emptyList()))
    }

    // --- registros draft (012) --------------------------------------------------

    @Test
    fun draftRecordsParseTheirSevenFields() {
        val out = """
            config	remote	origin
            draft	feature/checkout	/repo/.git/review-walkthrough/feature/checkout.md	3	9	local	delta
        """.trimIndent()
        assertEquals(
            listOf(
                DraftRecord(
                    src = "feature/checkout",
                    path = "/repo/.git/review-walkthrough/feature/checkout.md",
                    annotated = 3,
                    total = 9,
                    source = DraftSource.LOCAL,
                    range = DraftRange.DELTA,
                ),
            ),
            parseConfigPorcelain(out).drafts,
        )
    }

    @Test
    fun withoutDraftRecordsTheListIsEmptyNeverNull() {
        assertEquals(emptyList<DraftRecord>(), parseConfigPorcelain("config\tremote\torigin\n").drafts)
    }

    @Test
    fun draftRecordsKeepTheCliOrder() {
        val out = """
            draft	feature/telemetry	/repo/.git/review-walkthrough/feature/telemetry.md	0	5	remote	full
            draft	feature/checkout	/repo/.git/review-walkthrough/feature/checkout.md	3	9	local	delta
        """.trimIndent()
        assertEquals(
            listOf("feature/telemetry", "feature/checkout"),
            parseConfigPorcelain(out).drafts.map { it.src },
        )
    }

    @Test
    fun anUnknownSourceOrRangeReadsAsUnknown() {
        // Es lo que la CLI emite cuando el bloque de instrucciones se borró a
        // mano, y también lo único honesto para un valor que agregue una CLI más
        // nueva: en los dos casos este cliente no puede replicar los flags.
        val out = "draft\tfeature/x\t/repo/.git/review-walkthrough/feature/x.md\t0\t2\tunknown\tunknown"
        val draft = parseConfigPorcelain(out).drafts.single()
        assertEquals(DraftSource.UNKNOWN, draft.source)
        assertEquals(DraftRange.UNKNOWN, draft.range)
    }

    @Test
    fun aMalformedDraftRecordIsIgnoredWhole() {
        // Media fila de progreso sería peor que ninguna: un total que no es un
        // entero no se puede dibujar como "3/N" sin inventar el N.
        val out = """
            draft	feature/x	/repo/.git/review-walkthrough/feature/x.md	many	2	remote	full
            draft		/repo/.git/review-walkthrough/feature/y.md	0	2	remote	full
            draft	feature/z
            draft	feature/ok	/repo/.git/review-walkthrough/feature/ok.md	1	2	remote	full
        """.trimIndent()
        assertEquals(listOf("feature/ok"), parseConfigPorcelain(out).drafts.map { it.src })
    }
}
