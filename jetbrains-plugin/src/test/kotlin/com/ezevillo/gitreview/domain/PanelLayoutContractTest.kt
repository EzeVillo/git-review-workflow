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
            mode = "walk",
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
            mode = "walk",
        )
    }

    @Test
    fun `step control sequence matches canonical`() {
        assertLayoutAgainstCanonical(
            key = "review-step",
            layout = panelLayout(PanelFixtures.reviewStep()),
            mode = "step",
        )
    }

    @Test
    fun `whole control sequence matches canonical`() {
        assertLayoutAgainstCanonical(
            key = "review-whole",
            layout = panelLayout(PanelFixtures.reviewWhole()),
            mode = "whole",
        )
    }

    @Test
    fun `finish-conflict control sequence matches canonical`() {
        assertLayoutAgainstCanonical(
            key = "finish-conflict",
            layout = panelLayout(PanelFixtures.finishConflict()),
            mode = "walk",
        )
    }

    @Test
    fun `setup control sequence matches canonical`() {
        assertLayoutAgainstCanonical(
            key = "no-review-setup",
            layout = panelLayout(PanelFixtures.noReviewSetup()),
        )
    }

    // La situacion mas grande del contrato (ocho controles) y la que ofrece las
    // destructivas: quedaba sin comparar mientras las cinco chicas si estaban.
    @Test
    fun `no-review ready control sequence matches canonical`() {
        assertLayoutAgainstCanonical(
            key = "no-review",
            layout = panelLayout(PanelFixtures.noReviewReady()),
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
    fun `cli-outdated controls match canonical`() {
        assertLayoutAgainstCanonical(
            key = "cli-outdated",
            layout = panelLayout(PanelFixtures.cliOutdated()),
        )
    }

    @Test
    fun `out-of-range controls match canonical`() {
        assertLayoutAgainstCanonical(
            key = "out-of-range",
            layout = panelLayout(PanelFixtures.outOfRange()),
        )
    }

    @Test
    fun `error controls match canonical`() {
        assertLayoutAgainstCanonical(
            key = "error",
            layout = panelLayout(PanelFixtures.error()),
        )
    }

    @Test
    fun `whole openAllChanges present`() {
        val layout = panelLayout(PanelFixtures.reviewWhole())
        assertTrue(layout.collectControls().any { it.id == ControlId.OPEN_ALL_CHANGES && it.label == "Diff" })
    }

    /**
     * @param mode el modo de la fixture, cuando la situacion declara bloques con
     *   `when: walk` / `step` / `whole`. Esas ramas son excluyentes, asi que
     *   aplanarlas todas en una sola secuencia esperada le pide a un panel walk
     *   tambien la fila de step.
     */
    private fun assertLayoutAgainstCanonical(key: String, layout: PanelLayout, mode: String? = null) {
        val yaml = loadCanonical()
        @Suppress("UNCHECKED_CAST")
        val panelLayout = yaml["panel_layout"] as Map<String, Any?>
        val sit = panelLayout[key] as? Map<*, *>
            ?: error("panel_layout missing situation $key")
        val expected = extractControlSpecs(sit["blocks"], mode)
        val actual = layout.collectControls()
            .filter { it.id !in titleOnly }
            .map { Triple(it.id.wire, it.label, it.emphasis.id) }

        // 1. Nada que el canonico no declare para esta situacion. Sin esto el matcher
        //    de abajo solo prueba que los controles esperados estan, y en orden: un
        //    boton de mas en cualquier parte del panel le pasaba por al lado. Los
        //    bloques con `when:` pueden faltar, nunca sobrar, asi que la contencion
        //    corre en una sola direccion.
        val declared = extractControlSpecs(sit["blocks"]).map { it.id }.toSet()
        val allowed = declared.toMutableSet()
        if (mentionsBlock(sit["blocks"], "inventory_rows")) {
            @Suppress("UNCHECKED_CAST")
            val inventory = yaml["inventory_controls"] as? Map<String, Any?>
            if (inventory != null) allowed += inventory.keys
        }
        val stray = actual.map { it.first }.filter { it !in allowed }.distinct()
        assertTrue(
            stray.isEmpty(),
            "situation $key: controles que el canonico no declara: $stray (permitidos: ${allowed.sorted()})",
        )

        // 2. Y nada que el canonico marque not_in para este cliente.
        val forbidden = declared - extractControlSpecs(sit["blocks"], skipNotIn = true).map { it.id }.toSet()
        val offered = actual.map { it.first }.filter { it in forbidden }.distinct()
        assertTrue(
            offered.isEmpty(),
            "situation $key: ofrece $offered, que el contrato marca not_in: [$THIS_CLIENT]",
        )

        // 3. Los declarados, en orden, con su label y su emphasis.
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

    private fun mentionsBlock(node: Any?, blockType: String): Boolean = when (node) {
        is Map<*, *> -> node["block"] == blockType || node.values.any { mentionsBlock(it, blockType) }
        is List<*> -> node.any { mentionsBlock(it, blockType) }
        else -> false
    }

    /** Un bloque atado a un modo distinto del de la fixture no se dibuja. */
    private fun gatedOut(node: Map<*, *>, mode: String?): Boolean {
        if (mode == null) return false
        val whenTag = node["when"] as? String ?: return false
        return whenTag in MODE_GATES && whenTag != mode
    }

    private fun notInThisClient(node: Map<*, *>): Boolean =
        (node["not_in"] as? List<*>)?.any { it == THIS_CLIENT } == true

    private fun extractControlSpecs(
        blocks: Any?,
        mode: String? = null,
        skipNotIn: Boolean = false,
    ): List<Spec> {
        val out = ArrayList<Spec>()
        fun walk(node: Any?) {
            when (node) {
                is Map<*, *> -> {
                    if (gatedOut(node, mode)) return
                    if (skipNotIn && notInThisClient(node)) return
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

    private companion object {
        /** El nombre de este cliente en las listas `not_in:` del contrato. */
        const val THIS_CLIENT = "jetbrains"
        val MODE_GATES = setOf("walk", "step", "whole")
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
