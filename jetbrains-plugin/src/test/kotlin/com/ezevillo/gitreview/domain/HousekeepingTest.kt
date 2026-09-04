package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Las diez formas de limpiar, cada una con su argv y su cartel.
 *
 * Se recorre el enum entero en vez de nombrar unos pocos casos: son los verbos
 * destructivos del producto, y una variante nueva sin argv --o con el argv de
 * otra-- borra ramas que nadie pidio borrar. Un `when` exhaustivo compila igual
 * con la rama nueva copiada de la de al lado.
 */
class HousekeepingTest {
    private val needSource = setOf(
        HousekeepingKind.CLEAN_ONE,
        HousekeepingKind.CLEAN_KEEP_FIXES,
        HousekeepingKind.CLEAN_FIXES_ONE,
        HousekeepingKind.FORGET_SAVED_ONE,
        HousekeepingKind.FORGET_DELTA_ONE,
    )

    @Test
    fun everyKindHasItsOwnArgv() {
        val expected = mapOf(
            HousekeepingKind.CLEAN_ONE to listOf("f"),
            HousekeepingKind.CLEAN_KEEP_FIXES to listOf("--keep-fixes", "f"),
            HousekeepingKind.CLEAN_FIXES_ONE to listOf("--fixes-only", "f"),
            HousekeepingKind.CLEAN_FIXES_ONE_ALL to listOf("--fixes-only"),
            HousekeepingKind.CLEAN_ALL to emptyList(),
            HousekeepingKind.FORGET_SAVED_ONE to listOf("--saved", "f"),
            HousekeepingKind.FORGET_SAVED_ALL to listOf("--saved", "--all"),
            HousekeepingKind.FORGET_DELTA_ONE to listOf("--delta", "f"),
            HousekeepingKind.FORGET_DELTA_ALL to listOf("--delta", "--all"),
            HousekeepingKind.FORGET_DELTA_STALE to listOf("--delta", "--stale"),
        )
        assertEquals(HousekeepingKind.entries.toSet(), expected.keys)
        for ((kind, args) in expected) {
            assertEquals(args, argsForHousekeeping(HousekeepingAction(kind, "f")), kind.name)
        }
        // Y no hay dos que manden lo mismo: son diez operaciones distintas.
        assertEquals(expected.values.size, expected.values.toSet().size)
    }

    @Test
    fun theVerbFollowsTheNameOfTheKind() {
        for (kind in HousekeepingKind.entries) {
            val verb = verbForHousekeeping(HousekeepingAction(kind, "f"))
            assertEquals(if (kind.name.startsWith("CLEAN")) "clean" else "forget", verb, kind.name)
        }
    }

    /**
     * `--stale` es el unico que consulta el remoto, y por eso el unico que pide
     * la red: los demas se resuelven contra refs locales.
     */
    @Test
    fun onlyForgettingTheBranchesThatAreGoneTouchesTheNetwork() {
        for (kind in HousekeepingKind.entries) {
            assertEquals(
                kind == HousekeepingKind.FORGET_DELTA_STALE,
                housekeepingNeedsNetwork(HousekeepingAction(kind, "f")),
                kind.name,
            )
        }
    }

    /**
     * Sin rama no hay comando: un `clean` al que se le cae el argumento es un
     * `clean` de todo. Se rechaza aca antes de armar el argv, no despues.
     */
    @Test
    fun theKindsThatActOnOneBranchRefuseAnEmptySource() {
        for (kind in needSource) {
            assertThrows(IllegalArgumentException::class.java, { argsForHousekeeping(HousekeepingAction(kind)) }, kind.name)
            assertThrows(IllegalArgumentException::class.java, { argsForHousekeeping(HousekeepingAction(kind, "")) }, kind.name)
        }
        // Y las que actuan sobre todo no lo piden.
        for (kind in HousekeepingKind.entries - needSource) {
            assertTrue(argsForHousekeeping(HousekeepingAction(kind)).none { it == "" }, kind.name)
        }
    }

    /**
     * Todas se confirman, y ninguna reusa el cartel de otra: el titulo es lo que
     * distingue borrar una rama de borrarlas todas.
     */
    @Test
    fun everyKindHasItsOwnConfirmation() {
        val titles = HousekeepingKind.entries.map { kind ->
            val copy = confirmCopyFor(HousekeepingAction(kind, "feature/x"))
            assertTrue(copy.title.isNotBlank(), kind.name)
            assertTrue(copy.detail.isNotBlank(), kind.name)
            assertTrue(copy.button.isNotBlank(), kind.name)
            // Ni el cartel ni el boton nombran el argv: eso es el detalle
            // tecnico, y va a un clic de distancia.
            assertFalse(copy.title.contains("--"), kind.name)
            assertFalse(copy.button.contains("--"), kind.name)
            copy.title
        }
        assertEquals(titles.size, titles.toSet().size)
    }

