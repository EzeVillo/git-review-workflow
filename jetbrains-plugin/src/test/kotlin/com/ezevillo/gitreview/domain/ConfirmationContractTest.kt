package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.yaml.snakeyaml.Yaml
import java.io.File

/**
 * FR-032: requiresConfirmation(id) matches confirms: in the canonical YAML.
 */
class ConfirmationContractTest {
    @Test
    fun `requiresConfirmation matches canonical confirms for all ControlIds`() {
        val yaml = loadCanonical()
        val expected = HashMap<String, Boolean>()

        @Suppress("UNCHECKED_CAST")
        fun walk(node: Any?) {
            when (node) {
                is Map<*, *> -> {
                    val id = node["id"] as? String
                    if (id != null) {
                        val confirms = node["confirms"] as? Boolean ?: false
                        expected[id] = expected[id] == true || confirms
                    }
                    val control = node["control"] as? String
                    if (control != null) {
                        val confirms = node["confirms"] as? Boolean ?: false
                        expected[control] = expected[control] == true || confirms
                    }
                    for (v in node.values) walk(v)
                }
                is List<*> -> node.forEach { walk(it) }
            }
        }

        walk(yaml["panel_layout"])
        walk(yaml["title_actions"])

        // inventory_controls y draft_controls: los dos mapas de controles por
        // fila, que no pueden declararse dentro de panel_layout porque su
        // sujeto es la fila y no la situación.
        for (key in listOf("inventory_controls", "draft_controls")) {
            @Suppress("UNCHECKED_CAST")
            val rowControls = yaml[key] as? Map<String, Any?> ?: continue
            for ((id, node) in rowControls) {
                val map = node as? Map<*, *>
                val confirms = map?.get("confirms") as? Boolean ?: false
                expected[id] = expected[id] == true || confirms
            }
        }

        // guide_rows, walkthrough_row y fixes_rows: mismo papel que los dos de
        // arriba (controles cuyo sujeto es la fila), pero los suyos cuelgan de
        // una clave "controls" porque el bloque tambien declara las filas y sus
        // estados.
        for (key in listOf("guide_rows", "walkthrough_row", "fixes_rows")) {
            @Suppress("UNCHECKED_CAST")
            val rowControls =
                (yaml[key] as? Map<String, Any?>)?.get("controls") as? Map<String, Any?> ?: continue
            for ((id, node) in rowControls) {
                val map = node as? Map<*, *>
                val confirms = map?.get("confirms") as? Boolean ?: false
                expected[id] = expected[id] == true || confirms
            }
        }

        for (id in ControlId.entries) {
            val want = expected[id.wire] ?: false
            assertEquals(want, requiresConfirmation(id), "confirms mismatch for ${id.wire}")
        }
    }

    /**
     * QUE LA TABLA GOBIERNE, no solo que coincida.
     *
     * El test de arriba compara dos declaraciones entre si, y eso es exactamente
     * lo que no alcanza: durante un tiempo el canonico dijo
     * `startFromDraft: {confirms: true}`, CONFIRMING_IDS tuvo START_FROM_DRAFT, y
     * el control hacia rato que no confirmaba -- las cinco suites en verde,
     * porque el `if (requiresConfirmation(id))` del despachador tenia el cuerpo
     * vacio y nadie mas leia la tabla.
     *
     * Estos dos asserts cierran el circulo por el fuente: todo id declarado tiene
     * un llamador que lo pasa por la puerta, y no hay ninguna otra puerta.
     */
    @Test
    fun `every confirming id is passed through the single gate`() {
        val sources = uiSources()
        // walkthroughInit es la EXCEPCION declarada: no confirma con un si/no
        // sino con un picker de dos cursos ("Update" / "Start over"), que
        // UiMessages.choose expresa y confirm no puede -- su "no" es un cancel.
        // Sigue siendo `confirms: true` en el canonico porque hay un modal entre
        // el clic y la mutacion, que es lo que esa clave significa.
        val byPicker = setOf(ControlId.WALKTHROUGH_INIT)
        // El id REALMENTE pasado, extraido del segundo argumento y no buscado
        // suelto en el archivo: un `contains` da verde con el call site cambiado,
        // porque el nombre del control aparece en el archivo por otros motivos.
        val gate = Regex(
            """UiMessages\.confirm\(\s*project,\s*ControlId\.([A-Z_]+)""",
            RegexOption.DOT_MATCHES_ALL,
        )
        val passed = sources.flatMap { (_, text) ->
            gate.findAll(text).map { it.groupValues[1] }.toList()
        }.toSet()
        for (id in ControlId.entries) {
            if (!requiresConfirmation(id) || id in byPicker) continue
            assertTrue(
                id.name in passed,
                "${id.wire} is confirms: true but is never passed to UiMessages.confirm",
            )
        }
        for (name in passed) {
            val id = ControlId.entries.first { it.name == name }
            assertTrue(
                requiresConfirmation(id),
                "UiMessages.confirm is called with ${id.wire}, which the canonical marks confirms: false",
            )
        }
    }

    @Test
    fun `no confirmation dialog exists outside the gate`() {
        for ((file, text) in uiSources()) {
            if (file.name == "UiMessages.kt") continue
            assertFalse(
                text.contains("showYesNoDialog"),
                "${file.name} opens a confirmation itself; it must go through UiMessages.confirm",
            )
        }
    }

    /** Los .kt de la capa ui, que es la unica que puede abrir un dialogo. */
    private fun uiSources(): List<Pair<File, String>> {
        val root = System.getProperty("git.review.monorepo.root")
            ?: File("..").canonicalPath
        val dir = File(root, "jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/ui")
        require(dir.isDirectory) { "ui sources missing at ${dir.absolutePath}" }
        val files = dir.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()
        require(files.isNotEmpty()) { "no ui sources found" }
        return files.map { it to it.readText() }
    }

    private fun loadCanonical(): Map<String, Any?> {
        val root = System.getProperty("git.review.monorepo.root")
            ?: File("..").canonicalPath
        val file = File(root, "contracts/client-product-surface.yaml")
        require(file.isFile) { "canonical missing at ${file.absolutePath}" }
        @Suppress("UNCHECKED_CAST")
        return Yaml().load(file.readText()) as Map<String, Any?>
    }
}
