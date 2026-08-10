package com.ezevillo.gitreview.domain

import com.ezevillo.gitreview.fixtures.PanelFixtures
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.yaml.snakeyaml.Yaml
import java.io.File

/**
 * Structural parity gate: layout of each fixture vs panel_layout in the canonical YAML.
 */
class PanelLayoutContractTest {
    @Test
    fun `canonical file is present`() {
        val file = canonicalFile()
        assertTrue(file.isFile, "canonical missing at ${file.absolutePath} — never skip this gate")
    }

    @Test
    fun `walk control sequence matches canonical ids and labels`() {
        assertLayoutAgainstCanonical(
            key = "review-walk",
            layout = panelLayout(PanelFixtures.reviewWalk()),
        )
    }

    @Test
    fun `a draft walk keeps the same control sequence as any walk`() {
        // 011: whose walkthrough it is shows up as identity (the "(draft)" badge
        // on the identity bar), never as a different set of actions — so the
        // canonical review-walk row is what it has to match, unchanged.
        assertLayoutAgainstCanonical(
            key = "review-walk",
            layout = panelLayout(PanelFixtures.reviewWalkDraft()),
        )
    }

    @Test
    fun `step control sequence matches canonical`() {
        assertLayoutAgainstCanonical(
            key = "review-step",
            layout = panelLayout(PanelFixtures.reviewStep()),
        )
    }

    @Test
    fun `setup control sequence matches canonical`() {
        assertLayoutAgainstCanonical(
            key = "no-review-setup",
            layout = panelLayout(PanelFixtures.noReviewSetup()),
        )
    }

    @Test
    fun `finish-pending controls match canonical`() {
        assertLayoutAgainstCanonical(
            key = "finish-pending",
            layout = panelLayout(PanelFixtures.finishPending()),
        )
    }

    @Test
    fun `cli-missing controls match canonical`() {
        assertLayoutAgainstCanonical(
            key = "cli-missing",
            layout = panelLayout(PanelFixtures.cliMissing()),
        )
    }

    @Test
    fun `whole openAllChanges present`() {
        val layout = panelLayout(PanelFixtures.reviewWhole())
        assertTrue(layout.collectControls().any { it.id == ControlId.OPEN_ALL_CHANGES && it.label == "Diff" })
    }

    private fun assertLayoutAgainstCanonical(key: String, layout: PanelLayout) {
        val yaml = loadCanonical()
        @Suppress("UNCHECKED_CAST")
        val panelLayout = yaml["panel_layout"] as Map<String, Any?>
        val sit = panelLayout[key] as? Map<*, *>
            ?: error("panel_layout missing situation $key")
        val expected = extractControlSpecs(sit["blocks"])
        val actual = layout.collectControls()
            .filter { it.id !in titleOnly }
            .map { Triple(it.id.wire, it.label, it.emphasis.id) }

        // Subsequence: actual body controls must include expected in order (when-filtered fixtures may omit some)
        var j = 0
        for (a in actual) {
            if (j < expected.size && a.first == expected[j].id) {
                if (expected[j].label != null) {
                    assertEquals(
                        expected[j].label,
                        a.second,
                        "situation $key control ${a.first} label",
                    )
                }
                if (expected[j].emphasis != null) {
                    assertEquals(
                        expected[j].emphasis,
                        a.third,
                        "situation $key control ${a.first} emphasis",
                    )
                }
                j++
            }
        }
        assertTrue(
            j == expected.size,
            "situation $key: only matched $j/${expected.size} expected controls " +
                "(expected=${expected.map { it.id }}, actual=${actual.map { it.first }})",
        )
    }

    private data class Spec(val id: String, val label: String?, val emphasis: String?)

    private fun extractControlSpecs(blocks: Any?): List<Spec> {
        val out = ArrayList<Spec>()
        fun walk(node: Any?) {
            when (node) {
                is Map<*, *> -> {
                    val id = node["id"] as? String
                    if (id != null) {
                        val label = when (val l = node["label"]) {
                            null -> null
                            is String -> l
                            else -> null
                        }
                        // SnakeYAML may parse `label: null` as null already
                        val labelIsNullKey = node.containsKey("label") && node["label"] == null
                        out.add(
                            Spec(
                                id = id,
                                label = if (labelIsNullKey) null else label,
                                emphasis = node["emphasis"] as? String,
                            ),
                        )
                    }
                    val control = node["control"] as? String
                    if (control != null) {
                        out.add(Spec(control, node["label"] as? String, "secondary"))
                    }
                    for (v in node.values) walk(v)
                }
                is List<*> -> node.forEach { walk(it) }
            }
        }
        walk(blocks)
        return out
    }

    private val titleOnly = setOf(
        ControlId.REFRESH,
        ControlId.FINISH_REVIEW,
        ControlId.SAVE_REVIEW,
        ControlId.ABORT_REVIEW,
        ControlId.PREVIEW_EDITS,
    )

    private fun loadCanonical(): Map<String, Any?> {
        @Suppress("UNCHECKED_CAST")
        return Yaml().load(canonicalFile().readText()) as Map<String, Any?>
    }

    private fun canonicalFile(): File {
        val root = System.getProperty("git.review.monorepo.root")
            ?: File("..").canonicalPath
        return File(root, "contracts/client-product-surface.yaml")
    }
}
