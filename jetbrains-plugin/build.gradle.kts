import org.jetbrains.changelog.Changelog
import org.jetbrains.intellij.platform.gradle.IntelliJPlatformType
import org.jetbrains.kotlin.gradle.dsl.JvmDefaultMode
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("java")
    // Match platform Kotlin metadata; target JVM 21 (2026.1 platform Java level).
    id("org.jetbrains.kotlin.jvm") version "2.3.20"
    id("org.jetbrains.intellij.platform") version "2.18.1"
    // Renders CHANGELOG.md into the descriptor's <change-notes> (see below).
    id("org.jetbrains.changelog") version "2.4.0"
}

group = providers.gradleProperty("pluginGroup").get()
version = providers.gradleProperty("pluginVersion").get()

repositories {
    mavenCentral()
    intellijPlatform {
        defaultRepositories()
    }
}

dependencies {
    intellijPlatform {
        // IC is no longer published since 2025.3 — use intellijIdea(version).
        intellijIdea(providers.gradleProperty("platformVersion"))
        bundledPlugin("Git4Idea")
        // Extracted from the platform core in 2025.3+; manager/mapping types
        // live in the .impl module (API jar alone is not enough).
        bundledModule("intellij.platform.vcs.dvcs")
        bundledModule("intellij.platform.vcs.dvcs.impl")
        // Platform test framework is for platformTest (T030a), not domain unit tests.
        // testFramework(TestFrameworkType.Platform)
    }

    // Pure JUnit 5 for domain (no IDE host).
    testImplementation("org.junit.jupiter:junit-jupiter:5.11.4")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    // PanelLayoutContractTest reads contracts/client-product-surface.yaml (test-only).
    testImplementation("org.yaml:snakeyaml:2.3")
}

kotlin {
    jvmToolchain(21)
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_21)
        // Sin esto, kotlinc genera un override delegante por cada default method
        // de las interfaces Java que implementamos — p. ej. ToolWindowFactory —,
        // y cada delegación es un `invokespecial` a la interfaz. El verifier del
        // Marketplace las lee como uso propio de API deprecada/experimental
        // (isApplicable, isDoNotActivateOnStart, getAnchor, getIcon, manage) sobre
        // métodos que el plugin nunca escribió ni llama. NO_COMPATIBILITY no emite
        // esos puentes ni las clases DefaultImpls: nada externo compila contra este
        // módulo, así que la ABI que se pierde no la usa nadie.
        jvmDefault.set(JvmDefaultMode.NO_COMPATIBILITY)
    }
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(21))
    }
}

// CHANGELOG.md is the single source of release notes for this client: the
// Marketplace tab (changeNotes, below), the update dialog inside the IDE, and
// the GitHub Release body all read this one file. Keep a Changelog format,
// headings written by hand after bump-version.sh stamps the version.
changelog {
    path = file("CHANGELOG.md").canonicalPath
    version = providers.gradleProperty("pluginVersion")
    // patchChangelog is not part of the release path; the headings are edited by
    // hand. These only shape what `renderItem` emits.
    itemPrefix = "-"
    repositoryUrl = "https://github.com/EzeVillo/git-review-workflow"
}

