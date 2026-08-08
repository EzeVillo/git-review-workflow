package com.ezevillo.gitreview.preview

import com.ezevillo.gitreview.domain.EffectiveConfig
import com.ezevillo.gitreview.domain.EntryRecord
import com.ezevillo.gitreview.domain.PanelInputs
import com.ezevillo.gitreview.domain.PanelModel
import com.ezevillo.gitreview.domain.ReviewMode
import com.ezevillo.gitreview.domain.ReviewState
import com.ezevillo.gitreview.domain.Situation
import com.ezevillo.gitreview.domain.StateRecord
import com.ezevillo.gitreview.domain.WalkthroughStatus
import com.ezevillo.gitreview.domain.buildPanelModel
import com.ezevillo.gitreview.domain.parsePorcelain
import com.ezevillo.gitreview.domain.toPathRef
import java.awt.BorderLayout
import java.awt.Dimension
import java.awt.FlowLayout
import javax.swing.JComboBox
import javax.swing.JFrame
import javax.swing.JLabel
import javax.swing.JPanel
import javax.swing.JScrollPane
import javax.swing.JTextArea
import javax.swing.SwingUtilities
import javax.swing.UIManager
import javax.swing.WindowConstants

/**
 * Standalone Swing preview of [PanelModel] situations (T029).
 * No IntelliJ Platform — pure domain + Swing.
 */
object PanelPreviewMain {
    @JvmStatic
    fun main(args: Array<String>) {
        SwingUtilities.invokeLater {
            try {
                UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName())
            } catch (_: Exception) {
                // keep default
            }
            val frame = JFrame("git review — panel preview")
            frame.defaultCloseOperation = WindowConstants.EXIT_ON_CLOSE
            frame.preferredSize = Dimension(360, 640)

            val area = JTextArea()
            area.isEditable = false
            area.lineWrap = true
            area.wrapStyleWord = true

            val models = fixtureModels()
            val names = models.map { it.first }.toTypedArray()
            val combo = JComboBox(names)
            fun show(index: Int) {
                val model = models[index].second
                area.text = renderText(model)
            }
            combo.addActionListener { show(combo.selectedIndex) }
            show(0)

            val top = JPanel(FlowLayout(FlowLayout.LEFT))
            top.add(JLabel("Situation:"))
            top.add(combo)

            frame.layout = BorderLayout()
            frame.add(top, BorderLayout.NORTH)
            frame.add(JScrollPane(area), BorderLayout.CENTER)
            frame.pack()
            frame.setLocationRelativeTo(null)
            frame.isVisible = true
        }
    }

    private fun fixtureModels(): List<Pair<String, PanelModel>> {
        val walkPorcelain = """
            state	review/feature	feature	deadbeef	walk	applied	1	3	3	"src/a.kt"	1
            entry	1	src/a.kt	1	1
            entry	2	src/b.kt	0	1
            entry	3	src/c.kt	0	0
        """.trimIndent()
        val walkParsed = parsePorcelain(walkPorcelain)
        val walkState = ReviewState(
            situation = Situation.REVIEW,
            state = walkParsed.state,
            entries = walkParsed.entries,
        )

        return listOf(
            "cli-missing" to buildPanelModel(
                ReviewState(situation = Situation.CLI_MISSING, stderr = "not found"),
                PanelInputs(busy = false),
            ),
            "cli-outdated" to buildPanelModel(
                ReviewState(situation = Situation.CLI_OUTDATED, stderr = "0.3.0"),
                PanelInputs(busy = false),
            ),
            "no-review setup" to buildPanelModel(
                ReviewState(
                    situation = Situation.NO_REVIEW,
                    config = EffectiveConfig(base = null, remote = "origin"),
                ),
                PanelInputs(busy = false),
            ),
            "no-review ready" to buildPanelModel(
                ReviewState(
                    situation = Situation.NO_REVIEW,
                    config = EffectiveConfig(base = "main", remote = "origin"),
                ),
                PanelInputs(busy = false),
            ),
            "walk review" to buildPanelModel(walkState, PanelInputs(busy = false)),
            "step review" to buildPanelModel(
                ReviewState(
                    situation = Situation.REVIEW,
                    state = StateRecord(
                        "review/f", "f", "tip", ReviewMode.STEP, WalkthroughStatus.NONE,
                        position = 2, total = 4, recorded = 4, current = "abc1234",
                    ),
                    entries = listOf(
                        EntryRecord(1, "aaa1111", banked = false),
                        EntryRecord(2, "abc1234", banked = true),
                        EntryRecord(3, "ccc3333", banked = false),
                        EntryRecord(4, "ddd4444", banked = false),
                    ),
                    subjects = mapOf(2 to "Fix the thing"),
                ),
                PanelInputs(busy = false),
            ),
            "whole review" to buildPanelModel(
                ReviewState(
                    situation = Situation.REVIEW,
                    state = StateRecord(
                        "review/f", "f", "tip", ReviewMode.WHOLE, WalkthroughStatus.NONE,
                    ),
                    entries = listOf(
                        EntryRecord(1, toPathRef("a.kt")),
                        EntryRecord(2, toPathRef("b.kt")),
                    ),
                    base = "main",
                ),
                PanelInputs(busy = false, lastOpened = "a.kt"),
            ),
            "finish-conflict" to buildPanelModel(
                ReviewState(
                    situation = Situation.FINISH_CONFLICT,
                    state = StateRecord(
                        "review/f", "f", "tip", ReviewMode.WALK, WalkthroughStatus.APPLIED,
                        position = 1, total = 2, recorded = 2, current = toPathRef("a.kt"),
                    ),
                    entries = listOf(EntryRecord(1, toPathRef("a.kt"), essential = true, annotated = true)),
                ),
                PanelInputs(busy = false),
            ),
            "error multi-root" to buildPanelModel(
                ReviewState(
                    situation = Situation.ERROR,
                    stderr = "Open a single-folder workspace that is a git repository. git review uses one root (like the CLI cwd); multi-root is not supported.",
                ),
                PanelInputs(busy = false),
            ),
        )
    }

    private fun renderText(m: PanelModel): String = buildString {
        appendLine("situation: ${m.situation.id}")
        appendLine("busy: ${m.busy}")
        if (m.noBaseConfigured) appendLine("noBaseConfigured: true")
        m.configuredBase?.let { appendLine("configuredBase: $it") }
        m.configuredRemote?.let { appendLine("configuredRemote: $it") }
        m.mode?.let { appendLine("mode: ${it.id}") }
        m.branch?.let { appendLine("branch: $it") }
        m.source?.let { appendLine("source: $it") }
        m.tip?.let { appendLine("tip: $it") }
        m.position?.let { appendLine("position: $it / ${m.total}") }
        m.current?.let { appendLine("current: ${it.display}") }
        if (m.files.isNotEmpty()) {
            appendLine("files:")
            m.files.forEach { appendLine("  - ${it.display}") }
        }
        if (m.reviews.isNotEmpty()) {
            appendLine("reviews:")
            m.reviews.forEach { appendLine("  - ${it.name} resumable=${it.resumable}") }
        }
        m.why?.let { appendLine("why: ${it.state.id}") }
        m.stderr?.let { appendLine("stderr: $it") }
        appendLine("navLocked=${m.navigationLocked} atFirst=${m.atFirst} atLast=${m.atLast}")
    }
}
