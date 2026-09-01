package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.yaml.snakeyaml.Yaml
import java.io.File

/**
 * `revealsPanel(id)` coincide con `reveals:` del canonico, Y gobierna.
 *
 * Los tres chequeos son los mismos que cuidan `confirms:`, y estan acá por la
 * leccion que dejo esa tabla: durante un tiempo se declaraba en tres lugares y no
 * gobernaba en ninguno, porque nadie la consultaba para decidir. Una tabla nueva
 * nace con su gate o nace decorativa.
 */
class RevealContractTest {
    @Test
    fun `revealsPanel matches the canonical reveals list`() {
        val expected = canonicalReveals()
        assertFalse(expected.isEmpty(), "canonical: reveals: is empty or missing")
        for (id in ControlId.entries) {
            val want = id.wire in expected
            assertTrue(
                want == revealsPanel(id),
                "reveals mismatch for ${id.wire}: canonical says $want",
            )
        }
    }

    @Test
    fun `every revealing id is passed through the single gate`() {
        // El id REALMENTE pasado, del argumento y no buscado suelto en el
        // archivo: un `contains` da verde con el call site cambiado.
        //
        // Dos entradas y no una: los dos caminos que llegan al start comparten
        // runStart, que recibe el id y delega. Si aparece una tercera
        // delegacion, el gate la reclama sola -- su id no va a estar en el set.
        val gate = Regex(
            """(?:revealPanel|runStart)\(.*?ControlId\.([A-Z_]+)""",
            RegexOption.DOT_MATCHES_ALL,
        )
        val passed = uiSources().flatMap { (_, text) ->
            gate.findAll(text).map { it.groupValues[1] }.toList()
        }.toSet()
        for (id in ControlId.entries) {
            if (!revealsPanel(id)) continue
            assertTrue(
                id.name in passed,
                "${id.wire} is in reveals: but is never passed to revealPanel",
            )
        }
        for (name in passed) {
            val id = ControlId.entries.first { it.name == name }
            assertTrue(
                revealsPanel(id),
                "revealPanel is called with ${id.wire}, which the canonical does not list under reveals:",
            )
        }
    }

    @Test
    fun `no other surface brings the tool window to the front`() {
        // El vehiculo es ToolWindowManager, y vive en PanelReveal.kt. Cualquier
        // otro llamador se saltearia la tabla. GitReviewToolWindowFactory es la
        // excepcion obvia: es quien la construye, y ahi no revela nada.
        for ((file, text) in allSources()) {
            if (file.name == "PanelReveal.kt" || file.name == "GitReviewToolWindowFactory.kt") continue
            assertFalse(
                text.contains("ToolWindowManager"),
                "${file.name} reaches the tool window itself; it must go through revealPanel",
            )
        }
    }

    /**
     * Los ids de `reveals.intellij`, leidos como lista de escalares.
     *
     * `reveals:` es un mapa POR CLIENTE desde que entro la TUI, que declara la
     * suya vacia. Leerlo como lista plana devolvia un set vacio y el gate se
     * caia en el `assertFalse` de arriba en vez de comparar nada -- fallaba
     * ruidosamente, que es lo que se queria, pero la tabla igual dejo de
     * gobernar. El cliente se nombra, y su ausencia es un fallo: un renombre de
     * la clave no puede degradar a "no revela nada".
     */
    private fun canonicalReveals(): Set<String> {
        val file = File(monorepoRoot(), "contracts/client-product-surface.yaml")
        require(file.isFile) { "canonical missing at ${file.absolutePath}" }
        @Suppress("UNCHECKED_CAST")
        val yaml = Yaml().load(file.readText()) as Map<String, Any?>
        val reveals = yaml["reveals"] as? Map<String, Any?>
        require(reveals != null) { "canonical: reveals: is missing or is not a per-client map" }
        val mine = reveals[CLIENT]
        require(mine is List<*>) { "canonical: reveals: has no list for $CLIENT" }
        return mine.map { it as String }.toSet()
    }

    private fun uiSources(): List<Pair<File, String>> = sourcesUnder("ui")

    private fun allSources(): List<Pair<File, String>> = sourcesUnder("")

    private fun sourcesUnder(sub: String): List<Pair<File, String>> {
        val base = File(monorepoRoot(), "jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview")
        val dir = if (sub.isEmpty()) base else File(base, sub)
        require(dir.isDirectory) { "sources missing at ${dir.absolutePath}" }
        val files = dir.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()
        require(files.isNotEmpty()) { "no sources found under ${dir.absolutePath}" }
        return files.map { it to it.readText() }
    }

    private companion object {
        /** La clave de este cliente en el canonico. */
        const val CLIENT = "intellij"
    }

    private fun monorepoRoot(): String =
        System.getProperty("git.review.monorepo.root") ?: File("..").canonicalPath
}
