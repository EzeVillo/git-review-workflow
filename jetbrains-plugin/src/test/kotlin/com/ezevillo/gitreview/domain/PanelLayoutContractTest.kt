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

    @Test
    fun `the draft block is the first block of no-review and the body follows whole`() {
        val layout = panelLayout(PanelFixtures.noReviewDrafts())
        val blocks = layout.blocks
        // Primer bloque el encabezado, segundo las filas: no es una
        // sub-disposición que reemplace — el cuerpo de siempre sigue debajo.
        assertEquals("Reading orders you started", (blocks[0] as Block.Heading).text)
        assertTrue(blocks[1] is Block.DraftRows, "second block: ${blocks[1]}")
        assertTrue(
            blocks.any { it is Block.InventoryRows },
            "the inventory still follows the draft block",
        )
        assertTrue(
            layout.collectControls().any { it.id == ControlId.START_REVIEW },
            "Start a review still follows the draft block",
        )
    }

    @Test
    fun `draft rows carry the four canonical controls, with their labels and emphasis`() {
        val yaml = loadCanonical()
        @Suppress("UNCHECKED_CAST")
        val canonical = yaml["draft_controls"] as? Map<String, Any?>
            ?: error("canonical missing draft_controls")
        assertEquals(
            setOf("openDraft", "copyDraftPrompt", "startFromDraft", "discardDraft"),
            canonical.keys,
        )

        val rows = (panelLayout(PanelFixtures.noReviewDrafts()).blocks
            .first { it is Block.DraftRows } as Block.DraftRows).rows
        assertEquals(3, rows.size)

        // Las tres filas traen los cuatro, en el mismo orden: la botonera no
        // cambia de forma entre filas. En la segunda, startFromDraft va apagado
        // —su bloque de instrucciones se borró a mano, así que la CLI no sabe
        // con qué flags se generó y adivinarlos haría fallar el build por
        // deriva sobre un borrador válido—, y lo dice en el tooltip.
        val order = listOf("copyDraftPrompt", "startFromDraft", "openDraft", "discardDraft")
        for ((n, row) in rows.withIndex()) {
            assertEquals(order, row.controls.map { it.id.wire }, "order of row $n")
        }
        val unknownFlags = rows[1].controls.first { it.id == ControlId.START_FROM_DRAFT }
        assertTrue(!unknownFlags.enabled, "sin flags conocidos el control va apagado, no ausente")
        assertEquals(
            canonical["startFromDraft"].let { (it as Map<*, *>)["tooltip_disabled"] },
            unknownFlags.tooltip,
            "un control apagado dice por qué lo está",
        )

        for (control in rows[0].controls) {
            @Suppress("UNCHECKED_CAST")
            val spec = canonical[control.id.wire] as Map<String, Any?>
            assertEquals(spec["label"], control.label, "label of ${control.id.wire}")
            // rows[0] es 3/9: incompleto, así que rige emphasis_unfilled donde
            // el canónico lo declara y `emphasis` a secas donde no.
            val want = spec["emphasis_unfilled"] ?: spec["emphasis"]
            assertEquals(want, control.emphasis.id, "emphasis of ${control.id.wire}")
            assertEquals(
                spec["confirms"] as? Boolean ?: false,
                requiresConfirmation(control.id),
                "confirms of ${control.id.wire}",
            )
            // Cada control lleva el índice de SU fila: una acción sobre una fila
            // no puede tocar las demás.
            assertEquals(0, control.index, "index of ${control.id.wire}")
        }
        assertTrue(rows[1].controls.all { it.index == 1 }, "second row carries index 1")

        // Y la tercera está completa (1/1): ahí rige `emphasis` a secas.
        for (control in rows[2].controls) {
            @Suppress("UNCHECKED_CAST")
            val spec = canonical[control.id.wire] as Map<String, Any?>
            assertEquals(
                spec["emphasis"],
                control.emphasis.id,
                "emphasis of ${control.id.wire} (filled)",
            )
        }
    }

    @Test
    fun `the progress is what the CLI reported, never re-derived`() {
        val rows = (panelLayout(PanelFixtures.noReviewDrafts()).blocks
            .first { it is Block.DraftRows } as Block.DraftRows).rows
        assertEquals("feature/telemetry", rows[0].name)
        assertEquals("3/9", rows[0].meta)
        assertEquals("feature/pagos", rows[1].name)
        assertEquals("0/5", rows[1].meta)
        assertEquals("feature/legacy", rows[2].name)
        assertEquals("1/1", rows[2].meta)
    }

    @Test
    fun `the emphasis follows the progress and the order never moves`() {
        val rows = (panelLayout(PanelFixtures.noReviewDrafts()).blocks
            .first { it is Block.DraftRows } as Block.DraftRows).rows

        // 3/9: falta llenarlo, asi que el paso siguiente es Copy for agent.
        val incomplete = rows[0].controls.associateBy { it.id }
        assertEquals(Emphasis.PRIMARY, incomplete[ControlId.COPY_DRAFT_PROMPT]?.emphasis)
        assertEquals(Emphasis.SECONDARY, incomplete[ControlId.START_FROM_DRAFT]?.emphasis)

        // 1/1: el orden esta escrito, el paso siguiente es arrancar la review.
        val filled = rows[2].controls.associateBy { it.id }
        assertEquals(Emphasis.SECONDARY, filled[ControlId.COPY_DRAFT_PROMPT]?.emphasis)
        assertEquals(Emphasis.PRIMARY, filled[ControlId.START_FROM_DRAFT]?.emphasis)

        // Y el orden es el mismo en las dos: el objetivo del clic no se corre
        // bajo el cursor cuando el borrador avanza.
        assertEquals(
            rows[0].controls.map { it.id },
            rows[2].controls.map { it.id },
            "el objetivo del clic no se mueve con el progreso",
        )
    }

    @Test
    fun `validate and start is never disabled by progress, only by busy`() {
        // El conteo sale del disco y el borrador puede estar abierto con
        // cambios sin guardar, que el cliente guarda antes de validar:
        // grisarlo por el progreso mentiria al terminar de escribir.
        val rows = (panelLayout(PanelFixtures.noReviewDrafts()).blocks
            .first { it is Block.DraftRows } as Block.DraftRows).rows
        assertTrue(rows[0].controls.first { it.id == ControlId.START_FROM_DRAFT }.enabled)

        val busy = (panelLayout(PanelFixtures.noReviewDraftsBusy()).blocks
            .first { it is Block.DraftRows } as Block.DraftRows).rows
        assertTrue(!busy[0].controls.first { it.id == ControlId.START_FROM_DRAFT }.enabled)
    }

    @Test
    fun `open draft carries a label of its own and a name that says which one`() {
        // En una celda de ancho parejo la etiqueta ya no fuerza el wrap que
        // motivo el icono, y un glifo entre tres etiquetas no dice que abre.
        // Lo que se lee en voz alta sigue siendo la oracion: "Open" a secas se
        // repite una vez por fila y no nombra a ninguna.
        val rows = (panelLayout(PanelFixtures.noReviewDrafts()).blocks
            .first { it is Block.DraftRows } as Block.DraftRows).rows
        val open = rows[0].controls.first { it.id == ControlId.OPEN_DRAFT }
        assertEquals("Open", open.label)
        assertEquals(Emphasis.SECONDARY, open.emphasis)
        assertEquals("Open the reading order", open.accessibleName)
        assertEquals(0, open.index)
        assertTrue(
            rows[0].controls.none { it.emphasis == Emphasis.ICON },
            "ningun control de la fila es un icono",
        )
    }

    @Test
    fun `the irreversible control is last and the only one without a fill`() {
        // Sin relleno baja un escalon sin salirse de su celda: el hueco que
        // antes lo separaba no cabe en una grilla.
        val rows = (panelLayout(PanelFixtures.noReviewDrafts()).blocks
            .first { it is Block.DraftRows } as Block.DraftRows).rows
        assertEquals(
            listOf(ControlId.DISCARD_DRAFT),
            rows[0].controls.filter { it.emphasis == Emphasis.QUIET }.map { it.id },
        )
        assertEquals(ControlId.DISCARD_DRAFT, rows[0].controls.last().id)
    }

    @Test
    fun `no drafts means no block at all`() {
        val blocks = panelLayout(PanelFixtures.noReviewReady()).blocks
        assertTrue(blocks.none { it is Block.DraftRows }, "no DraftRows without drafts")
        assertTrue(
            blocks.none { it is Block.Heading && it.text == "Reading orders you started" },
            "no heading without drafts",
        )
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
        // Lo mismo para el bloque de borradores: sus cuatro controles son por
        // fila, asi que no se pueden declarar dentro de panel_layout —su sujeto
        // es la fila, no la situacion— y viven en un mapa propio, como los del
        // inventario.
        if (mentionsBlock(sit["blocks"], "draft_block")) {
            @Suppress("UNCHECKED_CAST")
            val draftControls = yaml["draft_controls"] as? Map<String, Any?>
            if (draftControls != null) allowed += draftControls.keys
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
