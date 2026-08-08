package com.ezevillo.gitreview.ui

import com.intellij.icons.AllIcons
import com.intellij.ui.JBColor
import com.intellij.util.ui.JBUI
import java.awt.Color
import java.awt.Font
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
    fun emptyBorder(top: Int = 0, left: Int = 0, bottom: Int = 0, right: Int = 0): Border
    fun monoFont(size: Float = 12f): Font
    fun boldFont(size: Float = 13f): Font
    fun normalFont(size: Float = 12f): Font
    fun iconPrev(): Icon?
    fun iconNext(): Icon?
    fun iconCopy(): Icon?
    fun iconDiff(): Icon?
    fun iconFile(): Icon?
    /** Fallback glyph when platform icons are unavailable (preview). */
    fun glyphPrev(): String = "◀"
    fun glyphNext(): String = "▶"
    fun glyphCopy(): String = "⎘"
}

class PluginPanelChrome : PanelChrome {
    override fun foreground(): Color = JBColor.foreground()
    override fun mutedForeground(): Color = JBColor.GRAY
    override fun background(): Color = JBColor.background()
    override fun borderColor(): Color = JBColor.border()
    override fun primaryButtonBackground(): Color =
        JBColor.namedColor("Button.default.startBackground", JBColor.BLUE)
    override fun emptyBorder(top: Int, left: Int, bottom: Int, right: Int): Border =
        JBUI.Borders.empty(top, left, bottom, right)
    override fun monoFont(size: Float): Font = Font(Font.MONOSPACED, Font.PLAIN, size.toInt())
    override fun boldFont(size: Float): Font = Font(Font.SANS_SERIF, Font.BOLD, size.toInt())
    override fun normalFont(size: Float): Font = Font(Font.SANS_SERIF, Font.PLAIN, size.toInt())
    override fun iconPrev(): Icon = AllIcons.Actions.Back
    override fun iconNext(): Icon = AllIcons.Actions.Forward
    override fun iconCopy(): Icon = AllIcons.Actions.Copy
    override fun iconDiff(): Icon = AllIcons.Actions.Diff
    override fun iconFile(): Icon = AllIcons.FileTypes.Any_type
}

class PreviewPanelChrome : PanelChrome {
    override fun foreground(): Color = UIManager.getColor("Label.foreground") ?: Color.BLACK
    override fun mutedForeground(): Color = UIManager.getColor("Label.disabledForeground") ?: Color.GRAY
    override fun background(): Color = UIManager.getColor("Panel.background") ?: Color.WHITE
    override fun borderColor(): Color = UIManager.getColor("Component.borderColor") ?: Color.LIGHT_GRAY
    override fun primaryButtonBackground(): Color =
        UIManager.getColor("Button.default.background") ?: Color(0x4A90D9)
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
}
