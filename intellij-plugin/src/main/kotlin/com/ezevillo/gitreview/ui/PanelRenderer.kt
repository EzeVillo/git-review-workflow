package com.ezevillo.gitreview.ui

import com.ezevillo.gitreview.domain.Block
import com.ezevillo.gitreview.domain.Control
import com.ezevillo.gitreview.domain.ControlId
import com.ezevillo.gitreview.domain.Emphasis
import com.ezevillo.gitreview.domain.FileRow
import com.ezevillo.gitreview.domain.PanelLayout
import com.ezevillo.gitreview.domain.SkeletonShape
import com.ezevillo.gitreview.domain.WhyState
import java.awt.BorderLayout
import java.awt.Component
import java.awt.Dimension
import java.awt.FlowLayout
import java.awt.Graphics
import java.awt.GridLayout
import java.awt.Insets
import java.awt.Rectangle
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
import javax.swing.Scrollable
import javax.swing.ScrollPaneConstants
import javax.swing.SwingConstants
import javax.swing.border.EmptyBorder

/** The bar at the margin of the last opened row (the extension's `border-left`). */
private const val ROW_MARKER_WIDTH = 2

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

        val body = ScrollBody()
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

    /**
     * The panel is a column in a sidebar: it follows the viewport width and only
     * ever scrolls vertically. Saying so through [Scrollable] is what lets the
     * wrapped text be measured at the width it will actually get — pinning
     * `preferredSize` by hand froze it at whatever the first pass computed, and
     * every paragraph after that was clipped to the line count of that guess.
     */
    private class ScrollBody : JPanel(), Scrollable {
        override fun getPreferredScrollableViewportSize(): Dimension = preferredSize
        override fun getScrollableTracksViewportWidth(): Boolean = true
        override fun getScrollableTracksViewportHeight(): Boolean = false
        override fun getScrollableUnitIncrement(r: Rectangle, orientation: Int, direction: Int) = 16
        override fun getScrollableBlockIncrement(r: Rectangle, orientation: Int, direction: Int) =
            r.height
    }

    private fun scrollPane(view: JComponent): JScrollPane {
        val scroll = JScrollPane(view)
        scroll.horizontalScrollBarPolicy = ScrollPaneConstants.HORIZONTAL_SCROLLBAR_NEVER
        scroll.verticalScrollBarPolicy = ScrollPaneConstants.VERTICAL_SCROLLBAR_AS_NEEDED
        scroll.border = null
        scroll.viewport.background = chrome.background()
        return scroll
    }

    private fun renderBlock(block: Block): JComponent {
        val c: JComponent = when (block) {
            is Block.IdentityBar -> renderIdentityBar(block)
            is Block.Note -> wrapText(block.text, muted = true)
            is Block.Paragraph -> renderParagraph(block)
            is Block.Heading -> {
                // The extension's `h2`: it labels the list under it, so it reads
                // quieter than the content — not louder, the way a bold
                // foreground-coloured line did.
                val l = JLabel(block.text)
                l.font = chrome.boldFont(11f)
                l.foreground = chrome.mutedForeground()
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
                val area = WrappedText(block.text)
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
                p.add(stacked(wrapText(block.text)))
                block.control?.let {
                    p.add(Box.createVerticalStrut(6))
                    p.add(stacked(renderControl(it)))
                }
                block.stderr?.let {
                    p.add(Box.createVerticalStrut(6))
                    p.add(stacked(wrapText(it, muted = true)))
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
        return stacked(c)
    }

    /**
     * A block in a vertical stack keeps the height it asked for. BoxLayout hands
     * the leftover height to whoever declares an unbounded maximum — and a
     * wrapped JTextArea, a BorderLayout row and a glue all do — which is what
     * pushed the primary button of a pane to the far bottom and blew air between
     * every paragraph. Capping at the preferred height reproduces the document
     * flow the extension gets for free.
     */
    private fun stacked(child: JComponent): JComponent {
        val box = object : JPanel(BorderLayout()) {
            override fun getMaximumSize(): Dimension =
                Dimension(Int.MAX_VALUE, preferredSize.height)
        }
        box.isOpaque = false
        box.alignmentX = Component.LEFT_ALIGNMENT
        box.add(child, BorderLayout.CENTER)
        return box
    }

    private fun renderParagraph(p: Block.Paragraph): JComponent {
        val text = wrapText(p.text, muted = p.muted)
        if (!p.separated) return text
        val box = JPanel(BorderLayout())
        box.background = chrome.background()
        box.alignmentX = Component.LEFT_ALIGNMENT
        box.border = javax.swing.BorderFactory.createCompoundBorder(
            javax.swing.BorderFactory.createMatteBorder(1, 0, 0, 0, chrome.borderColor()),
            chrome.emptyBorder(8, 0, 0, 0),
        )
        box.add(text, BorderLayout.CENTER)
        return box
    }

    /**
     * A header line: what names the thing on the left, what qualifies it on the
     * right. The trailing group is the extension's `margin-left: auto` (the
     * position counter, the entry badge, the inventory badges) — it belongs at
     * the far edge, not glued to the name.
     */
    private fun headerRow(left: List<JComponent>, right: List<JComponent>): JComponent {
        val row = JPanel()
        row.layout = BoxLayout(row, BoxLayout.X_AXIS)
        row.background = chrome.background()
        row.alignmentX = Component.LEFT_ALIGNMENT
        left.forEachIndexed { i, c ->
            if (i > 0) row.add(Box.createHorizontalStrut(6))
            c.alignmentY = Component.CENTER_ALIGNMENT
            row.add(c)
        }
        row.add(Box.createHorizontalGlue())
        right.forEachIndexed { i, c ->
            if (i > 0) row.add(Box.createHorizontalStrut(6))
            c.alignmentY = Component.CENTER_ALIGNMENT
            row.add(c)
        }
        return row
    }

    private fun renderIdentityBar(bar: Block.IdentityBar): JComponent {
        val left = ArrayList<JComponent>()
        left.add(badgeLabel(bar.mode, bold = true))
        if (bar.draft) {
            left.add(JLabel("(draft)").apply { foreground = chrome.mutedForeground() })
        }
        left.add(JLabel(bar.name).apply { foreground = chrome.foreground() })
        bar.tip?.let { left.add(JLabel(it).apply { foreground = chrome.mutedForeground() }) }
        val right = ArrayList<JComponent>()
        if (bar.skeleton) {
            right.add(skeletonBar(36))
        } else if (bar.position != null && bar.total != null) {
            right.add(
                JLabel("${bar.position}/${bar.total}").apply { foreground = chrome.mutedForeground() },
            )
        }
        // The bar is the panel's fixed chrome, ruled off from the entry below it
        // like the extension's `.bar { border-bottom }`.
        val row = headerRow(left, right)
        row.border = javax.swing.BorderFactory.createCompoundBorder(
            javax.swing.BorderFactory.createMatteBorder(0, 0, 1, 0, chrome.borderColor()),
            chrome.emptyBorder(0, 0, 6, 0),
        )
        return row
    }

    private fun renderEntryHead(head: Block.EntryHead): JComponent {
        if (head.skeleton) return skeletonBar(48)
        val left = ArrayList<JComponent>()
        val n = if (head.position < 10) "0${head.position}" else head.position.toString()
        left.add(badgeLabel(n, bold = true))
        head.identifier?.let { left.add(JLabel(it).apply { foreground = chrome.mutedForeground() }) }
        head.author?.let { left.add(JLabel(it).apply { foreground = chrome.mutedForeground() }) }
        val right = head.badge?.let { listOf<JComponent>(badgeLabel(it)) } ?: emptyList()
        return headerRow(left, right)
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
            box.add(stacked(wrapText(p)))
            box.add(Box.createVerticalStrut(4))
        }
        box.add(stacked(renderRow(banner.row.controls)))
        return box
    }

    private fun renderCodeCommand(cmd: Block.CodeCommand): JComponent {
        val row = JPanel(BorderLayout(6, 0))
        row.background = chrome.background()
        row.alignmentX = Component.LEFT_ALIGNMENT
        val code = WrappedText(cmd.command)
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
            box.add(fileRow(f))
        }
        return box
    }

    /**
     * A path in the list is a row, not a button: the extension paints it with
     * `background: none` and hands it a fill only under the pointer, so what the
     * eye picks up from the column is the list of paths — a stack of framed
     * buttons reads as a stack of actions and buries them. The last opened one
     * carries the inactive-selection fill *and* a bar at the margin, because in
     * a high-contrast theme the fill alone can be indistinguishable (FR-031).
     */
    private fun fileRow(f: FileRow): JButton {
        val hover = chrome.rowHoverBackground()
        val selected = chrome.rowSelectedBackground()
        val marker = chrome.linkForeground()
        val focus = chrome.linkForeground()
        val btn = object : JButton(f.display) {
            override fun getMaximumSize(): Dimension =
                Dimension(Int.MAX_VALUE, preferredSize.height)

            override fun paintComponent(g: Graphics) {
                val fill = when {
                    model.isRollover || model.isPressed -> hover
                    f.lastOpened -> selected
                    else -> null
                }
                if (fill != null) {
                    g.color = fill
                    g.fillRect(0, 0, width, height)
                }
                if (f.lastOpened) {
                    g.color = marker
                    g.fillRect(0, 0, ROW_MARKER_WIDTH, height)
                }
                // The LaF paints no focus ring on a borderless button, and
                // keyboard is the only way through this list without a mouse.
                if (isFocusOwner) {
                    g.color = focus
                    g.drawRect(0, 0, width - 1, height - 1)
                }
                super.paintComponent(g)
            }
        }
        btn.horizontalAlignment = SwingConstants.LEFT
        btn.alignmentX = Component.LEFT_ALIGNMENT
        btn.isContentAreaFilled = false
        btn.isBorderPainted = false
        btn.isFocusPainted = false
        btn.isOpaque = false
        btn.isRolloverEnabled = true
        btn.margin = Insets(0, 0, 0, 0)
        btn.border = chrome.emptyBorder(3, ROW_MARKER_WIDTH + 5, 3, 5)
        btn.font = chrome.monoFont(12f)
        btn.foreground = chrome.foreground()
        chrome.iconDiff()?.let {
            btn.icon = it
            btn.iconTextGap = 6
        }
        // A sidebar clips a long path; the whole of it stays one hover away.
        btn.toolTipText = if (f.lastOpened) "Last opened: ${f.display}" else f.display
        btn.addActionListener {
            onAction(ControlId.OPEN_CHANGE, f.index)
        }
        return btn
    }

    private fun renderInventory(inv: Block.InventoryRows): JComponent {
        val box = JPanel()
        box.layout = BoxLayout(box, BoxLayout.Y_AXIS)
        box.background = chrome.background()
        box.alignmentX = Component.LEFT_ALIGNMENT
        for (r in inv.rows) {
            val badges = ArrayList<JComponent>()
            for (b in r.badges) badges.add(badgeLabel(b))
            if (r.controls.isEmpty() && r.helpTooltip != null) {
                val help = JLabel("?")
                help.toolTipText = r.helpTooltip
                help.foreground = chrome.mutedForeground()
                badges.add(help)
            }
            box.add(
                stacked(
                    headerRow(
                        listOf(JLabel(r.name).apply { font = chrome.boldFont(12f) }),
                        badges,
                    ),
                ),
            )
            box.add(
                stacked(
                    JLabel(r.meta).apply {
                        foreground = chrome.mutedForeground()
                        border = EmptyBorder(0, 0, 2, 0)
                    },
                ),
            )
            if (r.controls.isNotEmpty()) {
                // Left, at label width — never one button per sidebar row.
                val actions = JPanel(FlowLayout(FlowLayout.LEFT, 4, 0))
                actions.background = chrome.background()
                actions.alignmentX = Component.LEFT_ALIGNMENT
                for (c in r.controls) {
                    actions.add(renderControl(c))
                }
                box.add(stacked(actions))
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
                // The verbs that open something carry the same glyph as their
                // rows do in the extension: two "Diff" buttons on one pane are
                // told apart by what sits next to them, not by their label.
                if (c.emphasis != Emphasis.LINK) {
                    when (c.id) {
                        ControlId.OPEN_CHANGE, ControlId.OPEN_ALL_CHANGES -> chrome.iconDiff()
                        ControlId.OPEN_ENTRY -> chrome.iconFile()
                        else -> null
                    }?.let {
                        b.icon = it
                        b.iconTextGap = 6
                    }
                }
                when (c.emphasis) {
                    Emphasis.LINK -> {
                        b.isBorderPainted = false
                        b.isContentAreaFilled = false
                        b.isOpaque = false
                        b.foreground = chrome.linkForeground()
                    }
                    Emphasis.PRIMARY -> chrome.markPrimary(b)
                    else -> Unit
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

    /**
     * Wrapped text whose preferred height is the height *at the width it will
     * get*. Swing measures a text area against its own current size, which on
     * the first pass is zero, so it reports one line and the block ends up
     * clipped; asking the parent for the width first is what makes it wrap.
     * Capping the maximum at that height keeps it from eating the leftover
     * space of the column.
     */
    private class WrappedText(text: String) : JTextArea(text) {
        override fun getPreferredSize(): Dimension {
            // Own width once laid out (a BorderLayout centre is narrower than
            // its parent — the copy button sits next to it); the parent's only
            // as the first-pass hint, when nothing has a width yet.
            if (width <= 0) {
                val p = parent
                if (p != null && p.width > 0) {
                    val insets = p.insets
                    val w = p.width - insets.left - insets.right
                    if (w > 0) setSize(w, height.coerceAtLeast(1))
                }
            }
            return super.getPreferredSize()
        }

        override fun getMaximumSize(): Dimension = Dimension(Int.MAX_VALUE, preferredSize.height)
    }

    private fun wrapText(text: String, muted: Boolean = false): JComponent {
        val area = WrappedText(text)
        area.isEditable = false
        area.lineWrap = true
        area.wrapStyleWord = true
        area.isOpaque = false
        area.border = null
        area.font = chrome.normalFont(12f)
        area.foreground = if (muted) chrome.mutedForeground() else chrome.foreground()
        area.alignmentX = Component.LEFT_ALIGNMENT
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
