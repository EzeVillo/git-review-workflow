package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * El filtro detrás de todo picker. Lo que se afirma acá no es "filtra" sino las
 * dos cosas que devuelven la rama equivocada en silencio cuando se rompen: una
 * fila siempre significa la opción de la que salió, se filtre lo que se filtre, y
 * la fila de texto libre —la única sin opción detrás— es la elegida mientras está.
 *
 * Espejo de `PickerRowsTests` del cliente de Visual Studio.
 */
class PickerRowsTest {
    private val branches = listOf(
        "main",
        "develop",
        "feature/checkout",
        "feature/cart",
        "release/2.0",
    )

    @Test
    fun `an empty needle keeps every option in order`() {
        assertEquals(listOf(0, 1, 2, 3, 4), PickerRows.rows(branches, "", freeText = false))
    }

    @Test
    fun `rows carry the index into the caller list not the visible position`() {
        // Las dos feature/* son la 3ra y 4ta opcion, no la 1ra y 2da fila.
        assertEquals(listOf(2, 3), PickerRows.rows(branches, "feature/", freeText = false))
    }

    @Test
    fun `the filter is case insensitive and matches anywhere`() {
        assertEquals(listOf(2), PickerRows.rows(branches, "CHECKOUT", freeText = false))
        assertEquals(listOf(4), PickerRows.rows(branches, "2.0", freeText = false))
    }

    @Test
    fun `a needle that matches nothing leaves no rows`() {
        assertTrue(PickerRows.rows(branches, "nope", freeText = false).isEmpty())
    }

    @Test
    fun `without free text a typed value is never offered as a row`() {
        val rows = PickerRows.rows(branches, "v1.2.3", freeText = false)
        assertTrue(rows.isEmpty(), "rows=$rows")
        assertFalse(rows.contains(PickerRows.TYPED))
    }

    @Test
    fun `free text offers the typed value first when it matches no option`() {
        assertEquals(listOf(PickerRows.TYPED), PickerRows.rows(branches, "v1.2.3", freeText = true))
    }

    @Test
    fun `free text keeps the matches behind the typed row`() {
        assertEquals(
            listOf(PickerRows.TYPED, 2, 3),
            PickerRows.rows(branches, "feature", freeText = true),
        )
    }

    @Test
    fun `free text does not duplicate an option typed in full`() {
        val rows = PickerRows.rows(branches, "main", freeText = true)
        assertEquals(listOf(0), rows)
        assertFalse(rows.contains(PickerRows.TYPED))
    }

    @Test
    fun `surrounding whitespace is not part of the needle`() {
        assertEquals(listOf(0), PickerRows.rows(branches, "  main  ", freeText = true))
    }

    // -- selection ----------------------------------------------------------

    @Test
    fun `with no rows nothing is selected`() {
        assertEquals(PickerRows.NONE, PickerRows.selection(emptyList(), keep = 2))
    }

    @Test
    fun `the previous selection survives a filter that still shows it`() {
        val rows = PickerRows.rows(branches, "feature/", freeText = false)
        // La opcion 3 es feature/cart, que sigue visible: fila 1 de las dos que quedan.
        assertEquals(1, PickerRows.selection(rows, keep = 3))
    }

    @Test
    fun `a previous selection that got filtered away falls back to the first row`() {
        val rows = PickerRows.rows(branches, "feature/", freeText = false)
        assertEquals(0, PickerRows.selection(rows, keep = 0))
    }

    /**
     * El caso que motiva todo: tipear un SHA con una rama seleccionada de antes y
     * que aceptar mande la rama. La fila de texto libre gana mientras está.
     */
    @Test
    fun `the typed row wins the selection over a previous pick`() {
        val rows = PickerRows.rows(branches, "feature", freeText = true)
        assertEquals(PickerRows.TYPED, rows.first())
        assertEquals(0, PickerRows.selection(rows, keep = 3))
    }

    @Test
    fun `with no previous pick the first row is selected`() {
        val rows = PickerRows.rows(branches, "", freeText = false)
        assertEquals(0, PickerRows.selection(rows, keep = null))
    }
}
