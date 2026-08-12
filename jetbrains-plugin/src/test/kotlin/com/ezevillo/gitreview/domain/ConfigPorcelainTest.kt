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
        assertEquals(listOf("Walkthrough — draft one", "Commit by commit", "Whole diff"), items.map { it.label })
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
            listOf("Walkthrough (recommended)", "Walkthrough — continue draft", "Commit by commit"),
            items.map { it.label },
        )
        assertNull(items[0].draft)
        assertEquals(DraftStep.RESUME, items[1].draft)
        assertEquals("finish the reading order you started", items[1].description)
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
}
