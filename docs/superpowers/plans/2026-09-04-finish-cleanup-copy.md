# Plan de implementación del texto de limpieza al finalizar

> **Para agentes:** SUBHABILIDAD OBLIGATORIA: usa superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea. Los pasos usan la sintaxis de casillas (`- [ ]`) para el seguimiento.

**Objetivo:** Hacer que cada superficie de una revisión finalizada indique claramente que la persona revisora conserva sus ediciones mientras se elimina la opción de deshacer.

**Arquitectura:** El estado de finalización pendiente, la invocación `clean --keep-fixes`, los controles y las transiciones de estado permanecen intactos. Cada cliente cambia únicamente su banner visible, sus controles y su texto de confirmación; las pruebas unitarias locales de cada cliente comprueban ese contrato exacto. La TUI regenera sus marcos dorados deterministas de finalización pendiente.

**Pila tecnológica:** TypeScript/Mocha, C#/.NET/xUnit, Kotlin/JUnit/Gradle, Go/Bubble Tea.

## Restricciones globales

- La línea 2 del banner es exactamente `Commit and push them from Source Control. You can still undo this finish.`
- La acción principal y su botón de aceptación de confirmación son exactamente `Keep edits & remove Undo`.
- La acción secundaria es exactamente `Undo Finish`.
- El título de confirmación principal es exactamente `Keep your edits & remove Undo?`.
- El detalle de confirmación principal es exactamente `Your edits stay on {destination} — commit and push them from Source Control. What goes away is the option to undo this finish.`
- No expongas `review/<source>` ni alteres los argumentos de comandos, las transiciones de estado o el comportamiento del diseño más allá del ajuste natural de líneas.

---

### Tarea 1: VS Code

**Archivos:**
- Modificar: `vscode-extension/src/views/panelHtml.ts:1366-1375`
- Modificar: `vscode-extension/src/review/housekeeping.ts:177-191`
- Prueba: `vscode-extension/test/unit/panelHtml.spec.ts:544-575`
- Prueba: `vscode-extension/test/unit/housekeeping.spec.ts:98-146`

**Interfaces:** Usa `renderEmptyState` y `confirmCopyFor`; conserva `cleanReview`, `undoFinish` y `clean-keep-fixes`.

- [ ] **Paso 1: Escribir pruebas fallidas**

```ts
assert.ok(pendingBranch.includes('"Keep edits & remove Undo", "cleanReview"'));
assert.ok(pendingBranch.includes('"Undo Finish", "undoFinish"'));
assert.ok(pendingBranch.includes("You can still undo this finish."));
assert.strictEqual(c.title, "Keep your edits & remove Undo?");
assert.strictEqual(c.button, "Keep edits & remove Undo");
assert.ok(c.detail.includes("What goes away is the option to undo this finish."));
```

- [ ] **Paso 2: Verificar RED**

Ejecuta: `npm run test:unit -- --grep "finish-pending|clean-keep-fixes"`

Esperado: falla con las etiquetas existentes `Done, clean up`, `Undo` y el texto de confirmación anterior.

- [ ] **Paso 3: Implementar cambios mínimos de texto**

Reemplaza únicamente el banner, las etiquetas de los controles y los literales de confirmación de `clean-keep-fixes` por el contrato global.

- [ ] **Paso 4: Verificar GREEN**

Ejecuta: `npm run test:unit -- --grep "finish-pending|clean-keep-fixes"`

Esperado: todas las pruebas enfocadas pasan.

- [ ] **Paso 5: Hacer commit**

```bash
git add vscode-extension/src/views/panelHtml.ts vscode-extension/src/review/housekeeping.ts vscode-extension/test/unit/panelHtml.spec.ts vscode-extension/test/unit/housekeeping.spec.ts
git commit -m "fix(vscode): clarify finish cleanup"
```

### Tarea 2: Visual Studio

