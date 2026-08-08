package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.Block
import com.ezevillo.gitreview.domain.Control
import com.ezevillo.gitreview.domain.ControlId
import com.ezevillo.gitreview.domain.Emphasis
import com.ezevillo.gitreview.domain.PanelLayout
import com.ezevillo.gitreview.domain.SkeletonShape
import com.ezevillo.gitreview.domain.WhyState
import java.awt.BorderLayout
import java.awt.Component
import java.awt.Dimension
import java.awt.FlowLayout
import java.awt.GridLayout
import java.awt.event.ComponentAdapter
import java.awt.event.ComponentEvent
import javax.swing.Box
import javax.swing.BoxLayout
import javax.swing.JButton
import javax.swing.JComponent
import javax.swing.JLabel
import javax.swing.JPanel
import javax.swing.JScrollPane
import javax.swing.JTextArea
import javax.swing.ScrollPaneConstants
import javax.swing.SwingUtilities
import javax.swing.border.EmptyBorder

/**
 * Generic Swing renderer of [PanelLayout]. No Project / GitReviewService.
 * @param onAction callback with control id and optional inventory/file index
 * @return true from onAction if the control should show transient "Copied" feedback
 */
class PanelRenderer(
    private val chrome: PanelChrome,
    private val onAction: (ControlId, Int?) -> Boolean = { _, _ -> false },
) {
    /** Section open state survives re-renders (FR-034). */
    private val sectionOpen = mutableMapOf<String, Boolean>()
    private var copyReset: javax.swing.Timer? = null

    fun render(layout: PanelLayout): JComponent {
        val root = JPanel(BorderLayout())
        root.background = chrome.background()

        val body = JPanel()
        body.layout = BoxLayout(body, BoxLayout.Y_AXIS)
        body.background = chrome.background()
        body.border = chrome.emptyBorder(8, 8, 8, 8)
        body.alignmentX = Component.LEFT_ALIGNMENT

        val footer = JPanel()
        footer.layout = BoxLayout(footer, BoxLayout.Y_AXIS)
        footer.background = chrome.background()
        footer.alignmentX = Component.LEFT_ALIGNMENT

        val bodyBlocks = ArrayList<Block>()
        val footerBlocks = ArrayList<Block>()
        for (b in layout.blocks) {
            if (b is Block.ToolsSection) footerBlocks.add(b) else bodyBlocks.add(b)
        }

        for (b in bodyBlocks) {
            body.add(renderBlock(b))
            body.add(Box.createVerticalStrut(4))
        }
        if (layout.fillsHeight) {
            body.add(Box.createVerticalGlue())
        }
        for (b in footerBlocks) {
            footer.add(renderBlock(b))
        }

        val scrollHost = if (layout.fillsHeight) {
            val wrap = JPanel(BorderLayout())
            wrap.background = chrome.background()
            val scroll = scrollPane(body)
            wrap.add(scroll, BorderLayout.CENTER)
            wrap.add(footer, BorderLayout.SOUTH)
            wrap
        } else {
            for (b in footerBlocks) {
                // already in footer; if not fills, append footer under body inside scroll
            }
            if (footerBlocks.isNotEmpty()) {
                body.add(footer)
            }
            scrollPane(body)
        }

        root.add(scrollHost, BorderLayout.CENTER)
        return root
    }

    private fun scrollPane(view: JComponent): JScrollPane {
        val scroll = JScrollPane(view)
        scroll.horizontalScrollBarPolicy = ScrollPaneConstants.HORIZONTAL_SCROLLBAR_NEVER
        scroll.verticalScrollBarPolicy = ScrollPaneConstants.VERTICAL_SCROLLBAR_AS_NEEDED
        scroll.border = null
        scroll.viewport.background = chrome.background()
        // Follow viewport width — never force horizontal scroll.
        scroll.addComponentListener(object : ComponentAdapter() {
            override fun componentResized(e: ComponentEvent?) {
                val w = scroll.viewport.width
                if (w > 0) {
                    view.preferredSize = Dimension(w, view.preferredSize.height)
                    view.maximumSize = Dimension(w, Int.MAX_VALUE)
                    view.revalidate()
                }
            }
        })
        return scroll
    }

    private fun renderBlock(block: Block): JComponent {
        val c: JComponent = when (block) {
            is Block.IdentityBar -> renderIdentityBar(block)
            is Block.Note -> wrapText(block.text, muted = true)
            is Block.Paragraph -> wrapText(block.text, muted = block.muted)
            is Block.Heading -> {
                val l = JLabel(block.text)
                l.font = chrome.boldFont(13f)
                l.alignmentX = Component.LEFT_ALIGNMENT
                l
            }
            is Block.Banner -> renderBanner(block)
            is Block.CodeCommand -> renderCodeCommand(block)
            is Block.EntryHead -> renderEntryHead(block)
            is Block.EntryTitle -> {
                if (block.skeleton) skeletonBar(60) else wrapText(block.text, muted = block.muted)
            }
            is Block.Why -> renderWhy(block)
            is Block.Row -> renderRow(block.controls)
            is Block.FileRows -> renderFileRows(block)
            is Block.InventoryRows -> renderInventory(block)
            is Block.ToolsSection -> renderToolsSection(block)
            is Block.Stderr -> {
                val area = JTextArea(block.text)
                area.isEditable = false
                area.lineWrap = true
                area.wrapStyleWord = true
                area.font = chrome.monoFont(11f)
                area.foreground = chrome.mutedForeground()
                area.background = chrome.background()
                area.alignmentX = Component.LEFT_ALIGNMENT
                area
            }
            is Block.EmptyMessage -> {
                val p = JPanel()
                p.layout = BoxLayout(p, BoxLayout.Y_AXIS)
                p.background = chrome.background()
                p.alignmentX = Component.LEFT_ALIGNMENT
                p.add(wrapText(block.text))
                block.control?.let {
                    p.add(Box.createVerticalStrut(6))
                    p.add(renderControl(it))
                }
                block.stderr?.let {
                    p.add(Box.createVerticalStrut(6))
                    p.add(wrapText(it, muted = true))
                }
                p
            }
            is Block.Skeleton -> skeletonBar(
                when (block.shape) {
                    SkeletonShape.POS -> 40
                    SkeletonShape.NUM -> 24
                    SkeletonShape.TITLE -> 80
                    SkeletonShape.WHY_LINE -> 100
                    SkeletonShape.BAR -> 120
                },
            )
        }
        c.alignmentX = Component.LEFT_ALIGNMENT
        return c
    }

    private fun renderIdentityBar(bar: Block.IdentityBar): JComponent {
        val row = JPanel(FlowLayout(FlowLayout.LEFT, 6, 0))
        row.background = chrome.background()
        row.alignmentX = Component.LEFT_ALIGNMENT
        row.add(badgeLabel(bar.mode, bold = true))
        row.add(JLabel(bar.name).apply { foreground = chrome.foreground() })
        bar.tip?.let { row.add(JLabel(it).apply { foreground = chrome.mutedForeground() }) }
        if (bar.skeleton) {
            row.add(skeletonBar(36))
        } else if (bar.position != null && bar.total != null) {
            row.add(JLabel("${bar.position}/${bar.total}").apply { foreground = chrome.mutedForeground() })
        }
        return row
    }

    private fun renderEntryHead(head: Block.EntryHead): JComponent {
        if (head.skeleton) return skeletonBar(48)
        val row = JPanel(FlowLayout(FlowLayout.LEFT, 6, 0))
        row.background = chrome.background()
        row.alignmentX = Component.LEFT_ALIGNMENT
        val n = if (head.position < 10) "0${head.position}" else head.position.toString()
        row.add(badgeLabel(n, bold = true))
        head.identifier?.let { row.add(JLabel(it).apply { foreground = chrome.mutedForeground() }) }
        head.author?.let { row.add(JLabel(it).apply { foreground = chrome.mutedForeground() }) }
        head.badge?.let { row.add(badgeLabel(it)) }
        return row
    }

    private fun renderWhy(why: Block.Why): JComponent {
        return when (why.state) {
            WhyState.LOADING -> {
                val p = JPanel()
                p.layout = BoxLayout(p, BoxLayout.Y_AXIS)
                p.background = chrome.background()
                p.add(skeletonBar(100))
                p.add(Box.createVerticalStrut(2))
                p.add(skeletonBar(80))
                p.add(Box.createVerticalStrut(2))
                p.add(skeletonBar(60))
                p
            }
            WhyState.PRESENT -> wrapText(why.text.orEmpty())
            WhyState.ABSENT, WhyState.FAILED -> wrapText(why.text.orEmpty(), muted = true)
        }
    }

    private fun renderBanner(banner: Block.Banner): JComponent {
        val box = JPanel()
        box.layout = BoxLayout(box, BoxLayout.Y_AXIS)
        box.background = chrome.background()
        box.border = chrome.emptyBorder(6, 6, 6, 6)
        box.alignmentX = Component.LEFT_ALIGNMENT
        for (p in banner.paragraphs) {
            box.add(wrapText(p))
            box.add(Box.createVerticalStrut(4))
        }
        box.add(renderRow(banner.row.controls))
        return box
    }

    private fun renderCodeCommand(cmd: Block.CodeCommand): JComponent {
        val row = JPanel(BorderLayout(6, 0))
        row.background = chrome.background()
        row.alignmentX = Component.LEFT_ALIGNMENT
        val code = JTextArea(cmd.command)
        code.isEditable = false
        code.lineWrap = true
        code.wrapStyleWord = true
        code.font = chrome.monoFont(11f)
        code.background = chrome.background()
        code.foreground = chrome.foreground()
        code.border = javax.swing.BorderFactory.createLineBorder(chrome.borderColor())
        row.add(code, BorderLayout.CENTER)
        row.add(renderControl(cmd.copy), BorderLayout.EAST)
        return row
    }

    private fun renderRow(controls: List<Control>): JComponent {
        val panel = object : JPanel() {
            override fun getMaximumSize(): Dimension {
                val pref = preferredSize
                return Dimension(Int.MAX_VALUE, pref.height)
            }
        }
        panel.alignmentX = Component.LEFT_ALIGNMENT
        panel.background = chrome.background()
        if (controls.size == 2) {
            panel.layout = GridLayout(1, 2, 6, 0)
            // Stack when too narrow: listen to resize
            panel.addComponentListener(object : ComponentAdapter() {
                override fun componentResized(e: ComponentEvent?) {
                    val w = panel.width
                    if (w > 0 && w < 160) {
                        if (panel.layout !is BoxLayout) {
                            panel.layout = BoxLayout(panel, BoxLayout.Y_AXIS)
                            panel.revalidate()
                        }
                    } else if (panel.layout !is GridLayout) {
                        panel.layout = GridLayout(1, 2, 6, 0)
                        panel.revalidate()
                    }
                }
            })
        } else {
            panel.layout = GridLayout(1, 1)
        }
        for (c in controls) {
            panel.add(renderControl(c))
        }
        return panel
    }

    private fun renderFileRows(files: Block.FileRows): JComponent {
        val box = JPanel()
        box.layout = BoxLayout(box, BoxLayout.Y_AXIS)
        box.background = chrome.background()
        box.alignmentX = Component.LEFT_ALIGNMENT
        for (f in files.rows) {
            val btn = JButton(f.display)
            btn.isEnabled = true
            btn.horizontalAlignment = JButton.LEFT
            btn.alignmentX = Component.LEFT_ALIGNMENT
            btn.maximumSize = Dimension(Int.MAX_VALUE, btn.preferredSize.height)
            if (f.lastOpened) {
                btn.toolTipText = "Last opened"
            }
            btn.addActionListener {
                onAction(ControlId.OPEN_CHANGE, f.index)
            }
            box.add(btn)
        }
        return box
    }

    private fun renderInventory(inv: Block.InventoryRows): JComponent {
        val box = JPanel()
        box.layout = BoxLayout(box, BoxLayout.Y_AXIS)
        box.background = chrome.background()
        box.alignmentX = Component.LEFT_ALIGNMENT
        for (r in inv.rows) {
            val head = JPanel(FlowLayout(FlowLayout.LEFT, 4, 0))
            head.background = chrome.background()
            head.add(JLabel(r.name).apply { font = chrome.boldFont(12f) })
            for (b in r.badges) head.add(badgeLabel(b))
            if (r.controls.isEmpty() && r.helpTooltip != null) {
                val help = JLabel("?")
                help.toolTipText = r.helpTooltip
                help.foreground = chrome.mutedForeground()
                head.add(help)
            }
            box.add(head)
            box.add(JLabel(r.meta).apply {
                foreground = chrome.mutedForeground()
                alignmentX = Component.LEFT_ALIGNMENT
                border = EmptyBorder(0, 4, 2, 0)
            })
            if (r.controls.isNotEmpty()) {
                val actions = JPanel(FlowLayout(FlowLayout.LEFT, 4, 0))
                actions.background = chrome.background()
                actions.alignmentX = Component.LEFT_ALIGNMENT
                for (c in r.controls) {
                    actions.add(renderControl(c))
                }
                box.add(actions)
            }
            box.add(Box.createVerticalStrut(6))
        }
        return box
    }

    private fun renderToolsSection(section: Block.ToolsSection): JComponent {
        val open = sectionOpen.getOrDefault(section.title, false)
        val box = JPanel()
        box.layout = BoxLayout(box, BoxLayout.Y_AXIS)
        box.background = chrome.background()
        box.alignmentX = Component.LEFT_ALIGNMENT

        val toggle = JButton((if (open) "▼ " else "▶ ") + section.title)
        toggle.isBorderPainted = false
        toggle.isContentAreaFilled = false
        toggle.horizontalAlignment = JButton.LEFT
        toggle.alignmentX = Component.LEFT_ALIGNMENT
        toggle.foreground = chrome.foreground()

        val content = JPanel()
        content.layout = BoxLayout(content, BoxLayout.Y_AXIS)
        content.background = chrome.background()
        content.alignmentX = Component.LEFT_ALIGNMENT
        content.isVisible = open
        content.border = chrome.emptyBorder(0, 8, 4, 0)
        for (b in section.blocks) {
            content.add(renderBlock(b))
            content.add(Box.createVerticalStrut(4))
        }

        toggle.addActionListener {
            val next = !content.isVisible
            content.isVisible = next
            sectionOpen[section.title] = next
            toggle.text = (if (next) "▼ " else "▶ ") + section.title
            box.revalidate()
            box.repaint()
        }
        box.add(toggle)
        box.add(content)
        return box
    }

    fun renderControl(c: Control): JComponent {
        val btn = when (c.emphasis) {
            Emphasis.ICON -> {
                val b = JButton()
                val icon = when (c.id) {
                    ControlId.PREV -> chrome.iconPrev()
                    ControlId.NEXT -> chrome.iconNext()
                    ControlId.COPY_CLI_INSTALL -> chrome.iconCopy()
                    else -> null
                }
                if (icon != null) {
                    b.icon = icon
                } else {
                    b.text = when (c.id) {
                        ControlId.PREV -> chrome.glyphPrev()
                        ControlId.NEXT -> chrome.glyphNext()
                        else -> c.accessibleName
                    }
                }
                b.toolTipText = c.accessibleName
                b.accessibleContext.accessibleName = c.accessibleName
                b
            }
            else -> {
                val b = JButton(c.label ?: c.accessibleName)
                if (c.emphasis == Emphasis.LINK) {
                    b.isBorderPainted = false
                    b.isContentAreaFilled = false
                    b.foreground = JBLinkColor
                }
                b
            }
        }
        btn.isEnabled = c.enabled
        c.tooltip?.let { btn.toolTipText = it }
        btn.addActionListener {
            if (!btn.isEnabled) return@addActionListener
            val copied = onAction(c.id, c.index)
            if (copied && c.id == ControlId.COPY_CLI_INSTALL) {
                val original = btn.text
                btn.text = "Copied"
                copyReset?.stop()
                copyReset = javax.swing.Timer(1500) {
                    btn.text = original ?: "Copy"
                }.also {
                    it.isRepeats = false
                    it.start()
                }
            }
        }
        return btn
    }

    private val JBLinkColor: java.awt.Color
        get() = chrome.primaryButtonBackground()

    private fun wrapText(text: String, muted: Boolean = false): JComponent {
        val area = JTextArea(text)
        area.isEditable = false
        area.lineWrap = true
        area.wrapStyleWord = true
        area.isOpaque = false
        area.border = null
        area.font = chrome.normalFont(12f)
        area.foreground = if (muted) chrome.mutedForeground() else chrome.foreground()
        area.alignmentX = Component.LEFT_ALIGNMENT
        area.maximumSize = Dimension(Int.MAX_VALUE, Int.MAX_VALUE)
        return area
    }

    private fun badgeLabel(text: String, bold: Boolean = false): JLabel {
        val l = JLabel(text)
        l.font = if (bold) chrome.boldFont(11f) else chrome.normalFont(11f)
        l.foreground = chrome.mutedForeground()
        return l
    }

    private fun skeletonBar(widthPct: Int): JComponent {
        val bar = JPanel()
        bar.background = chrome.borderColor()
        bar.preferredSize = Dimension(widthPct * 2, 12)
        bar.maximumSize = Dimension(Int.MAX_VALUE, 12)
        bar.alignmentX = Component.LEFT_ALIGNMENT
        bar.border = chrome.emptyBorder(2, 0, 2, 0)
        return bar
    }

    /** Test helper: walk rendered tree collecting enabled control ids in order. */
    companion object {
        fun collectButtons(root: JComponent): List<JButton> {
            val out = ArrayList<JButton>()
            fun walk(c: Component) {
                if (c is JButton) out.add(c)
                if (c is java.awt.Container) {
                    for (ch in c.components) walk(ch)
                }
            }
            walk(root)
            return out
        }
    }
}
