package com.ezevillo.gitreview.ui

import com.intellij.icons.AllIcons
import com.intellij.ide.ui.laf.darcula.ui.DarculaButtonUI
import com.intellij.openapi.editor.colors.EditorColorsManager
import com.intellij.ui.JBColor
import com.intellij.util.ui.JBUI
import com.intellij.util.ui.UIUtil
import java.awt.Color
import java.awt.Font
import javax.swing.AbstractButton
import javax.swing.Icon
import javax.swing.UIManager
import javax.swing.border.Border

/**
 * Theme tokens for [PanelRenderer]. Plugin uses JBColor/AllIcons; preview uses UIManager + glyphs.
 */
interface PanelChrome {
    fun foreground(): Color
    fun mutedForeground(): Color
    fun background(): Color
    fun borderColor(): Color
    fun primaryButtonBackground(): Color
    fun linkForeground(): Color

    /**
     * The two fills of a list row — the extension's `--vscode-list-hoverBackground`
     * and `--vscode-list-inactiveSelectionBackground`. A file row is a row of a
     * list and not a button: it only takes a fill under the pointer, or when it
     * is the one the reviewer opened last.
     */
    fun rowHoverBackground(): Color
    fun rowSelectedBackground(): Color

    /**
     * The solid badge — the extension's `--vscode-badge-*`, which is what it
     * paints `key` with. The IDE owns the same pair for its own counters, so a
     * marked entry reads as marked in every theme without a colour of ours.
     */
    fun badgeBackground(): Color
    fun badgeForeground(): Color

    /**
     * A block of code inside prose (`--vscode-textCodeBlock-background`): the
     * install command and whatever the CLI wrote to stderr. What the fill says
     * is "this is verbatim output", so it has to differ from the panel.
     */
    fun codeBackground(): Color

    /**
     * A stopped finish is not a passing note: it is the only thing the reviewer
     * can act on, so it takes the theme's own warning pair — never one of ours.
     */
    fun warningBackground(): Color
    fun warningBorder(): Color

    /**
     * Marks the one primary control of a situation. The extension paints it with
     * `--vscode-button-background`; here it is the IDE's own default-button
     * style, so "this is the action" reads the same without inventing a colour
     * the theme does not own.
     */
    fun markPrimary(button: AbstractButton)
    fun emptyBorder(top: Int = 0, left: Int = 0, bottom: Int = 0, right: Int = 0): Border
    fun monoFont(size: Float = 12f): Font
    fun boldFont(size: Float = 13f): Font
    fun normalFont(size: Float = 12f): Font
    fun iconPrev(): Icon?
    fun iconNext(): Icon?
    fun iconCopy(): Icon?
    fun iconDiff(): Icon?
    fun iconFile(): Icon?
    fun iconTrash(): Icon?
    /** Fallback glyph when platform icons are unavailable (preview). */
    fun glyphPrev(): String = "◀"
    fun glyphNext(): String = "▶"
    fun glyphCopy(): String = "⎘"
    fun glyphFile(): String = "▤"
    // BMP y de un solo ancho, como los demas: un codepoint astral (el tacho de
    // verdad, U+1F5D1) sale como caja vacia en la fuente que de el tema.
    fun glyphTrash(): String = "✕"
}

class PluginPanelChrome : PanelChrome {
    override fun foreground(): Color = JBColor.foreground()
    override fun mutedForeground(): Color = JBColor.GRAY
    override fun background(): Color = JBColor.background()
    override fun borderColor(): Color = JBColor.border()
    override fun primaryButtonBackground(): Color =
        JBColor.namedColor("Button.default.startBackground", JBColor.BLUE)
    override fun linkForeground(): Color = JBUI.CurrentTheme.Link.Foreground.ENABLED
    override fun rowHoverBackground(): Color = JBUI.CurrentTheme.List.Hover.background(true)
    override fun rowSelectedBackground(): Color = UIUtil.getListSelectionBackground(false)
    override fun badgeBackground(): Color =
        JBColor.namedColor("Counter.background", JBColor(0x3574F0, 0x3574F0))
    override fun badgeForeground(): Color =
        JBColor.namedColor("Counter.foreground", JBColor(0xFFFFFF, 0xFFFFFF))
    override fun codeBackground(): Color = UIUtil.getTextFieldBackground()
    override fun warningBackground(): Color =
        JBColor.namedColor("NotificationWarning.background", JBColor(0xFFF8E3, 0x594E32))
    override fun warningBorder(): Color =
        JBColor.namedColor("NotificationWarning.borderColor", JBColor(0xE0C888, 0x8A7A4B))
    override fun markPrimary(button: AbstractButton) {
        button.putClientProperty(DarculaButtonUI.DEFAULT_STYLE_KEY, true)
    }
    override fun emptyBorder(top: Int, left: Int, bottom: Int, right: Int): Border =
        JBUI.Borders.empty(top, left, bottom, right)

