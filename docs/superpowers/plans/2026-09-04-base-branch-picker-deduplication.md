# Base Branch Picker Deduplication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mostrar una sola opción por nombre de rama en Set/Change the base branch en JetBrains, VS Code y Visual Studio.

**Architecture:** Reutilizar en cada acción de configuración el normalizador puro `branchPickerItems` que ya consume el asistente de inicio. Mantener intactas las candidatas porcelain crudas para que el paso de origen siga distinguiendo local de remoto.

**Tech Stack:** Kotlin/JUnit 5/Gradle, TypeScript/Mocha/VS Code integration host, C#/xUnit/.NET 8.

## Global Constraints

- Trabajar directamente sobre `main`, sin worktree ni rama auxiliar.
- No cambiar `git review config --porcelain` ni la semántica de `CandidateBranch`.
- No modificar la TUI: ya usa `BranchPickerItems` en `beginSetBase`.
- Seguir TDD y verificar el rojo antes de cada cambio de producción.

---

### Task 1: JetBrains base picker

**Files:**
- Modify: `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/ui/actions/ReviewActions.kt`
- Test: `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/ConfigPorcelainTest.kt`

**Interfaces:**
- Consumes: `branchPickerItems(List<CandidateBranch>): List<CandidateBranch>`.
- Produces: la lista normalizada que `SetBaseAction` etiqueta y entrega a `UiMessages.choose`.

- [ ] **Step 1: Write the failing regression test**

Agregar una prueba de la preparación del selector de base con `main` local+remote y una rama sólo
local; esperar exactamente dos nombres, con la copia actual de `main` conservada.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `cd jetbrains-plugin; .\gradlew.bat test --tests com.ezevillo.gitreview.domain.ConfigPorcelainTest`

Expected: FAIL porque el camino de SetBase todavía entrega ambas filas porcelain.

- [ ] **Step 3: Use the shared normalizer in SetBaseAction**

Importar y aplicar `branchPickerItems(list)` antes de crear labels e indexar la selección.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `cd jetbrains-plugin; .\gradlew.bat test --tests com.ezevillo.gitreview.domain.ConfigPorcelainTest`

Expected: PASS.

### Task 2: VS Code base picker

**Files:**
- Modify: `vscode-extension/src/commands/setBase.ts`
- Test: `vscode-extension/test/integration/start-review.spec.ts`

**Interfaces:**
- Consumes: `branchPickerItems(readonly CandidateBranch[]): CandidateBranch[]`.
- Produces: QuickPick de base deduplicado, conservando el `CandidateBranch` elegido para formar argv.

- [ ] **Step 1: Write the failing integration test**

Crear una rama disponible localmente y en `origin`, interceptar el QuickPick de
`gitReview.setBase` y afirmar que su nombre aparece una sola vez.

- [ ] **Step 2: Run the focused integration test and verify RED**

Run: `vscode-extension/test/run-docker.sh start-review`

Expected: FAIL con dos items del mismo nombre en el picker de base.

- [ ] **Step 3: Normalize candidates in setBase**

Importar `branchPickerItems` y aplicarlo antes del sort y map actuales.

- [ ] **Step 4: Run the focused integration test and verify GREEN**

Run: `vscode-extension/test/run-docker.sh start-review`

Expected: PASS.

### Task 3: Visual Studio base picker

**Files:**
- Modify: `visualstudio-extension/src/GitReview.VS/ToolWindows/ActionDispatcher.cs`
- Test: `visualstudio-extension/tests/GitReview.Domain.Tests/ConfigPorcelainTests.cs`

**Interfaces:**
- Consumes: `ConfigPorcelain.BranchPickerItems(IReadOnlyList<CandidateBranch>)`.
- Produces: opciones deduplicadas para `GitReviewDialogs.Choose` y el nombre correcto para `setBase`.

- [ ] **Step 1: Write the failing regression test**

Cubrir explícitamente la preparación del selector de base con una rama local+remote y afirmar una
sola opción con la copia actual conservada.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `dotnet test visualstudio-extension/tests/GitReview.Domain.Tests --filter Branch_picker`

Expected: FAIL porque SetConfig todavía ordena `parsed.Candidates` sin colapsarlas.

- [ ] **Step 3: Use BranchPickerItems in SetConfigAsync**

Reemplazar el sort manual por `ConfigPorcelain.BranchPickerItems(parsed.Candidates)`.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `dotnet test visualstudio-extension/tests/GitReview.Domain.Tests --filter Branch_picker`

Expected: PASS.

### Task 4: Cross-client verification

**Files:**
- No additional files.

**Interfaces:**
- Consumes: los tres cambios anteriores.
- Produces: evidencia fresca de que el bug está cubierto sin romper otros flujos.

- [ ] **Step 1: Run JetBrains verification**

Run: `cd jetbrains-plugin; .\gradlew.bat test`

- [ ] **Step 2: Run VS Code verification**

Run: `cd vscode-extension; npm run test:unit`

Run: `vscode-extension/test/run-docker.sh start-review`

- [ ] **Step 3: Run Visual Studio verification**

Run: `dotnet test visualstudio-extension/GitReview.sln`

Run: `dotnet build visualstudio-extension/GitReview.sln`

- [ ] **Step 4: Inspect the final diff and repository state**

Run: `git diff --check`

Run: `git status --short`

