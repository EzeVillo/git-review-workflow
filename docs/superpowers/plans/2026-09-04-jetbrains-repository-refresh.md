# JetBrains Repository Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hacer que el widget nativo de rama de IntelliJ refleje inmediatamente cualquier cambio de `HEAD` producido por una mutación de git review.

**Architecture:** La capa `vcs` conserva la única interacción con `GitRepositoryManager` y expone un refresh del repositorio único. Los dos runners centrales de mutaciones llaman esa puerta después de que la CLI termina y antes de refrescar el estado porcelain del panel, sin condicionar la llamada al exit code.

**Tech Stack:** Kotlin 2.3.20, IntelliJ Platform 2026.1 / Git4Idea, JUnit 5, Gradle.

## Global Constraints

- Trabajar directamente sobre `main`, según lo pedido.
- Mantener `com.ezevillo.gitreview.domain` libre de imports `com.intellij`.
- Ejecutar `GitRepository.update()` fuera del EDT; los runners actuales ya corren en `Bg.async`.
- No agregar polling ni refresh recursivo de VFS.
- Notificar después de cualquier mutación completada, incluso con exit code no cero.

---

### Task 1: Sincronizar el modelo Git de IntelliJ

**Files:**
- Modify: `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/vcs/RepositoryTargets.kt`
- Modify: `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/host/MutationActions.kt`
- Create: `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/host/RepositoryRefreshTest.kt`

**Interfaces:**
- Consumes: `pickSoleGitRoot(project: Project): RepositoryTarget?` y `GitRepository.update(): Unit`.
- Produces: `refreshIdeRepository(project: Project): Unit`, llamada por `runStart` y `runSimple`.

- [x] **Step 1: Escribir el test estructural que falla**

```kotlin
package com.ezevillo.gitreview.host

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

class RepositoryRefreshTest {
    @Test
    fun `the repository helper updates the sole Git repository`() {
        val source = source("vcs/RepositoryTargets.kt")
        assertTrue(source.contains("pickSoleGitRoot(project)?.repository?.update()"))
    }

    @Test
    fun `every completed mutation refreshes IntelliJ before the panel state`() {
        val source = source("host/MutationActions.kt")
        val invocations = source.split("service.cliInvoker.invoke(").drop(1)
        assertEquals(2, invocations.size, "new mutation invocation sites must join the same refresh path")
        invocations.forEach { afterInvocation ->
            val ideRefresh = afterInvocation.indexOf("refreshIdeRepository(project)")
            val panelRefresh = afterInvocation.indexOf("service.refreshNow()")
            assertTrue(ideRefresh >= 0, "a completed mutation did not refresh GitRepository")
            assertTrue(panelRefresh >= 0 && ideRefresh < panelRefresh, "refresh GitRepository before porcelain")
        }
    }

    private fun source(relative: String): String {
        val root = System.getProperty("git.review.monorepo.root")
        assertNotNull(root, "git.review.monorepo.root is not set — see build.gradle.kts")
        val file = File(root, "jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/$relative")
        assertTrue(file.isFile, "source missing at ${file.absolutePath}")
        return file.readText()
    }
}
```

- [x] **Step 2: Ejecutar el test y verificar RED**

Run: `cd jetbrains-plugin; .\gradlew.bat test --tests com.ezevillo.gitreview.host.RepositoryRefreshTest`

Expected: FAIL porque todavía no existe la llamada a `repository.update()` ni `refreshIdeRepository(project)`.

- [x] **Step 3: Implementar la puerta mínima de refresh**

Agregar a `RepositoryTargets.kt`:

```kotlin
fun refreshIdeRepository(project: Project) {
    pickSoleGitRoot(project)?.repository?.update()
}
```

Importar esa función en `MutationActions.kt` y llamarla inmediatamente después de las dos invocaciones de `service.cliInvoker.invoke(...)`, antes del `service.refreshNow()` posterior.

- [x] **Step 4: Ejecutar el test focal y verificar GREEN**

Run: `cd jetbrains-plugin; .\gradlew.bat test --tests com.ezevillo.gitreview.host.RepositoryRefreshTest`

Expected: PASS.

- [x] **Step 5: Ejecutar la regresión del plugin y el contrato del monorepo**

Run: `cd jetbrains-plugin; .\gradlew.bat test`

Expected: BUILD SUCCESSFUL, sin tests fallidos.

Run desde la raíz: `node scripts/check-client-product-surface.mjs`

Expected: verificación exitosa sin drift entre clientes.

- [x] **Step 6: Commit de implementación**

```powershell
git add -- jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/vcs/RepositoryTargets.kt jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/host/MutationActions.kt jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/host/RepositoryRefreshTest.kt docs/superpowers/plans/2026-09-04-jetbrains-repository-refresh.md
git commit -m "fix(jetbrains): refresh branch after mutations"
```