    /**
     * Paths, commands and stderr in the editor's own font — the extension's
     * `--vscode-editor-font-family`. `Font.MONOSPACED` resolves to whatever the
     * JDK picked (Courier New on Windows), which is not the face the reviewer
     * reads code in two panes over.
     */
    override fun monoFont(size: Float): Font {
        val name = EditorColorsManager.getInstance().globalScheme.editorFontName
        return Font(name, Font.PLAIN, size.toInt())
    }
    override fun boldFont(size: Float): Font = Font(Font.SANS_SERIF, Font.BOLD, size.toInt())
    override fun normalFont(size: Float): Font = Font(Font.SANS_SERIF, Font.PLAIN, size.toInt())
    override fun iconPrev(): Icon = AllIcons.Actions.Back
    override fun iconNext(): Icon = AllIcons.Actions.Forward
    override fun iconCopy(): Icon = AllIcons.Actions.Copy
    override fun iconDiff(): Icon = AllIcons.Actions.Diff
    override fun iconFile(): Icon = AllIcons.FileTypes.Any_type
    override fun iconTrash(): Icon = AllIcons.Actions.GC
}

class PreviewPanelChrome : PanelChrome {
    override fun foreground(): Color = UIManager.getColor("Label.foreground") ?: Color.BLACK
    override fun mutedForeground(): Color = UIManager.getColor("Label.disabledForeground") ?: Color.GRAY
    override fun background(): Color = UIManager.getColor("Panel.background") ?: Color.WHITE
    override fun borderColor(): Color = UIManager.getColor("Component.borderColor") ?: Color.LIGHT_GRAY
    override fun primaryButtonBackground(): Color =
        UIManager.getColor("Button.default.background") ?: Color(0x4A90D9)
    override fun linkForeground(): Color = Color(0x38, 0x7C, 0xC8)

    /**
     * No list tokens outside the IDE: the two fills are the panel foreground laid
     * over the panel background at the weight the extension gives them, so the
     * preview keeps working on whatever LaF it lands on (light or dark).
     */
    override fun rowHoverBackground(): Color =
        UIManager.getColor("List.hoverBackground") ?: blend(foreground(), background(), 0.08f)

    override fun rowSelectedBackground(): Color =
        UIManager.getColor("List.selectionInactiveBackground")
            ?: blend(foreground(), background(), 0.16f)

    override fun badgeBackground(): Color =
        UIManager.getColor("List.selectionBackground") ?: Color(0x35, 0x74, 0xF0)
    override fun badgeForeground(): Color =
        UIManager.getColor("List.selectionForeground") ?: Color.WHITE
    override fun codeBackground(): Color =
        UIManager.getColor("TextField.background") ?: blend(foreground(), background(), 0.06f)
    override fun warningBackground(): Color = blend(Color(0xE0, 0xC8, 0x88), background(), 0.22f)
    override fun warningBorder(): Color = Color(0xE0, 0xC8, 0x88)

    private fun blend(over: Color, under: Color, weight: Float): Color = Color(
        (over.red * weight + under.red * (1 - weight)).toInt(),
        (over.green * weight + under.green * (1 - weight)).toInt(),
        (over.blue * weight + under.blue * (1 - weight)).toInt(),
    )

    /**
     * No IDE LaF here: the fill is ours, so the preview shows the same weight.
     * `isContentAreaFilled = false` is what keeps the platform LaF from painting
     * its own background over it.
     */
    override fun markPrimary(button: AbstractButton) {
        button.isContentAreaFilled = false
        button.isOpaque = true
        button.background = primaryButtonBackground()
        button.foreground = Color.WHITE
    }
    override fun emptyBorder(top: Int, left: Int, bottom: Int, right: Int): Border =
        javax.swing.BorderFactory.createEmptyBorder(top, left, bottom, right)
    override fun monoFont(size: Float): Font = Font(Font.MONOSPACED, Font.PLAIN, size.toInt())
    override fun boldFont(size: Float): Font = Font(Font.SANS_SERIF, Font.BOLD, size.toInt())
    override fun normalFont(size: Float): Font = Font(Font.SANS_SERIF, Font.PLAIN, size.toInt())
    override fun iconPrev(): Icon? = null
    override fun iconNext(): Icon? = null
    override fun iconCopy(): Icon? = null
    override fun iconDiff(): Icon? = null
    override fun iconFile(): Icon? = null
    override fun iconTrash(): Icon? = null
}
