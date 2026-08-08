import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("java")
    // IDEA 2026.1 bundles stdlib 2.3.20 — compiler must match metadata.
    id("org.jetbrains.kotlin.jvm") version "2.3.20"
    id("org.jetbrains.intellij.platform") version "2.18.1"
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
        // Platform test framework is for platformTest (T030a), not domain unit tests.
        // testFramework(TestFrameworkType.Platform)
    }

    // Pure JUnit 5 for domain (no IDE host).
    testImplementation("org.junit.jupiter:junit-jupiter:5.11.4")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

kotlin {
    jvmToolchain(21)
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_21)
    }
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(21))
    }
}

intellijPlatform {
    // instrumentCode needs a full JDK layout; some Windows JDKs (e.g. Microsoft)
    // omit Packages/ and break :instrumentCode. Domain tests do not need it.
    instrumentCode = false

    pluginConfiguration {
        name = providers.gradleProperty("pluginName")
        version = providers.gradleProperty("pluginVersion")
        description.set(
            "Review a git-review-workflow pull request as a native IntelliJ IDEA tool window.",
        )

        ideaVersion {
            sinceBuild = providers.gradleProperty("pluginSinceBuild")
            val until = providers.gradleProperty("pluginUntilBuild").orNull
            if (!until.isNullOrBlank()) {
                untilBuild = until
            }
        }
    }

    pluginVerification {
        ides {
            recommended()
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

// Standalone panel preview (T029) — main lives under preview/ source set if present.
sourceSets {
    create("preview") {
        kotlin.srcDir("preview")
        compileClasspath += sourceSets["main"].output + configurations["compileClasspath"]
        runtimeClasspath += output + compileClasspath
    }
}

tasks.register<JavaExec>("runPanelPreview") {
    group = "application"
    description = "Standalone Swing preview of panel states from porcelain fixtures"
    classpath = sourceSets["preview"].runtimeClasspath
    mainClass.set("com.ezevillo.gitreview.preview.PanelPreviewMain")
}
