package com.ezevillo.gitreview.domain

import org.junit.jupiter.api.Assertions.assertEquals
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

        // guide_rows: mismo papel que los dos de arriba (controles cuyo sujeto es
        // la fila), pero los suyos cuelgan de una clave "controls" porque el
        // bloque tambien declara las filas y sus estados.
        @Suppress("UNCHECKED_CAST")
        val guideControls =
            (yaml["guide_rows"] as? Map<String, Any?>)?.get("controls") as? Map<String, Any?>
        if (guideControls != null) {
            for ((id, node) in guideControls) {
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

    private fun loadCanonical(): Map<String, Any?> {
        val root = System.getProperty("git.review.monorepo.root")
            ?: File("..").canonicalPath
        val file = File(root, "contracts/client-product-surface.yaml")
        require(file.isFile) { "canonical missing at ${file.absolutePath}" }
        @Suppress("UNCHECKED_CAST")
        return Yaml().load(file.readText()) as Map<String, Any?>
    }
}