intellijPlatform {
    // instrumentCode needs a full JDK layout; some Windows JDKs (e.g. Microsoft)
    // omit Packages/ and break :instrumentCode. Domain tests do not need it.
    instrumentCode = false

    pluginConfiguration {
        name = providers.gradleProperty("pluginName")
        version = providers.gradleProperty("pluginVersion")

        // No `description` here on purpose. It is the Marketplace listing body,
        // and setting it would overwrite the <description> in the source
        // plugin.xml with a second copy nothing checks — PluginCompatibilityTest
        // asserts on the descriptor, so the two used to drift silently (the
        // Gradle copy still claimed parity with "the VS Code extension" alone
        // after the Visual Studio client shipped). One copy, in plugin.xml.

        // The Marketplace "What's New" tab, and the release notes the IDE shows
        // before an update. Rendered from the same CHANGELOG.md section that
        // release-jetbrains.yml turns into the GitHub Release body, so the two
        // cannot disagree. No section for this version yet (bump-version.sh
        // stamps the version, the heading is written by hand afterwards) →
        // point at the file instead of publishing an empty tab.
        changeNotes = providers.gradleProperty("pluginVersion").map { v ->
            // Both lookups throw on a missing section, and the whole point of the
            // fallback is that packaging never fails over prose: a build between
            // the version bump and the CHANGELOG heading still has to produce a
            // zip. runCatching, not get-or-throw.
            val item = changelog.getOrNull(v)
                ?: runCatching { changelog.getUnreleased() }.getOrNull()
            val html = item?.let {
                changelog.renderItem(
                    it.withHeader(false).withEmptySections(false),
                    Changelog.OutputType.HTML,
                )
            }.orEmpty()
            html.ifBlank {
                "See <a href=\"https://github.com/EzeVillo/git-review-workflow/blob/main/" +
                    "jetbrains-plugin/CHANGELOG.md\">CHANGELOG.md</a>."
            }
        }

        ideaVersion {
            sinceBuild = providers.gradleProperty("pluginSinceBuild")
            // Empty pluginUntilBuild → open-ended (no until-build attribute). Explicit
            // null, not the Gradle-plugin default of MAJOR.*, so later IDE lines stay
            // installable without a plugin rebuild for the range alone.
            untilBuild = providers.gradleProperty("pluginUntilBuild")
                .map { it.takeIf(String::isNotBlank) }
                .orElse(provider { null })
        }
    }

    // Marketplace upload, driven by .github/workflows/release-jetbrains.yml.
    // The token is a Marketplace permanent token (Profile -> My Tokens) with
    // rights over this plugin; it only exists as a CI secret, so the provider is
    // absent locally and *only* publishPlugin notices — build, verify, runIde and
    // the tests are untouched by the empty value.
    //
    // Signing is deliberately not wired: the Marketplace accepts unsigned
    // uploads (it signs them with its own certificate), which is how 0.1.x
    // shipped. To sign with our own key instead, add a `signing { }` block here
    // reading CERTIFICATE_CHAIN / PRIVATE_KEY / PRIVATE_KEY_PASSWORD from the
    // environment — publishPlugin then uploads the signed archive on its own.
    publishing {
        token = providers.environmentVariable("PUBLISH_TOKEN")
    }

    pluginVerification {
        ides {
            // Same platform line we compile against, one binary per product that
            // publishes a verifier download for that line. Marketplace product
            // coverage still comes from plugin.xml (platform + Git4Idea); this
            // list is binary-compat only. Android Studio and Rider are omitted
            // on purpose — plugin.xml marks them incompatible-with.
            // DataGrip is not in the JetBrains plugin-verifier binary index for
            // this line (create() fails to resolve a download URL); it remains
            // Marketplace-eligible via the same depends as the others.
            val line = providers.gradleProperty("platformVersion")
            create(IntelliJPlatformType.IntellijIdea, line)
            create(IntelliJPlatformType.WebStorm, line)
            create(IntelliJPlatformType.PhpStorm, line)
            create(IntelliJPlatformType.PyCharm, line)
            create(IntelliJPlatformType.GoLand, line)
            create(IntelliJPlatformType.CLion, line)
            create(IntelliJPlatformType.RubyMine, line)
            create(IntelliJPlatformType.RustRover, line)
        }
    }
}

tasks {
    test {
        useJUnitPlatform()
    }

    register("platformTest") {
        group = "verification"
        description = "Headless IntelliJ platform tests (wired in T030a)"
        dependsOn(test)
    }
}

tasks.register("checkDomainNoIntellij") {
    group = "verification"
    description = "Fail if domain sources import com.intellij"
    val domainDir = layout.projectDirectory.dir("src/main/kotlin/com/ezevillo/gitreview/domain")
    inputs.dir(domainDir)
    doLast {
        val dir = domainDir.asFile
        if (!dir.exists()) return@doLast
        val offenders = dir.walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .flatMap { f ->
                f.readLines().mapIndexedNotNull { i, line ->
                    if (line.contains("com.intellij")) {
                        "${f.relativeTo(dir)}:${i + 1}: $line"
                    } else {
                        null
                    }
                }
            }
            .toList()
        if (offenders.isNotEmpty()) {
            throw GradleException(
                "domain must not import com.intellij:\n${offenders.joinToString("\n")}",
            )
        }
    }
}

tasks.named("check") {
    dependsOn("checkDomainNoIntellij")
}

// Fixtures shared by unit tests and standalone preview (feature 010).
// Preview reuses domain + fixtures without the IntelliJ Platform host.
sourceSets {
    create("fixtures") {
        kotlin.srcDir("fixtures")
        compileClasspath += sourceSets["main"].output + configurations["compileClasspath"]
        runtimeClasspath += output + compileClasspath
    }
    create("preview") {
        kotlin.srcDir("preview")
        compileClasspath += sourceSets["main"].output +
                sourceSets["fixtures"].output +
                configurations["compileClasspath"]
        runtimeClasspath += output + compileClasspath
    }
    named("test") {
        compileClasspath += sourceSets["fixtures"].output
        runtimeClasspath += sourceSets["fixtures"].output
    }
}

configurations {
    getByName("fixturesImplementation").extendsFrom(configurations.getByName("implementation"))
    getByName("previewImplementation").extendsFrom(configurations.getByName("implementation"))
    getByName("testImplementation").extendsFrom(configurations.getByName("fixturesImplementation"))
}

tasks.register<JavaExec>("runPanelPreview") {
    group = "application"
    description = "Standalone Swing preview of panel states from porcelain fixtures"
    classpath = sourceSets["preview"].runtimeClasspath
    mainClass.set("com.ezevillo.gitreview.preview.PanelPreviewMain")
}

// Expose monorepo root contracts/ path to tests (PanelLayoutContractTest).
tasks.named<Test>("test") {
    systemProperty(
        "git.review.contracts.dir",
        rootProject.projectDir.parentFile.resolve("contracts").absolutePath,
    )
    // When jetbrains-plugin is the Gradle root, parent is the monorepo root.
    val monorepoRoot = projectDir.parentFile
    systemProperty("git.review.monorepo.root", monorepoRoot.absolutePath)
}
