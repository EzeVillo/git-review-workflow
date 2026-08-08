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
    fun `requiresConfirmation matches canonical confirms for all 26 ControlIds`() {
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

        @Suppress("UNCHECKED_CAST")
        val inventory = yaml["inventory_controls"] as? Map<String, Any?>
        if (inventory != null) {
            for ((id, node) in inventory) {
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
