package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Las ofertas de lectura del asistente y los flags que salen de elegirlas.
 *
 * `buildLayoutItems` ya lo miraban los tests de config porcelain; lo que no
 * miraba nadie era la otra punta -- el resumen que va al cartel de compare y el
 * argv que arma el start.
 */
class LayoutOffersTest {
    @Test
    fun everyLayoutHasItsOwnSummary() {
        assertEquals("as a walkthrough", layoutSummary(ReviewLayout.WALK))
        assertEquals("keys only", layoutSummary(ReviewLayout.KEYS))
        assertEquals("commit by commit", layoutSummary(ReviewLayout.STEP))
        assertEquals("as the whole diff", layoutSummary(ReviewLayout.WHOLE))

        val all = ReviewLayout.entries.map(::layoutSummary)
        assertEquals(all.size, all.toSet().size)
        // Es prosa dentro de una pregunta, no vocabulario de git ni un flag.
        assertTrue(all.none { it.contains("--") }, all.toString())
    }

    /**
     * Los flags de origen y de rango, que son los DOS ejes que el asistente
     * ofrece aparte de la forma de leer. `remote` y `full` son los defaults de la
     * CLI, asi que no llevan flag: mandarlos igual seria fijar de este lado un
     * default que es de la CLI.
     */
    @Test
    fun onlyTheNonDefaultChoicesBecomeFlags() {
        assertEquals(emptyList<String>(), offerConfigFlags(ReviewSource.REMOTE, ReviewRange.FULL))
        assertEquals(listOf("--local"), offerConfigFlags(ReviewSource.LOCAL, ReviewRange.FULL))
        assertEquals(listOf("--offline"), offerConfigFlags(ReviewSource.OFFLINE, ReviewRange.FULL))
        assertEquals(listOf("--delta"), offerConfigFlags(ReviewSource.REMOTE, ReviewRange.DELTA))
        // Y se combinan en ese orden: primero el origen, despues el rango.
        assertEquals(listOf("--local", "--delta"), offerConfigFlags(ReviewSource.LOCAL, ReviewRange.DELTA))
        assertEquals(listOf("--offline", "--delta"), offerConfigFlags(ReviewSource.OFFLINE, ReviewRange.DELTA))
    }

    /**
     * Sin filas `offer` de la CLI el asistente igual ofrece algo, y lo que ofrece
     * son las dos formas que no dependen de que el PR traiga un walkthrough.
     */
    @Test
    fun withoutOffersTheFallbackIsTheTwoThatAlwaysWork() {
        for (empty in listOf<List<ReadingOffer>?>(null, emptyList())) {
            val items = buildLayoutItems(empty)
            assertEquals(listOf(ReviewLayout.STEP, ReviewLayout.WHOLE), items.map { it.layout }, "$empty")
            assertTrue(items.all { it.draft == null })
        }
        assertEquals(FALLBACK_OFFERS, effectiveOffers(null))
        assertEquals(FALLBACK_OFFERS, effectiveOffers(emptyList()))
    }

    /**
     * La recomendada sube al tope y se anuncia en la etiqueta Y en la
     * descripcion: la lista se lee de arriba abajo, pero tambien de costado.
     */
    @Test
    fun theRecommendedOfferLeadsAndSaysSo() {
        val items = buildLayoutItems(
            listOf(
                ReadingOffer(OfferId.STEP, OfferRank.AVAILABLE),
                ReadingOffer(OfferId.WHOLE, OfferRank.AVAILABLE),
                ReadingOffer(OfferId.WALK, OfferRank.RECOMMENDED),
            ),
        )
        assertEquals(ReviewLayout.WALK, items[0].layout)
        assertEquals("Walkthrough (recommended)", items[0].label)
        assertTrue(items[0].description.endsWith("(recommended)"))
        // Las demas conservan el orden canonico, no el de llegada.
        assertEquals(listOf(ReviewLayout.WALK, ReviewLayout.STEP, ReviewLayout.WHOLE), items.map { it.layout })
        assertTrue(items.drop(1).none { it.label.contains("recommended") })
    }

    /**
     * Las tres filas de borrador llevan su paso, y todas dicen que la forma
     * resultante es el walkthrough: elegir una no es elegir otra manera de leer,
     * es escribir la que el PR no trae.
     */
    @Test
    fun theDraftOffersCarryTheirStep() {
        val steps = mapOf(
            OfferId.DRAFT to DraftStep.CREATE,
            OfferId.DRAFT_RESUME to DraftStep.RESUME,
            OfferId.DRAFT_UPDATE to DraftStep.UPDATE,
        )
        for ((id, step) in steps) {
            val item = buildLayoutItems(listOf(ReadingOffer(id, OfferRank.AVAILABLE))).single()
            assertEquals(step, item.draft, id.name)
            assertEquals(ReviewLayout.WALK, item.layout, id.name)
            assertTrue(item.label.isNotBlank(), id.name)
        }
        assertEquals(steps.values.toSet(), DraftStep.entries.toSet())
    }
}
