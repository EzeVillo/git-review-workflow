package com.ezevillo.gitreview.preview

import com.ezevillo.gitreview.domain.panelLayout
import com.ezevillo.gitreview.fixtures.PanelFixtures
import com.ezevillo.gitreview.ui.PanelRenderer
import com.ezevillo.gitreview.ui.PreviewPanelChrome
import java.awt.BorderLayout
import java.awt.Dimension
import java.awt.FlowLayout
import javax.swing.JComboBox
import javax.swing.JFrame
import javax.swing.JLabel
import javax.swing.JPanel
import javax.swing.SwingUtilities
import javax.swing.UIManager
import javax.swing.WindowConstants

/**
 * Standalone Swing preview of real [PanelRenderer] output (feature 010).
 * Compare side-by-side with `npm run preview` in vscode-extension.
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

            val models = PanelFixtures.all()
            val names = models.map { it.first }.toTypedArray()
            val combo = JComboBox(names)
            val widthCombo = JComboBox(arrayOf("Sidebar (280)", "Loose (420)"))
            val host = JPanel(BorderLayout())
            val chrome = PreviewPanelChrome()
            val renderer = PanelRenderer(chrome) { _, _, _ -> false }

            fun show() {
                val model = models[combo.selectedIndex].second
                val width = if (widthCombo.selectedIndex == 0) 280 else 420
                host.removeAll()
                val panel = renderer.render(panelLayout(model))
                host.add(panel, BorderLayout.CENTER)
                host.preferredSize = Dimension(width, 640)
                host.revalidate()
                host.repaint()
                frame.pack()
            }
            combo.addActionListener { show() }
            widthCombo.addActionListener { show() }

            val top = JPanel(FlowLayout(FlowLayout.LEFT))
            top.add(JLabel("Situation:"))
            top.add(combo)
            top.add(JLabel("Width:"))
            top.add(widthCombo)

            frame.layout = BorderLayout()
            frame.add(top, BorderLayout.NORTH)
            frame.add(host, BorderLayout.CENTER)
            show()
            frame.setLocationRelativeTo(null)
            frame.isVisible = true
        }
    }
}
