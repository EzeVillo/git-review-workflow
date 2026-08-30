package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class CliMessageTest {
    // El registro existe porque leer la FRASE del verbo por stdout seria parsear
    // salida humana; los tres numeros llegan en campos aparte.
    @Test
    fun readsTheThreeNumbersOfTheRecord() {
        assertEquals(MergedCounts(1, 2, 3), parseMergedRecord("merged\t1\t2\t3\n"))
    }

    @Test
    fun findsTheRecordAmongOtherLines() {
        assertEquals(MergedCounts(0, 1, 0), parseMergedRecord("otra\tcosa\nmerged\t0\t1\t0\n"))
    }

    // Sin registro el llamador se calla: una CLI vieja imprime solo la frase humana,
    // y ahi la respuesta correcta es no acusar nada.
    @Test
    fun withoutTheRecordItReturnsNullRatherThanInventing() {
        assertNull(parseMergedRecord(""))
        assertNull(parseMergedRecord("updated /tmp/x.md: 1 kept, 2 added, 3 dropped\n"))
        // Tampoco cuenta un registro con menos de tres campos, ni uno con un campo no numerico.
        assertNull(parseMergedRecord("merged\t1\t2\n"))
        assertNull(parseMergedRecord("merged\t1\tdos\t3\n"))
    }

    @Test
    fun namesTheThreeThingsWhenTheThreeHappened() {
        assertEquals(
            "Reading order updated: 3 kept, 1 added, 2 no longer in the PR.",
            UserCopy.draftUpdated(3, 1, 2),
        )
    }

    // Los ceros no se dicen: leer "0 added" para enterarse de que no paso nada
    // es el ruido que esta frase evita.
    @Test
    fun omitsTheZeroRatherThanEnumeratingIt() {
        assertEquals("Reading order updated: 3 kept, 1 added.", UserCopy.draftUpdated(3, 1, 0))
        assertEquals(
            "Reading order updated: 3 kept, 2 no longer in the PR.",
            UserCopy.draftUpdated(3, 0, 2),
        )
    }

    // Un update que no mueve nada es un resultado real, no un no-op: el rango
    // se corrio sin cambiar que archivos toca, y sin frase no habria senal de eso.
    @Test
    fun anUpdateThatMovedNothingStillSaysWhatHappened() {
        assertEquals("Reading order updated: nothing moved, 4 kept.", UserCopy.draftUpdated(4, 0, 0))
    }

    // Ninguna de las tres frases nombra un comando ni una ruta: eso era el stdout que reemplazan.
    @Test
    fun namesNoCommandAndNoPath() {
        for (text in listOf(
            UserCopy.draftUpdated(3, 1, 2),
            UserCopy.draftUpdated(3, 1, 0),
            UserCopy.draftUpdated(4, 0, 0),
        )) {
            assertFalse(text.contains("git review"), text)
            assertFalse(text.contains("/"), text)
            assertTrue(text.startsWith("Reading order updated:"), text)
        }
    }
}