    /**
     * Un solo verbo para borrar en toda la superficie. "Delete" para lo que se
     * va, "Forget" para lo que se olvida (el punto de la ultima review), y
     * "Done" para el que cierra el ciclo.
     */
    @Test
    fun theButtonsUseOneVerbPerConcept() {
        assertEquals(
            setOf("Delete", "Delete all", "Keep edits & remove Undo", "Forget", "Forget all"),
            HousekeepingKind.entries.map { confirmCopyFor(HousekeepingAction(it, "f")).button }.toSet(),
        )
    }

    /**
     * Cuanto cuesta borrar una rama de ediciones lo contesta la CLI, y cada
     * respuesta tiene su frase: "no hay nada commiteado" no es "es seguro porque
     * ya esta integrado", y "no se sabe" no es "no esta integrado".
     */
    @Test
    fun theCostOfDeletingExtractedEditsIsSaidPerState() {
        fun detail(state: FixesState?) = confirmCopyFor(
            HousekeepingAction(HousekeepingKind.CLEAN_FIXES_ONE, "f", fixesState = state),
        ).detail

        assertTrue(detail(FixesState.EMPTY).startsWith("Nothing was ever committed on it"))
        assertTrue(detail(FixesState.MERGED).startsWith("Its commits are already in the base branch."))
        assertTrue(detail(FixesState.UNMERGED).contains("deleting it loses them"))
        // Sin dato de la CLI, se dice que no se sabe -- nunca que es seguro.
        val unknown = detail(null)
        assertTrue(unknown.contains("git cannot tell whether its commits are integrated"))
        assertEquals(unknown, detail(FixesState.UNKNOWN))

        val four = listOf(FixesState.EMPTY, FixesState.MERGED, FixesState.UNMERGED, null).map(::detail)
        assertEquals(four.size, four.toSet().size)
    }

    /**
     * La sesion se nombra solo cuando existe: prometer que queda algo que no
     * esta es ruido, y el argv es el mismo en los dos casos.
     */
    @Test
    fun theSessionIsNamedOnlyWhenItIsThere() {
        val with = HousekeepingAction(HousekeepingKind.CLEAN_FIXES_ONE, "f", session = true)
        val without = HousekeepingAction(HousekeepingKind.CLEAN_FIXES_ONE, "f", session = false)
        assertTrue(confirmCopyFor(with).detail.contains("You can still undo the finish afterwards."))
        assertFalse(confirmCopyFor(without).detail.contains("undo the finish"))
        assertEquals(argsForHousekeeping(with), argsForHousekeeping(without))
    }

    /**
     * El cartel del boton que cierra el ciclo dice PRIMERO lo que se conserva, y
     * nombra el destino real de las ediciones -- que con `--onto-source` es la
     * rama del PR y no `review-fixes/`.
     */
    @Test
    fun theClosingConfirmationNamesWhereTheEditsStayed() {
        val separate = confirmCopyFor(HousekeepingAction(HousekeepingKind.CLEAN_KEEP_FIXES, "feature/x"))
        assertEquals("Keep your edits & remove Undo?", separate.title)
        assertEquals("Keep edits & remove Undo", separate.button)
        assertTrue(separate.detail.startsWith("Your edits stay on review-fixes/feature/x"), separate.detail)

        val onto = confirmCopyFor(
            HousekeepingAction(HousekeepingKind.CLEAN_KEEP_FIXES, "feature/x", onto = true),
        )
        assertTrue(onto.detail.startsWith("Your edits stay on feature/x -"), onto.detail)
        assertFalse(onto.detail.contains("review-fixes/"))
    }

    @Test
    fun theSourceIsReadOffAnyOfTheThreePrefixes() {
        assertEquals("feature/x", sourceFromReviewName("review/feature/x"))
        assertEquals("feature/x", sourceFromReviewName("review-saved/feature/x"))
        assertEquals("feature/x", sourceFromReviewName("review-fixes/feature/x"))
        // `review-saved/` se prueba antes que `review/`, o quedaria "saved/x".
        assertEquals("x", sourceFromReviewName("review-saved/x"))
        // Una rama que no es de review vuelve entera, sin recortes.
        assertEquals("feature/review/x", sourceFromReviewName("feature/review/x"))
        assertEquals("main", sourceFromReviewName("main"))
    }

    @Test
    fun thePendingFinishIsFoundOnlyInItsOwnSituation() {
        val pending = BranchRecord(
            "review/feature",
            saved = false,
            current = true,
            orphan = false,
            finish = BranchFinish("pending", onto = true),
        )
        val state = ReviewState(situation = Situation.FINISH_PENDING, branches = listOf(pending))
        assertEquals("feature" to true, pendingFinishInfo(state))
        assertEquals("feature", pendingFinishSource(state))

        // La misma rama en otra situacion no cuenta: el banner es de finish-pending.
        assertNull(pendingFinishInfo(state.copy(situation = Situation.NO_REVIEW)))
        // Y en finish-pending sin ninguna rama pendiente tampoco se inventa una.
        assertNull(pendingFinishInfo(state.copy(branches = emptyList())))
        assertNull(
            pendingFinishInfo(
                state.copy(branches = listOf(pending.copy(finish = BranchFinish("conflict", onto = false)))),
            ),
        )
        assertNull(pendingFinishSource(state.copy(branches = emptyList())))
    }
}