**Archivos:**
- Modificar: `visualstudio-extension/src/GitReview.Domain/PanelLayout.cs:700-714`
- Modificar: `visualstudio-extension/src/GitReview.Domain/Housekeeping.cs:126-130`
- Prueba: `visualstudio-extension/tests/GitReview.Domain.Tests/PanelLayoutFinishTests.cs:8-35`
- Prueba: `visualstudio-extension/tests/GitReview.Domain.Tests/HousekeepingTests.cs:168-183`

**Interfaces:** Usa `PanelLayoutBuilder.PanelLayout` y `HousekeepingLogic.ConfirmCopyFor`; conserva `ControlId.CleanReview`, `ControlId.UndoFinish` y los argumentos `--keep-fixes`.

- [ ] **Paso 1: Escribir pruebas fallidas**

```csharp
Assert.Equal("Keep edits & remove Undo", controls[0].Label);
Assert.Equal("Undo Finish", controls[1].Label);
Assert.Contains("You can still undo this finish.", banner.Paragraphs[1]);
Assert.Equal("Keep your edits & remove Undo?", separate.Title);
Assert.Equal("Keep edits & remove Undo", separate.Button);
```

- [ ] **Paso 2: Verificar RED**

Ejecuta: `dotnet test tests/GitReview.Domain.Tests/GitReview.Domain.Tests.csproj --filter "FullyQualifiedName~PanelLayoutFinishTests|FullyQualifiedName~HousekeepingTests" --no-restore`

Esperado: falla con las etiquetas y el texto anteriores.

- [ ] **Paso 3: Implementar cambios mínimos de texto**

Reemplaza únicamente los literales de texto de finalización pendiente y `CleanKeepFixes` por el contrato global.

- [ ] **Paso 4: Verificar GREEN**

Run: `dotnet test tests/GitReview.Domain.Tests/GitReview.Domain.Tests.csproj --filter "FullyQualifiedName~PanelLayoutFinishTests|FullyQualifiedName~HousekeepingTests" --no-restore`

Esperado: las pruebas seleccionadas pasan.

- [ ] **Paso 5: Hacer commit**

```bash
git add visualstudio-extension/src/GitReview.Domain/PanelLayout.cs visualstudio-extension/src/GitReview.Domain/Housekeeping.cs visualstudio-extension/tests/GitReview.Domain.Tests/PanelLayoutFinishTests.cs visualstudio-extension/tests/GitReview.Domain.Tests/HousekeepingTests.cs
git commit -m "fix(visualstudio): clarify finish cleanup"
```

### Tarea 3: JetBrains

**Archivos:**
- Modificar: `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/PanelLayout.kt:700-716`
- Modificar: `jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/Housekeeping.kt:114-126`
- Prueba: `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutFinishTest.kt:10-33`
- Prueba: `jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/HousekeepingTest.kt:158-174`

**Interfaces:** Usa `panelLayout` y `confirmCopyFor`; conserva `CLEAN_REVIEW`, `UNDO_FINISH` y `CLEAN_KEEP_FIXES`.

- [ ] **Paso 1: Escribir pruebas fallidas**

```kotlin
assertEquals("Keep edits & remove Undo", banner.row.controls[0].label)
assertEquals("Undo Finish", banner.row.controls[1].label)
assertTrue(banner.paragraphs[1].contains("You can still undo this finish."))
assertEquals("Keep your edits & remove Undo?", separate.title)
assertEquals("Keep edits & remove Undo", separate.button)
```

- [ ] **Paso 2: Verificar RED**

Ejecuta: `./gradlew.bat test --tests "com.ezevillo.gitreview.domain.PanelLayoutFinishTest" --tests "com.ezevillo.gitreview.domain.HousekeepingTest"`

Esperado: falla con los textos actuales.

- [ ] **Paso 3: Implementar cambios mínimos de texto**

Cambia únicamente el banner de finalización pendiente y los textos de confirmación de `CLEAN_KEEP_FIXES`.

- [ ] **Paso 4: Verificar GREEN**

Ejecuta: `./gradlew.bat test --tests "com.ezevillo.gitreview.domain.PanelLayoutFinishTest" --tests "com.ezevillo.gitreview.domain.HousekeepingTest"`

