package com.ezevillo.gitreview.ui

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Locks the multi-IDE product matrix in source plugin.xml.
 *
 * Marketplace derives "compatible products" from module dependencies, not from
 * a product-code list in Gradle. The only durable contract is therefore the
 * source descriptor: platform + Git4Idea (load anywhere that ships both) and
 * incompatible-with for the two products we deliberately do not support.
 * pluginVerification.ides in build.gradle.kts must stay aligned with that
 * intent — add a product there only if plugin.xml would load on it.
 */
class PluginCompatibilityTest {
    @Test
    fun `depends on platform and Git4Idea only`() {
        val depends = textChildren("depends").toSet()
        assertEquals(
            setOf("com.intellij.modules.platform", "Git4Idea"),
            depends,
            "extra or missing <depends> change which IDEs Marketplace offers the plugin to",
        )
    }

    @Test
    fun `declares incompatibility with Android Studio and Rider`() {
        val incompatible = textChildren("incompatible-with").toSet()
        assertEquals(
            setOf(
                "com.intellij.modules.androidstudio",
                "com.intellij.modules.rider",
            ),
            incompatible,
            "Android Studio and Rider are out of scope — keep both <incompatible-with> entries",
        )
    }

    @Test
    fun `description advertises multi-IDE and names the exclusions`() {
        val description = textChildren("description").single()
        assertTrue(
            description.contains("WebStorm") && description.contains("PyCharm"),
            "Marketplace description should name peer IDEs, got: $description",
        )
        assertTrue(
            description.contains("Android Studio") && description.contains("Rider"),
            "description should say Android Studio and Rider are unsupported",
        )
    }

    @Test
    fun `no until-build is required in source — Gradle patches idea-version`() {
        // Source may omit idea-version entirely; patchPluginXml writes since/until
        // from gradle.properties. Guard against a hard-coded until that would
        // re-cap compatibility if someone pastes a full idea-version here.
        val xml = pluginXml().readText()
        assertFalse(
            Regex("""until-build\s*=\s*"[^"]+"""").containsMatchIn(xml),
            "source plugin.xml must not hard-code until-build; use pluginUntilBuild",
        )
    }

    private fun textChildren(tag: String): List<String> {
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(pluginXml())
        val nodes = doc.getElementsByTagName(tag)
        val out = mutableListOf<String>()
        for (i in 0 until nodes.length) {
            val el = nodes.item(i) as Element
            out += el.textContent.trim()
        }
        assertTrue(out.isNotEmpty(), "no <$tag> in plugin.xml")
        return out
    }

    private fun pluginXml(): File {
        val root = System.getProperty("git.review.monorepo.root")
        assertNotNull(root, "git.review.monorepo.root is not set — see build.gradle.kts")
        val xml = File(root, "jetbrains-plugin/src/main/resources/META-INF/plugin.xml")
        assertTrue(xml.isFile, "plugin.xml missing at ${xml.absolutePath}")
        return xml
    }
}
