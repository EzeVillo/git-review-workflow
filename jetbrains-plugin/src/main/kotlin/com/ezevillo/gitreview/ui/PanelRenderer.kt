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
import java.awt.Container
import java.awt.Dimension
import java.awt.FlowLayout
import java.awt.Font
import java.awt.Graphics
import java.awt.Graphics2D
import java.awt.GridLayout
import java.awt.Insets
import java.awt.Rectangle
import java.awt.RenderingHints
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

/** Corner of a badge (the extension's `border-radius: 3px`). */
private const val CHIP_ARC = 6

/**
 * Generic Swing renderer of [PanelLayout]. No Project / GitReviewService.
 * @param onAction callback with control id, optional inventory/file index, and
 *   optional openSupport link id (`star` / `bug`)
 * @return true from onAction if the control should show transient "Copied" feedback
 */
class PanelRenderer(
    private val chrome: PanelChrome,
    private val onAction: (ControlId, Int?, String?) -> Boolean = { _, _, _ -> false },
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
            is Block.Note -> renderNote(block)
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
                // The entry's identifier: a path, or a commit subject. It is what
                // gets pasted into a terminal, so it reads in the editor's font —
                // and a missing subject is the absence said, in italics.
                if (block.skeleton) {
                    skeletonBar(60)
                } else {
                    val t = wrapText(block.text, muted = block.muted)
                    t.font = if (block.muted) {
                        chrome.normalFont(12f).deriveFont(Font.ITALIC)
                    } else {
                        chrome.monoFont(12f)
                    }
                    t
                }
            }
            is Block.Why -> renderWhy(block)
            is Block.Row -> renderRow(block.controls)
            is Block.FileRows -> renderFileRows(block)
            is Block.InventoryRows -> renderInventory(block)
            is Block.DraftRows -> renderDrafts(block)
            is Block.GuideRows -> renderGuides(block)
            // One row, drawn by the same renderer: the shape is a guide row's --
            // a name, a badge, an icon in the header and a labelled button
            // underneath -- so a second implementation would be the same code
            // with a different chance of drifting from it.
            is Block.WalkthroughRow -> renderGuides(Block.GuideRows(listOf(block.row)))
            // Same shape again, same renderer: a name, a badge and the icon in
            // the header. What a fixes row does not have is a labelled button,
            // and the guide renderer already draws none when there is none.
            is Block.FixesRows -> renderGuides(Block.GuideRows(block.rows))
            is Block.ToolsSection -> renderToolsSection(block)
            is Block.Stderr -> renderStderr(block.text)
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
                    p.add(stacked(renderStderr(it)))
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

    /**
     * What the CLI wrote, verbatim. The fill is what says so — the extension's
     * `.stderr` block; muted text alone reads as one more sentence of ours.
     */
    private fun renderStderr(text: String): JComponent {
        val area = WrappedText(text)
        area.isEditable = false
        area.lineWrap = true
        area.wrapStyleWord = true
        area.font = chrome.monoFont(11f)
        area.foreground = chrome.mutedForeground()
        area.background = chrome.codeBackground()
        area.border = chrome.emptyBorder(6, 6, 6, 6)
        area.alignmentX = Component.LEFT_ALIGNMENT
        return area
    }

    /**
     * A note describes the review, not the entry, so it sits between the bar and
     * the body with a rule of its own — the extension's `.note { border-bottom }`.
     */
    private fun renderNote(note: Block.Note): JComponent {
        val box = JPanel(BorderLayout())
        box.background = chrome.background()
        box.alignmentX = Component.LEFT_ALIGNMENT
        box.border = javax.swing.BorderFactory.createCompoundBorder(
            javax.swing.BorderFactory.createMatteBorder(0, 0, 1, 0, chrome.borderColor()),
            chrome.emptyBorder(0, 0, 6, 0),
        )
        box.add(wrapText(note.text, muted = true), BorderLayout.CENTER)
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
        // Every field of the bar is something the reviewer retypes in a terminal
        // (the mode, the branch, the abbreviated tip), so the whole line reads in
        // the editor's font like the extension's `.bar`.
        val left = ArrayList<JComponent>()
        left.add(monoLabel(bar.mode, muted = false, bold = true))
        if (bar.draft) {
            left.add(monoLabel("(draft)"))
        }
        left.add(monoLabel(bar.name, muted = false))
        bar.tip?.let { left.add(monoLabel(it)) }
        val right = ArrayList<JComponent>()
        if (bar.skeleton) {
            right.add(skeletonBar(36))
        } else if (bar.position != null && bar.total != null) {
            right.add(monoLabel("${bar.position}/${bar.total}"))
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
        left.add(monoLabel(n, bold = true))
        head.identifier?.let { left.add(monoLabel(it)) }
        head.author?.let { left.add(monoLabel(it)) }
        val right = head.badge?.let { listOf<JComponent>(chipLabel(it)) } ?: emptyList()
        return headerRow(left, right)
    }

    /**
     * The why is quoted prose — the author's, or the panel saying there is none.
     * The rule at its left is what separates it from the panel's own voice
     * (the extension's `.why { border-left }`); without it a walkthrough entry
     * and a diagnostic look like the same sentence.
     */
    private fun renderWhy(why: Block.Why): JComponent {
        val content: JComponent = when (why.state) {
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
            WhyState.ABSENT, WhyState.FAILED -> {
                val t = wrapText(why.text.orEmpty(), muted = true)
                t.font = chrome.normalFont(12f).deriveFont(Font.ITALIC)
                t
            }
        }
        val box = JPanel(BorderLayout())
        box.background = chrome.background()
        box.alignmentX = Component.LEFT_ALIGNMENT
        box.border = javax.swing.BorderFactory.createCompoundBorder(
            javax.swing.BorderFactory.createMatteBorder(0, 2, 0, 0, chrome.borderColor()),
            chrome.emptyBorder(0, 7, 0, 0),
        )
        box.add(content, BorderLayout.CENTER)
        return box
    }

    /**
     * A stopped finish: not a note in passing but the only thing that can be
     * done right now, so it carries the theme's warning fill and a bar at its
     * left, like the extension's `.note.finish-banner`.
     */
    private fun renderBanner(banner: Block.Banner): JComponent {
        val box = JPanel()
        box.layout = BoxLayout(box, BoxLayout.Y_AXIS)
        box.background = chrome.warningBackground()
        box.isOpaque = true
        box.border = javax.swing.BorderFactory.createCompoundBorder(
            javax.swing.BorderFactory.createMatteBorder(0, 3, 0, 0, chrome.warningBorder()),
            chrome.emptyBorder(6, 6, 6, 6),
        )
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
        // Fenced code, like the extension's `.code-block`: the fill is what says
        // "this line is meant to be pasted", not the frame around it.
        code.background = chrome.codeBackground()
        code.foreground = chrome.foreground()
        code.border = javax.swing.BorderFactory.createCompoundBorder(
            javax.swing.BorderFactory.createLineBorder(chrome.borderColor()),
            chrome.emptyBorder(4, 5, 4, 5),
        )
        row.add(code, BorderLayout.CENTER)
        row.add(renderControl(cmd.copy), BorderLayout.EAST)
        return row
    }

    private fun renderRow(controls: List<Control>): JComponent {
        // A lone link is not a button in disguise: the extension leaves it inline
        // at the start of the line, and stretching it across the sidebar made
        // "open in editor" read as the pane's main action.
        val single = controls.singleOrNull()
        if (single != null && single.emphasis == Emphasis.LINK) {
            val row = JPanel(FlowLayout(FlowLayout.LEFT, 0, 0))
            row.isOpaque = false
            row.alignmentX = Component.LEFT_ALIGNMENT
            row.add(renderControl(single))
            return row
        }
        val panel = object : JPanel() {
            override fun getMaximumSize(): Dimension {
                val pref = preferredSize
                return Dimension(Int.MAX_VALUE, pref.height)
            }
        }
        panel.alignmentX = Component.LEFT_ALIGNMENT
        panel.isOpaque = false
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
            onAction(ControlId.OPEN_CHANGE, f.index, null)
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
            for (b in r.badges) badges.add(chipLabel(b))
            if (r.controls.isEmpty() && r.helpTooltip != null) {
                val help = chipLabel("?")
                help.toolTipText = r.helpTooltip
                badges.add(help)
            }
            box.add(
                stacked(
                    headerRow(
                        // A ref name, in the editor's font: it is what gets
                        // retyped after `git review continue`.
                        listOf(monoLabel(r.name, muted = false)),
                        badges,
                    ),
                ),
            )
            box.add(
                stacked(
                    monoLabel(r.meta).apply {
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

    /**
     * The draft block. Same shape as an inventory row — name, meta, actions —
     * because it is the same kind of thing: a row of the empty state you act on.
     * Product parity, not pixel parity: what has to match VS Code is the order,
     * the labels and which controls a row offers.
     */
    private fun renderDrafts(block: Block.DraftRows): JComponent {
        val box = JPanel()
        box.layout = BoxLayout(box, BoxLayout.Y_AXIS)
        box.background = chrome.background()
        box.alignmentX = Component.LEFT_ALIGNMENT
        for (r in block.rows) {
            // The progress rides the header instead of a line of its own: it is
            // a badge-sized fact about the branch, and one loose line per row
            // multiplied the height of the block for nothing.
            //
            // The ICON controls ride it too, right after the pair that names
            // their subject. Which half of the row a control lands in is read
            // off its emphasis and decided nowhere else: the layout already
            // says which of the four are glyphs.
            val (glyphs, labelled) = r.controls.partition { it.emphasis == Emphasis.ICON }
            val right = ArrayList<JComponent>()
            // The badge CLOSES the line, in every row of the panel: that is what
            // drops the states of all three sections into the same column at the
            // right edge. The glyphs go before it, still glued to the fact that
            // names their subject.
            for (c in glyphs) {
                right.add(renderControl(c, bare = true))
            }
            right.add(chipLabel(r.meta))
            box.add(
                stacked(
                    headerRow(listOf(monoLabel(r.name, muted = false)), right),
                ),
            )
            // A grid of two even columns, not a row that wraps: at sidebar
            // width two long labels do not fit on one line of free widths, and
            // wrapping them broke every row in a different place — none lined
            // up with the one beside it. Even cells always do.
            val actions = JPanel(GridLayout(1, labelled.size, 4, 4))
            actions.background = chrome.background()
            actions.alignmentX = Component.LEFT_ALIGNMENT
            for (c in labelled) {
                actions.add(renderControl(c))
            }
            box.add(stacked(actions))
            // Two draft rows in a row need more air between them than two
            // inventory ones: each is a header with glyphs plus its own button
            // pair, and without the gap the two read as a single pane.
            box.add(Box.createVerticalStrut(10))
        }
        return box
    }

    /**
     * The authoring-guide rows. Same two-place shape as the draft rows -- badge
     * and glyphs in the header, the labelled control underneath -- because they
     * are the same kind of thing, and the reviewer should not have to learn a
     * second row.
     *
     * Less air between rows than between drafts: there are exactly two, they
     * belong together, and they sit inside a collapsed section rather than at the
     * top of the empty state.
     */
    private fun renderGuides(block: Block.GuideRows): JComponent {
        val box = JPanel()
        box.layout = BoxLayout(box, BoxLayout.Y_AXIS)
        box.background = chrome.background()
        box.alignmentX = Component.LEFT_ALIGNMENT
        for (r in block.rows) {
            val (glyphs, labelled) = r.controls.partition { it.emphasis == Emphasis.ICON }
            val right = ArrayList<JComponent>()
            for (c in glyphs) {
                right.add(renderControl(c, bare = true))
            }
            right.add(chipLabel(r.badge))
            box.add(
                stacked(
                    headerRow(listOf(monoLabel(r.name, muted = false)), right),
                ),
            )
            // Left, at label width, like the inventory's actions -- and unlike
            // the draft rows above, whose two even columns exist so that row
            // after row lines up. Here the count is one (a guide) or three (the
            // walkthrough): even cells would stretch a lone Create across half
            // the sidebar and squeeze three labels that fit as they are.
            val actions = JPanel(FlowLayout(FlowLayout.LEFT, 4, 0))
            actions.background = chrome.background()
            actions.alignmentX = Component.LEFT_ALIGNMENT
            for (c in labelled) {
                actions.add(renderControl(c))
            }
            box.add(stacked(actions))
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

        // A section header of the sidebar: ruled off from what sits above it and
        // quieter than the body, like the extension's `.tools summary`.
        box.border = javax.swing.BorderFactory.createMatteBorder(1, 0, 0, 0, chrome.borderColor())

        val toggle = JButton((if (open) "▼ " else "▶ ") + section.title)
        toggle.isBorderPainted = false
        toggle.isContentAreaFilled = false
        toggle.horizontalAlignment = JButton.LEFT
        toggle.alignmentX = Component.LEFT_ALIGNMENT
        toggle.foreground = chrome.mutedForeground()
        toggle.font = chrome.boldFont(11f)

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

    /**
     * @param bare un control de icono que va en la CABECERA de una fila, no en
     *   una fila de controles: sin caja y con relleno recien bajo el puntero.
     *   La distincion es del sitio y no del control, igual que en la extension,
     *   donde la regla cuelga de `.rev-head-actions button` y no del icono: los
     *   mismos glifos en la nav row de una review son dos botones rellenos que
     *   se reparten el ancho (`.row button { flex: 1 }`).
     */
    fun renderControl(c: Control, bare: Boolean = false): JComponent {
        val btn = when (c.emphasis) {
            Emphasis.ICON -> {
                // Un icono en la CABECERA de una fila es una afordancia sobre
                // esa fila, no una accion del panel: la extension lo dibuja sin
                // caja y le da relleno recien bajo el puntero (`background:
                // none` mas el hover de la toolbar), igual que fileRow aca
                // arriba y por el mismo motivo. Con el JButton de fabrica manda
                // DarculaButtonUI, que le impone su ancho minimo (72px mas 14
                // de padding): un glifo de 16 termina en un marco cuatro veces
                // mas ancho que el, y tres cajas asi en una cabecera pesan mas
                // que la botonera de abajo, que es la que si mueve el flujo.
                // Asi que ahi la medida la damos nosotros, como el relleno.
                val hover = chrome.rowHoverBackground()
                val focus = chrome.linkForeground()
                val b = object : JButton() {
                    override fun paintComponent(g: Graphics) {
                        if (bare) {
                            if (isEnabled && (model.isRollover || model.isPressed)) {
                                g.color = hover
                                g.fillRect(0, 0, width, height)
                            }
                            // El LaF no pinta anillo de foco sobre un boton sin
                            // borde, y el teclado es la unica forma de llegar a
                            // estos glifos sin mouse.
                            if (isFocusOwner) {
                                g.color = focus
                                g.drawRect(0, 0, width - 1, height - 1)
                            }
                        }
                        super.paintComponent(g)
                    }

                    override fun getPreferredSize(): Dimension {
                        if (!bare) return super.getPreferredSize()
                        val ins = insets
                        val ic = icon
                        val w: Int
                        val h: Int
                        if (ic != null) {
                            w = ic.iconWidth
                            h = ic.iconHeight
                        } else {
                            val fm = getFontMetrics(font)
                            w = fm.stringWidth(text ?: "")
                            h = fm.height
                        }
                        return Dimension(w + ins.left + ins.right, h + ins.top + ins.bottom)
                    }

                    override fun getMinimumSize(): Dimension =
                        if (bare) preferredSize else super.getMinimumSize()

                    override fun getMaximumSize(): Dimension =
                        if (bare) preferredSize else super.getMaximumSize()
                }
                val icon = when (c.id) {
                    ControlId.PREV -> chrome.iconPrev()
                    ControlId.NEXT -> chrome.iconNext()
                    ControlId.COPY_CLI_INSTALL -> chrome.iconCopy()
                    // EVERY file-and-trash affordance of the panel, not just
                    // the draft's: a guide row's Open and Discard, the
                    // walkthrough row's Open and a fixes row's Discard are the
                    // same two affordances over a different subject, and the
                    // canonical declares the same two icons for them. Missing
                    // here, they fall through to the accessible name below -- a
                    // sentence-wide button in a header that a glyph exists to
                    // keep narrow. It happened twice: once when the guides
                    // arrived and again when the fixes rows did, which is why
                    // the drift is now pinned over EVERY fixture rather than
                    // over a hand-written list of names.
                    ControlId.OPEN_DRAFT,
                    ControlId.OPEN_GUIDE,
                    ControlId.OPEN_WALKTHROUGH,
                    -> chrome.iconFile()
                    ControlId.DISCARD_DRAFT,
                    ControlId.DISCARD_GUIDE,
                    ControlId.DISCARD_FIXES,
                    -> chrome.iconTrash()
                    else -> null
                }
                if (icon != null) {
                    b.icon = icon
                } else {
                    b.text = when (c.id) {
                        ControlId.PREV -> chrome.glyphPrev()
                        ControlId.NEXT -> chrome.glyphNext()
                        ControlId.COPY_CLI_INSTALL -> chrome.glyphCopy()
                        ControlId.OPEN_DRAFT,
                        ControlId.OPEN_GUIDE,
                        ControlId.OPEN_WALKTHROUGH,
                        -> chrome.glyphFile()
                        ControlId.DISCARD_DRAFT,
                        ControlId.DISCARD_GUIDE,
                        ControlId.DISCARD_FIXES,
                        -> chrome.glyphTrash()
                        // Un id de icono sin glifo cae al nombre accesible, que
                        // es una oracion: el control se vuelve el mas ancho de
                        // su fila, que es justo lo que un icono viene a evitar.
                        else -> c.accessibleName
                    }
                }
                if (bare) {
                    b.isContentAreaFilled = false
                    b.isBorderPainted = false
                    b.isFocusPainted = false
                    b.isOpaque = false
                    b.isRolloverEnabled = true
                    b.margin = Insets(0, 0, 0, 0)
                    b.border = chrome.emptyBorder(3, 4, 3, 4)
                    b.foreground = chrome.mutedForeground()
                }
                // The name is the floor; the tooltip proper, when the layout
                // gave the control one, replaces it at the bottom of this
                // function along with every other emphasis.
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
                        // No button padding around a link: it starts where the
                        // text above it starts (the extension's `padding: 0`).
                        b.margin = Insets(0, 0, 0, 0)
                        b.border = chrome.emptyBorder()
                    }
                    Emphasis.PRIMARY -> chrome.markPrimary(b)
                    else -> Unit
                }
                b
            }
        }
        btn.isEnabled = c.enabled
        // Un control cuyo nombre accesible no es su etiqueta lo dice: "Open" a
        // secas se repite una vez por fila del bloque de borradores y no nombra
        // a ninguna, asi que lo que se lee en voz alta es la oracion.
        if (c.accessibleName != c.label) {
            btn.accessibleContext.accessibleName = c.accessibleName
        }
        c.tooltip?.let { btn.toolTipText = it }
        btn.addActionListener {
            if (!btn.isEnabled) return@addActionListener
            val copied = onAction(c.id, c.index, c.supportLinkId)
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

    /** A field of the bar or the head: an identifier, in the editor's font. */
    private fun monoLabel(text: String, muted: Boolean = true, bold: Boolean = false): JLabel {
        val l = JLabel(text)
        val base = chrome.monoFont(11f)
        l.font = if (bold) base.deriveFont(Font.BOLD) else base
        l.foreground = if (muted) chrome.mutedForeground() else chrome.foreground()
        return l
    }

    /**
     * A mark on an entry or an inventory row, in the extension's three weights:
     * `key` is what the walkthrough author called essential and goes solid, in
     * the theme's own counter colours; `uncovered` is a warning of ours and goes
     * bare; everything else — `edits`, `current`, `orphan` — is a state and goes
     * in outline. Which is which is read off the text, exactly as the extension
     * reads it off the class.
     */
    private fun chipLabel(text: String): JComponent {
        val solid = text == "key"
        val bare = text == "uncovered" || text == "?"
        val fg = when {
            solid -> chrome.badgeForeground()
            bare -> chrome.mutedForeground()
            else -> chrome.foreground()
        }
        val fill = if (solid) chrome.badgeBackground() else null
        val line = if (solid || bare) null else chrome.borderColor()
        val label = object : JLabel(text) {
            override fun paintComponent(g: Graphics) {
                val g2 = g.create() as Graphics2D
                g2.setRenderingHint(
                    RenderingHints.KEY_ANTIALIASING,
                    RenderingHints.VALUE_ANTIALIAS_ON,
                )
                if (fill != null) {
                    g2.color = fill
                    g2.fillRoundRect(0, 0, width, height, CHIP_ARC, CHIP_ARC)
                }
                if (line != null) {
                    g2.color = line
                    g2.drawRoundRect(0, 0, width - 1, height - 1, CHIP_ARC, CHIP_ARC)
                }
                g2.dispose()
                super.paintComponent(g)
            }
        }
        label.font = chrome.normalFont(10f)
        label.foreground = fg
        label.isOpaque = false
        label.border = chrome.emptyBorder(1, 4, 1, 4)
        return label
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
                if (c is Container) {
                    for (ch in c.components) walk(ch)
                }
            }
            walk(root)
            return out
        }
    }
}