Esperado: las pruebas seleccionadas pasan.

- [ ] **Paso 5: Hacer commit**

```bash
git add jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/PanelLayout.kt jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/Housekeeping.kt jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutFinishTest.kt jetbrains-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/HousekeepingTest.kt
git commit -m "fix(jetbrains): clarify finish cleanup"
```

### Tarea 4: TUI

**Archivos:**
- Modificar: `tui/internal/domain/usercopy.go:200-201,306-307,514-516`
- Prueba: `tui/internal/ui/mutation_test.go:232-247`
- Prueba: `tui/internal/ui/render_test.go`
- Modificar: seis archivos `tui/testdata/golden/finish-pending-*.txt`

**Interfaces:** Usa las constantes de texto de finalización pendiente y `beginCleanReview`; conserva `CleanKeepFixes` y el fixture golden determinista.

- [ ] **Paso 1: Escribir pruebas fallidas**

```go
if domain.FinishPendingLine2 != "Commit and push them from Source Control. You can still undo this finish." { t.Fatal("unexpected finish-pending line") }
if domain.DoneCleanUpLabel != "Keep edits & remove Undo" { t.Fatal("unexpected clean label") }
if domain.UndoLabel != "Undo Finish" { t.Fatal("unexpected undo label") }
if domain.CleanReviewConfirmTitle != "Keep your edits & remove Undo?" { t.Fatal("unexpected clean title") }
if domain.DoneLabel != "Keep edits & remove Undo" { t.Fatal("unexpected confirmation label") }
```

- [ ] **Paso 2: Verificar RED**

Ejecuta: `go test ./internal/ui -run "TestFinishPending"`

Esperado: las nuevas aserciones de texto fallan.

- [ ] **Paso 3: Implementar el texto y regenerar los goldens**

Update the five constants, then run:

```bash
go test -tags goldenupdate ./internal/ui -update
```

Confirma que solo cambien los seis archivos golden de finalización pendiente.

- [ ] **Paso 4: Verificar GREEN**

Ejecuta: `go test ./internal/ui`

Esperado: pasan los 68 marcos golden y las pruebas unitarias de la TUI.

- [ ] **Paso 5: Hacer commit**

```bash
git add tui/internal/domain/usercopy.go tui/internal/ui/mutation_test.go tui/internal/ui/render_test.go tui/testdata/golden/finish-pending-80x24.txt tui/testdata/golden/finish-pending-80x24-nocolor.txt tui/testdata/golden/finish-pending-80x24-ascii.txt tui/testdata/golden/finish-pending-120x40.txt tui/testdata/golden/finish-pending-120x40-nocolor.txt tui/testdata/golden/finish-pending-120x40-ascii.txt
git commit -m "fix(tui): clarify finish cleanup"
```

### Tarea 5: Verificación entre clientes

**Archivos:**
- Verificar: archivos de las tareas 1-4.

**Interfaces:** Consume el contrato de texto aprobado y la suite de pruebas de cada cliente; demuestran que el comportamiento permanece sin cambios.

- [ ] **Paso 1: Comprobar que el texto nuevo no tenga detalles técnicos de ramas**

Run: `rg -n "temporary review branch|temporary undo branch" vscode-extension/src/views/panelHtml.ts vscode-extension/src/review/housekeeping.ts visualstudio-extension/src/GitReview.Domain/PanelLayout.cs visualstudio-extension/src/GitReview.Domain/Housekeeping.cs jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/PanelLayout.kt jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/Housekeeping.kt tui/internal/domain/usercopy.go`

Esperado: ninguna coincidencia.

- [ ] **Paso 2: Ejecutar las suites de cliente específicas**

Ejecuta los comandos en verde de las tareas 1-4.

Esperado: cada comando termina con código 0.

- [ ] **Paso 3: Inspeccionar el worktree**

Run: `git diff --check && git status --short`

Esperado: ningún error de espacios en blanco; solo quedan cambios intencionales y confirmados.
