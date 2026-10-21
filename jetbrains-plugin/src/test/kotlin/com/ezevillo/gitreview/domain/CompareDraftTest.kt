package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class CompareDraftTest {
    @Test
    fun comparisonDraftKeepsItsIdentityAndStartsCompare() {
        val id = "compare/0123456789012345678901234567890123456789"
        val row = "draft\t$id\t/repo/.git/order.md\t2\t2\tcompare\tfull\tfresh"
        val title = "draft-title\t$id\tmain → release"
        for (text in listOf("$row\n$title", "$title\n$row")) {
            val draft = parseConfigPorcelain(text).drafts.single()
            assertEquals(id, draft.src)
            assertEquals("main → release", draft.title)
            assertEquals(DraftSource.COMPARE, draft.source)
            assertEquals(listOf("draft", "--build", "--compare", "--", id), draftArgs(id, ReviewSource.COMPARE, ReviewRange.FULL, build = true))
            assertEquals(listOf("--porcelain", "--compare", "--", id), draftConfigArgs(id, ReviewSource.COMPARE, ReviewRange.FULL))
            val intent = ReviewIntent(id, ReviewLayout.KEYS, ReviewRange.FULL, ReviewSource.COMPARE)
            val argv = actionToArgv("startReview", ActionParams.Start(intent, "main"))
            assertEquals("compare", argv.verb)
            assertEquals(listOf("--keys", "--draft", "--", id), argv.args)
            assertFalse(argv.network)
            val model = buildPanelModel(ReviewState(situation = Situation.NO_REVIEW, config = EffectiveConfig(base = null, remote = "origin"), drafts = listOf(draft)), PanelInputs(busy = false))
            assertTrue(model.noBaseConfigured)
            val layout = panelLayout(model)
            val controls = layout.collectControls()
            assertTrue(controls.any { it.id == ControlId.START_FROM_DRAFT && it.enabled })
            assertTrue(controls.any { it.id == ControlId.COMPARE_REVIEW && it.enabled })
            val rows = layout.blocks.filterIsInstance<Block.DraftRows>().single().rows
            assertEquals("main → release", rows.single().name)
        }
    }
}
