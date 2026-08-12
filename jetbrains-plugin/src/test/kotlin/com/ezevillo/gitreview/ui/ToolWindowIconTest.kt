package com.ezevillo.gitreview.ui

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * The stripe icon is the one piece of the plugin that fails silently: point the
 * plugin.xml at a path that is not there and the platform draws a placeholder
 * instead of raising anything, and the same goes for the _dark name it derives on
 * its own. So the two ends are tied here — what the XML asks for and what ships
 * in resources — and so is the third: the mark is the VS Code extension's file,
 * copied, so the geometry is compared against it shape by shape.
 */
class ToolWindowIconTest {
    @Test
    fun `the tool window icon in plugin xml resolves to a shipped resource`() {
        val icon = toolWindowIconAttribute()
        assertTrue(
            icon.startsWith("/"),
            "the tool window icon must be a plugin resource path, not $icon",
        )
        assertTrue(
            resources().resolve(icon.removePrefix("/")).isFile,
            "plugin.xml points at $icon but no such file is under src/main/resources",
        )
        assertNotNull(
            javaClass.getResource(icon),
            "$icon is not on the classpath, so the platform will not find it either",
        )
    }

    @Test
    fun `the dark variant the platform derives is present`() {
        val icon = toolWindowIconAttribute().removePrefix("/").removeSuffix(".svg")
        assertTrue(
            resources().resolve("${icon}_dark.svg").isFile,
            "missing ${icon}_dark.svg — the platform derives that name and falls back silently",
        )
    }

    @Test
    fun `both variants are the extension's mark at the size the stripe asks for`() {
        val icon = toolWindowIconAttribute().removePrefix("/").removeSuffix(".svg")
        val source = svgRoot(File(extensionMedia(), "activity-bar.svg"))
        for (suffix in listOf("", "_dark")) {
            val svg = svgRoot(resources().resolve("$icon$suffix.svg"))
            assertEquals("16", svg.getAttribute("width"), "width of $icon$suffix.svg")
            assertEquals("16", svg.getAttribute("height"), "height of $icon$suffix.svg")
            // Same viewBox as the extension's file: the geometry is copied, not
            // redrawn, so the two clients cannot drift into different marks.
            assertEquals(
                source.getAttribute("viewBox"),
                svg.getAttribute("viewBox"),
                "viewBox of $icon$suffix.svg vs the extension's activity-bar.svg",
            )
            assertEquals(
                shapesOf(source),
                shapesOf(svg),
                "$icon$suffix.svg drifted from vscode-extension/media/activity-bar.svg",
            )
        }
    }

    @Test
    fun `the marketplace icon ships in both themes at the size JetBrains asks for`() {
        for (name in listOf("pluginIcon.svg", "pluginIcon_dark.svg")) {
            val file = resources().resolve("META-INF/$name")
            assertTrue(file.isFile, "missing META-INF/$name — the Marketplace falls back to a stub")
            val svg = svgRoot(file)
            assertEquals("40", svg.getAttribute("width"), "width of $name")
            assertEquals("40", svg.getAttribute("height"), "height of $name")
        }
    }

    private fun resources(): File {
        val root = System.getProperty("git.review.monorepo.root")
        assertNotNull(root, "git.review.monorepo.root is not set — see build.gradle.kts")
        val dir = File(root, "jetbrains-plugin/src/main/resources")
        assertTrue(dir.isDirectory, "resources missing at ${dir.absolutePath}")
        return dir
    }

    private fun toolWindowIconAttribute(): String {
        val xml = resources().resolve("META-INF/plugin.xml")
        assertTrue(xml.isFile, "plugin.xml missing at ${xml.absolutePath}")
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(xml)
        val nodes = doc.getElementsByTagName("toolWindow")
        assertEquals(1, nodes.length, "expected exactly one toolWindow declaration")
        val element = nodes.item(0) as Element
        assertEquals(
            "gitReview.walkthrough",
            element.getAttribute("id"),
            "the tool window id is part of the client contract",
        )
        val icon = element.getAttribute("icon")
        assertTrue(icon.isNotBlank(), "the toolWindow declaration has no icon attribute")
        return icon
    }

    private fun svgRoot(file: File): Element =
        DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file).documentElement

    private fun extensionMedia(): File {
        val root = System.getProperty("git.review.monorepo.root")
        val dir = File(root, "vscode-extension/media")
        assertTrue(dir.isDirectory, "extension media missing at ${dir.absolutePath}")
        return dir
    }

    /** Geometry only — colour is the one thing the two clients are allowed to differ on. */
    private fun shapesOf(svg: Element): List<String> {
        val geometry = listOf(
            "x", "y", "width", "height", "rx", "ry",
            "cx", "cy", "r", "x1", "y1", "x2", "y2", "d", "points", "transform",
        )
        val out = mutableListOf<String>()
        fun walk(element: Element) {
            val children = element.childNodes
            for (i in 0 until children.length) {
                val child = children.item(i) as? Element ?: continue
                if (child.tagName != "g" && child.tagName != "defs") {
                    val attrs = geometry
                        .filter { child.hasAttribute(it) }
                        .joinToString(" ") { "$it=${child.getAttribute(it)}" }
                    out += "${child.tagName} $attrs"
                }
                walk(child)
            }
        }
        walk(svg)
        return out
    }
}
