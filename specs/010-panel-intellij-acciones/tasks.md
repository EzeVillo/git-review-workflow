---

description: "Task list template for feature implementation"
---

# Tasks: Panel del plugin de IntelliJ con la superficie de acciones del panel de VS Code

**Input**: Design documents from `/specs/010-panel-intellij-acciones/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: se incluyen tareas de test. No es TDD ceremonial: el invariante rector
de la spec sólo es afirmable con tests estructurales (FR-036, SC-001), y el
repositorio exige asserts fuertes sin falsos positivos (`CLAUDE.md`).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Monorepo multi-cliente. Rutas relativas a la raíz del repositorio:

- Plugin: `intellij-plugin/src/main/kotlin/com/ezevillo/gitreview/`
- Tests del plugin: `intellij-plugin/src/test/kotlin/com/ezevillo/gitreview/`
- Fixtures compartidas: `intellij-plugin/fixtures/com/ezevillo/gitreview/fixtures/`
- Preview: `intellij-plugin/preview/com/ezevillo/gitreview/preview/`
- Canónico multi-cliente: `contracts/` y `scripts/`

**Comandos**: `cd intellij-plugin && ./gradlew test` (Git Bash) o
`.\gradlew.bat test` (PowerShell) — no mezclar.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: dejar escrito el canónico y el andamiaje de fixtures antes de tocar
código de panel. Nada de esto depende del plugin.

- [ ] T001 Escribir los bloques `panel_layout:`, `title_actions:` y `panel_excluded:` en `contracts/client-product-surface.yaml`, transcribiendo situación por situación la tabla de `specs/010-panel-intellij-acciones/contracts/panel-layout.md` (9 situaciones + las 3 variantes de modo de `review`, 22 controles de cuerpo, 5 de barra de título, 4 excluidos)
- [ ] T002 [P] Extender `scripts/check-client-product-surface.mjs` con las cuatro verificaciones del lado VS Code descritas en `contracts/panel-layout.md` § Verificación: cada `label` del canónico existe literalmente en `vscode-extension/src/views/panelHtml.ts`; cada `id` de cuerpo está en `PANEL_MESSAGES` de `vscode-extension/src/views/walkthroughViewProvider.ts`; ningún literal de botón de `panelHtml.ts` queda fuera del canónico; ningún id de `panel_excluded` aparece en `PANEL_MESSAGES`
- [ ] T003 [P] Crear el source set `fixtures` en `intellij-plugin/build.gradle.kts` (compilado contra `main`, agregado al classpath de `test` y de `preview`) para que los modelos de ejemplo no se dupliquen entre tests y preview

**Checkpoint**: `node scripts/check-client-product-surface.mjs` pasa contra el canónico ampliado y el panel actual de la extensión.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: los tipos del layout, el renderer y el cableado del panel. Ninguna
historia puede empezar sin esto.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T004 Crear `intellij-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/PanelLayout.kt` con los tipos de `data-model.md`: `PanelLayout`, la suma cerrada `Block` (las 16 variantes), `Control`, `ControlId` (22 de cuerpo + 5 de barra), `Emphasis`, `FileRow`, `InventoryRow` — sin la función de proyección todavía y sin importar `com.intellij`
- [ ] T005 Agregar a `PanelLayout.kt` los cinco invariantes de construcción de `data-model.md` § Control (ícono ⟹ nombre accesible; fila de 1 o 2 controles; un solo `PRIMARY` por situación; `index` sólo en filas; ningún id ajeno a la situación) como validación en los constructores
- [ ] T006 Agregar a `PanelLayout.kt` el esqueleto de `panelLayout(model: PanelModel): PanelLayout` y de `titleBarActions(model: PanelModel): List<Control>`: despacho por `Situation` con las ramas vacías que cada historia irá completando
- [ ] T007 [P] Crear `intellij-plugin/src/main/kotlin/com/ezevillo/gitreview/ui/PanelChrome.kt`: interfaz de colores, iconos y fuentes, con la implementación del plugin (`JBColor` / `JBUI` / `AllIcons`) y la del preview (`UIManager` y glifos), según research §3
- [ ] T008 Crear `intellij-plugin/src/main/kotlin/com/ezevillo/gitreview/ui/PanelRenderer.kt`: renderer genérico de `PanelLayout` a Swing que recibe un `PanelChrome` y un callback `(ControlId, Int?) -> Unit`, sin conocer `Project` ni `GitReviewService`. Texto con ancho variable contra el viewport y `JBScrollPane` que sigue el ancho del viewport (nunca scroll horizontal); filas de dos controles al 50% que se apilan conservando el orden cuando no entran (research §4)
- [ ] T009 Crear `intellij-plugin/src/main/kotlin/com/ezevillo/gitreview/ui/PanelActionDispatcher.kt` con el mapeo de `data-model.md` § Mapeo: cada `ControlId` (más el índice cuando corresponde) a las acciones existentes de `ui/actions/ReviewActions.kt` y `host/MutationActions.kt`
- [ ] T010 Reescribir `intellij-plugin/src/main/kotlin/com/ezevillo/gitreview/ui/ReviewPanel.kt` para suscribir el servicio, pedir `panelLayout(model)` y delegar en `PanelRenderer` + `PanelActionDispatcher`: se elimina todo `when (situation)`, los `renderX` propios y **el botón `Refresh` del cuerpo** (hoy en `ReviewPanel.kt:77`, lugar donde la extensión no lo tiene)
- [ ] T011 [P] Crear `intellij-plugin/fixtures/com/ezevillo/gitreview/fixtures/PanelFixtures.kt` con un `PanelModel` por situación y por modo de review, derivados de porcelain de ejemplo con `parsePorcelain` (mismo criterio que el preview actual: salida real de la CLI pasada por el parser real)

**Checkpoint**: el panel compila, se dibuja vacío o parcial en `runIde`, y `./gradlew check` pasa incluyendo `checkDomainNoIntellij`.

---

## Phase 3: User Story 1 - Reconocer el panel viniendo de VS Code (Priority: P1) 🎯 MVP

**Goal**: que la paridad sea una propiedad verificada por el build y no una
impresión visual, y que exista la herramienta para compararla a ojo cuando haga
falta.

**Independent Test**: cambiar a propósito un rótulo, el orden de una fila o el
énfasis de un control en `PanelLayout.kt` y comprobar que `./gradlew test` se
pone en rojo señalando la situación y el control; revertir y ver verde. Se puede
ejercitar con una sola situación implementada.

### Tests for User Story 1

- [ ] T012 [P] [US1] Crear `intellij-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutContractTest.kt`: lee `contracts/client-product-surface.yaml` (ruta relativa al `projectDir`), y para cada situación registrada compara `panelLayout(fixture)` contra el canónico en identidad, rótulo, orden, agrupación en filas, énfasis y habilitación; falla nombrando situación y control
- [ ] T013 [P] [US1] Crear `intellij-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutInvariantsTest.kt`: los cinco invariantes de T005 se violan y el constructor falla; y ningún `ControlId` de `panel_excluded` es construible en ninguna situación
- [ ] T014 [P] [US1] Crear `intellij-plugin/src/test/kotlin/com/ezevillo/gitreview/ui/PanelRendererTest.kt`: el renderer produce exactamente los controles del layout, en el mismo orden de recorrido, con el mismo estado de habilitación, y con nombre accesible en los de ícono (Swing sin ventana; JPanel/JButton se instancian en headless)

### Implementation for User Story 1

- [ ] T015 [US1] Reescribir `intellij-plugin/preview/com/ezevillo/gitreview/preview/PanelPreviewMain.kt` para renderizar con `PanelRenderer` y `PanelChrome` de preview sobre las fixtures de T011, con selector de situación y de ancho (ancho de sidebar / ancho suelto), en lugar del volcado de texto actual
- [ ] T016 [US1] Verificar en `intellij-plugin/src/main/resources/META-INF/plugin.xml` que el `toolWindow` conserva `anchor="right"` y documentar en el comentario contiguo que es la excepción explícita al invariante (spec § Invariante rector)

**Checkpoint**: el build afirma la paridad de lo que ya esté implementado, y `./gradlew runPanelPreview` muestra el panel real al lado del `npm run preview` de la extensión.

---

## Phase 4: User Story 2 - Leer y avanzar sin salir del panel (Priority: P1)

**Goal**: el ciclo de lectura completo dentro del tool window: entrada, *why*,
abrir archivo y diff, avanzar y retroceder.

**Independent Test**: con `./tests/sandbox.sh` y `git review start
feature/checkout`, recorrer la review de principio a fin en `runIde` sin abrir
`Tools → git review` ni una terminal.

### Tests for User Story 2

- [ ] T017 [P] [US2] Crear `intellij-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutReviewTest.kt`: para walk y para step, el layout produce la secuencia de `contracts/panel-layout.md` (barra, notas, cabecera, título, *why* sólo en walk, fila de apertura con 2 o 1 control, fila de navegación), con los rótulos `File`, `Diff`, `open in editor` y los nombres accesibles `Previous entry` / `Next entry`
- [ ] T018 [P] [US2] En el mismo archivo, cubrir los extremos y las marcas: en la primera entrada `prev` va deshabilitado y presente, en la última `next`; con acción en curso todos los controles que mutan van deshabilitados; la cabecera lleva **una** marca (`key`, o `uncovered`, o `edits`) según la precedencia de la extensión; sin *why* presente no existe el control `open in editor`

### Implementation for User Story 2

- [ ] T019 [US2] Implementar en `domain/PanelLayout.kt` la rama común de review: `IdentityBar` (modo, origen o rama, tip a 7, posición/total) y las `Note` en el orden de la extensión (solo lectura, solo claves, base movida, degradado, base del rango)
- [ ] T020 [US2] Implementar en `domain/PanelLayout.kt` la rama walk: `EntryHead` con número y marca, `EntryTitle` con el path, `Why` en sus cuatro estados con el texto propio de cada uno, `Row[open in editor]` sólo con *why* presente, `Row[File | Diff]` y `Row[◀ | ▶]`
- [ ] T021 [US2] Implementar en `domain/PanelLayout.kt` la rama step: cabecera con sha y autor, título con el asunto (y `This commit has no subject.` cuando está vacío), sin bloque `Why`, `Row[Diff]` y `Row[◀ | ▶]`
- [ ] T022 [US2] Implementar en `domain/PanelLayout.kt` el `EmptyMessage` de cursor sin entrada (`The cursor does not point at any entry in the sequence.`)
- [ ] T023 [US2] Cablear en `ui/PanelActionDispatcher.kt` los controles de esta historia (`openEntry`, `openChange`, `showWhy`, `next`, `prev`) a `OpenEntryActions` y `MutationActions.runNextPrev`
- [ ] T024 [US2] Registrar las situaciones de review en `contracts/client-product-surface.yaml` si T001 las dejó pendientes, y hacer pasar `PanelLayoutContractTest`

**Checkpoint**: US1 + US2 son el MVP: se lee y se navega una review entera desde el panel, y el build afirma que la disposición coincide con la de la extensión.

---

## Phase 5: User Story 3 - Cerrar, pausar o abandonar la review (Priority: P1)

**Goal**: el ciclo de vida en la barra del tool window, y los dos estados de
finish resueltos desde el propio aviso.

**Independent Test**: cerrar una review desde la barra del tool window; provocar
un finish trabado y resolverlo desde el banner, comprobando que la fila de
navegación no está.

### Tests for User Story 3

- [ ] T025 [P] [US3] Crear `intellij-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/TitleBarActionsTest.kt`: `titleBarActions` devuelve `Refresh`, `Finish`, `Save`, `Cancel`, `Preview edits` en ese orden y con las condiciones de `contributes.menus.view/title` (Finish ausente en solo lectura; todas menos Refresh ausentes fuera de review / finish-conflict; ninguna con acción en curso)
- [ ] T026 [P] [US3] Crear `intellij-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutFinishTest.kt`: en `finish-pending` el banner trae `Row[Clean (PRIMARY) | Undo finish]` con el texto del destino; en `finish-conflict` el banner va **antes** de las notas con `Row[Undo | Continue]` y el layout **no contiene** ningún control `next`/`prev`

### Implementation for User Story 3

- [ ] T027 [US3] Implementar en `domain/PanelLayout.kt` la situación `finish-pending`: los dos párrafos del aviso con el destino resuelto y su fila de controles
- [ ] T028 [US3] Implementar en `domain/PanelLayout.kt` la situación `finish-conflict`: banner con su fila entre la barra y las notas, y retiro completo de la fila de navegación
- [ ] T029 [US3] Implementar `titleBarActions` en `domain/PanelLayout.kt` con las cinco acciones y sus condiciones
- [ ] T030 [US3] Registrar el grupo de acciones del tool window en `intellij-plugin/src/main/resources/META-INF/plugin.xml` y engancharlo en `ui/GitReviewToolWindowFactory.kt` mediante `setTitleActions`, en el orden de `titleBarActions`
- [ ] T031 [US3] Agregar `update()` a `FinishReviewAction`, `SaveReviewAction`, `AbortReviewAction`, `PreviewEditsAction` y `RefreshAction` en `ui/actions/ReviewActions.kt` y `ui/actions/RefreshAction.kt` para que reflejen la disponibilidad del modelo (hoy están siempre habilitadas en el menú)
- [ ] T032 [US3] Cablear en `ui/PanelActionDispatcher.kt` `undoFinish`, `resumeFinish` y `cleanReview`, resolviendo el source del finish pendiente desde el modelo (sin selector de tipo de limpieza, como la extensión)

**Checkpoint**: el ciclo de review se abre y se cierra entero desde el panel y su barra.

---

## Phase 6: User Story 4 - Arrancar desde el estado vacío (Priority: P1)

**Goal**: el punto de entrada: configurar la base, arrancar, y continuar o
descartar desde la fila del inventario.

**Independent Test**: con `reviewworkflow.base` sin configurar, llegar a una
review activa usando solamente el panel; guardar una review y continuarla desde
su fila, sin selector de por medio.

### Tests for User Story 4

- [ ] T033 [P] [US4] Crear `intellij-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutEmptyStateTest.kt`: sin base, el layout es exactamente los cinco bloques del setup con `Set the base branch` como único `PRIMARY` y **sin** inventario, sin `Start a review` y sin pie; con base, el inventario va antes del bloque de arrancar y `fillsHeight` es `true`
- [ ] T034 [P] [US4] En el mismo archivo, cubrir las filas del inventario: `Continue` sólo en guardadas y deshabilitado con su tooltip cuando no es reanudable; `Discard` / `Discard orphan` según corresponda; fila sin ningún control ⟹ tooltip de ayuda presente; cada control lleva su `index`

### Implementation for User Story 4

- [ ] T035 [US4] Implementar en `domain/PanelLayout.kt` la variante de setup (sin base) con sus cinco bloques y los textos de `contracts/panel-layout.md`
- [ ] T036 [US4] Implementar en `domain/PanelLayout.kt` la variante `no-review` con base: `Heading`, `InventoryRows` (nombre, badges, meta, controles, tooltip de ayuda), párrafo y `Row[Start a review]`
- [ ] T037 [US4] Cablear en `ui/PanelActionDispatcher.kt` `startReview`, `setBase`, `setRemote`, y `continueReview` / `discardInventory` **por índice**, resolviendo la review desde el modelo
- [ ] T038 [US4] Corregir `DiscardInventoryAction` en `ui/actions/ReviewActions.kt` para aceptar la review ya resuelta cuando la invoca el panel, conservando el diálogo de entrada sólo para la invocación desde el menú (research §7)
- [ ] T039 [US4] Eliminar de `ui/ReviewPanel.kt` los textos que derivan al menú (`Start a review from the git review actions.` y `Use the "Set the Base Branch" action (Settings → git review).`), que quedan sin sentido al existir los controles (FR-010)

**Checkpoint**: las cuatro historias P1 están completas; una sesión entera se hace desde el panel.

---

## Phase 7: User Story 5 - Recorrer la lista de archivos en modo whole (Priority: P2)

**Goal**: el listado completo de archivos, cada uno a un clic de su diff.

**Independent Test**: en una review whole de más de 50 archivos, abrir con un
clic el diff de un archivo del final de la lista.

### Tests for User Story 5

- [ ] T040 [P] [US5] Crear `intellij-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutWholeTest.kt`: con 300 archivos el layout contiene 300 `FileRow` (ningún truncado), el `Heading` usa singular o plural según corresponda, el `Row[Diff]` de "todos" va antes de las filas con su tooltip, la fila del último abierto está marcada, y un rango vacío produce el `EmptyMessage` en lugar de la lista

### Implementation for User Story 5

- [ ] T041 [US5] Implementar en `domain/PanelLayout.kt` la rama whole: `Heading` con la cuenta, `Row[Diff]` de todos los cambios y `FileRows` con `index` y marca de último abierto
- [ ] T042 [US5] Implementar en `domain/PanelLayout.kt` el `EmptyMessage` de rango sin archivos (`This review's range does not touch any files.`)
- [ ] T043 [US5] Cablear en `ui/PanelActionDispatcher.kt` `openAllChanges` y `openChange` por índice contra `OpenEntryActions`
- [ ] T044 [US5] Verificar en `ui/PanelRenderer.kt` que `FileRows` se dibuja como controles de una línea activables con **un** clic (no lista con doble clic) y que la lista larga scrollea sin scroll horizontal

**Checkpoint**: whole deja de ser texto inerte y se recorre entero.

---

## Phase 8: User Story 6 - Salir del paso en falso (Priority: P2)

**Goal**: las pantallas de diagnóstico ofrecen el camino de salida como control.

**Independent Test**: con la setting apuntando a un binario inexistente, copiar
el comando de instalación desde el panel y ver la confirmación transitoria.

### Tests for User Story 6

- [ ] T045 [P] [US6] Crear `intellij-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutDiagnosticsTest.kt`: `cli-missing` y `cli-outdated` producen los seis bloques de `contracts/panel-layout.md` con el comando correcto (`npm_install` vs `npm_update`) y `Other install options` como `LINK`; `out-of-range` y `error` producen párrafo, `Row[How to fix it]` (`PRIMARY`) y `Stderr` cuando hay

### Implementation for User Story 6

- [ ] T046 [US6] Implementar en `domain/PanelLayout.kt` las situaciones `cli-missing` y `cli-outdated` reusando las constantes de `domain/InstallHint.kt` y `domain/Version.kt`
- [ ] T047 [US6] Implementar en `domain/PanelLayout.kt` las situaciones `out-of-range` y `error` con el bloque de `stderr`
- [ ] T048 [US6] Implementar en `ui/PanelActionDispatcher.kt` el control `copyCliInstall`: copia al portapapeles y devuelve la señal de confirmación
- [ ] T049 [US6] Implementar en `ui/PanelRenderer.kt` la confirmación transitoria del control de copiar (rótulo `Copied` durante 1500 ms y vuelta a `Copy`), y en el dispatcher el control `outOfRangeHelp`, que reexpone el `stderr` del modelo sin invocar la CLI

**Checkpoint**: ninguna pantalla de diagnóstico deja al revisor sin salida accionable.

---

## Phase 9: User Story 7 - Herramientas y configuración al pie (Priority: P3)

**Goal**: las tres secciones plegables del pie, con el mismo contenido y orden.

**Independent Test**: desde el estado vacío, cambiar la base y lanzar un compare
sin abrir el menú; desplegar una sección, provocar un refresh y comprobar que
sigue desplegada.

### Tests for User Story 7

- [ ] T050 [P] [US7] Crear `intellij-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutFooterTest.kt`: en `no-review` con base el layout termina con tres `ToolsSection` tituladas `Other actions`, `Settings` y `Support`, en ese orden, con sus controles y con los valores vigentes de base y remoto; en el resto de las situaciones no hay ninguna `ToolsSection`
- [ ] T051 [P] [US7] Agregar a `PanelRendererTest.kt` que el estado de apertura de una sección sobrevive a un redibujado con un modelo nuevo (regresión del bug documentado en `panelHtml.ts:721`)

### Implementation for User Story 7

- [ ] T052 [US7] Implementar en `domain/PanelLayout.kt` las tres `ToolsSection` con sus bloques
- [ ] T053 [US7] Implementar en `ui/PanelRenderer.kt` la sección plegable nativa, plegada por defecto, con el estado de apertura guardado en el componente y no en el modelo (FR-034, research §6)
- [ ] T054 [US7] Cablear en `ui/PanelActionDispatcher.kt` `compareReview`, `walkthroughInit`, `walkthroughBuild` y `openSupport` (este último abre `support.star_url` del canónico, sin pasar por la CLI)

**Checkpoint**: el pie está completo y no se pliega solo.

---

## Phase 10: User Story 8 - El panel avisa que está trabajando (Priority: P3)

**Goal**: la carga no deja accionar sobre datos viejos ni hace saltar el panel.

**Independent Test**: navegar con una CLI lenta y comprobar que no se puede
accionar sobre la entrada anterior, y que una respuesta inmediata no produce
parpadeo.

### Tests for User Story 8

- [ ] T055 [P] [US8] Crear `intellij-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutSkeletonTest.kt`: el layout de carga conserva la silueta (barra con posición en bloque, notas normales, cabecera y título en bloque, *why* en bloque sólo en walk, las dos filas de controles) y **todos** sus controles vienen deshabilitados

### Implementation for User Story 8

- [ ] T056 [US8] Implementar en `domain/PanelLayout.kt` la variante de esqueleto (parámetro de carga que devuelve el layout con bloques `Skeleton` y controles deshabilitados)
- [ ] T057 [US8] Implementar en `ui/ReviewPanel.kt` la lógica de presentación de las dos fases con los umbrales de la extensión (120 ms antes del esqueleto, 800 ms de techo para el *why*), con los temporizadores en el componente y no en el servicio (research §8)
- [ ] T058 [US8] Implementar en `ui/ReviewPanel.kt` la guarda de obsolescencia: lo dibujado durante la carga no acciona nada aunque el usuario haga clic (equivalente del `stale()` de la extensión)

**Checkpoint**: todas las historias implementadas.

---

## Phase 11: Polish & Cross-Cutting Concerns

**Purpose**: cierre transversal y verificación completa.

- [ ] T059 [P] Recorrer el panel entero con Tab en `runIde` y corregir en `ui/PanelRenderer.kt` el orden de foco, la visibilidad del foco y los nombres accesibles de los controles de ícono (SC-010, FR-035)
- [ ] T060 [P] Verificar el panel en tema claro, oscuro y alto contraste y con escalado de fuente al 200%, corrigiendo en `ui/PanelChrome.kt` cualquier color o métrica fija (SC-009)
- [ ] T061 [P] Actualizar `intellij-plugin/README.md` con la superficie del panel: qué ofrece cada situación y qué vive en el menú
- [ ] T062 [P] Actualizar la sección *The IntelliJ IDEA plugin* de `CONTRIBUTING.md` con la comparación lado a lado (`runPanelPreview` contra `npm run preview`) como forma de validar la paridad
- [ ] T063 [P] Actualizar la sección de clientes del monorepo en `CLAUDE.md` para nombrar el canónico de disposición del panel y qué lo verifica de cada lado
- [ ] T064 Correr la guía completa de `specs/010-panel-intellij-acciones/quickstart.md` sobre el sandbox, incluidos los cinco recorridos manuales y la regresión del menú (las 27 acciones siguen ahí)
- [ ] T065 Correr la verificación completa: `cd intellij-plugin && ./gradlew check` y `node scripts/check-client-product-surface.mjs`, y confirmar que el CI del plugin cubre los tres sistemas operativos

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: sin dependencias — puede empezar ya
- **Foundational (Phase 2)**: depende de T001 (el canónico define qué tipos hacen falta) — **BLOQUEA todas las historias**
- **User Stories (Phase 3+)**: todas dependen de Foundational
- **Polish (Phase 11)**: depende de las historias que se quieran entregar

### User Story Dependencies

- **US1 (P1)** — entrega la maquinaria de verificación. Es la única historia con una dependencia declarada: su comparación lado a lado necesita **al menos una situación implementada** para ser interesante. Se valida rompiendo a propósito un rótulo, cosa que ya se puede hacer con el layout parcial de Foundational, y se re-valida con cada historia posterior sin trabajo adicional.
- **US2, US3, US4 (P1)**, **US5, US6 (P2)**, **US7, US8 (P3)**: independientes entre sí. Cada una toca su propia rama de `panelLayout()` y su propio archivo de test.

### Conflicto de archivo a tener en cuenta

Todas las historias escriben en `domain/PanelLayout.kt` y en
`ui/PanelActionDispatcher.kt`. Las tareas de implementación de historias
distintas **no** llevan `[P]` entre sí por eso, aunque las ramas sean
independientes: si se trabajan en paralelo, conviene una rama por historia y
resolver el archivo compartido al integrar.

### Within Each User Story

- Los tests se escriben primero y deben fallar antes de implementar
- Tipos y proyección (`domain/`) antes del cableado (`ui/`)
- El registro en el canónico antes de dar la historia por cerrada

### Parallel Opportunities

- T002 y T003 en paralelo con T001
- T007 y T011 en paralelo con el resto de Foundational
- Los tres tests de US1 (T012–T014) en paralelo
- Dentro de cada historia, sus tareas de test en paralelo
- Todo el bloque T059–T063 de Polish en paralelo

---

## Parallel Example: User Story 1

```bash
# Los tres tests de la maquinaria de verificacion, en paralelo:
Task: "PanelLayoutContractTest en intellij-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutContractTest.kt"
Task: "PanelLayoutInvariantsTest en intellij-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/PanelLayoutInvariantsTest.kt"
Task: "PanelRendererTest en intellij-plugin/src/test/kotlin/com/ezevillo/gitreview/ui/PanelRendererTest.kt"
```

---

## Implementation Strategy

### MVP First (User Story 1 + User Story 2)

1. Phase 1: Setup — el canónico y su verificador
2. Phase 2: Foundational — tipos, renderer, cableado del panel
3. Phase 3: US1 — la maquinaria que hace verificable la paridad
4. Phase 4: US2 — el ciclo de lectura, que es el uso dominante
5. **PARAR Y VALIDAR**: recorrer una review entera en `runIde` sin tocar el menú, y comparar lado a lado con `npm run preview`

El MVP es de dos historias y no de una a propósito: US1 sola entrega
infraestructura sin superficie visible, y US2 sola entrega superficie sin la red
que impide que se desvíe.

### Incremental Delivery

1. Setup + Foundational → base lista
2. + US1 + US2 → **MVP**: se lee y se navega desde el panel, con la paridad afirmada por el build
3. + US3 → el ciclo se cierra desde el panel
4. + US4 → el estado vacío deja de mandar al menú; **las cuatro P1 completas**
5. + US5, US6 → whole y diagnóstico
6. + US7, US8 → pie y feedback de carga
7. Polish → accesibilidad, temas, documentación y verificación completa

### Parallel Team Strategy

Después de Foundational, con una rama por historia:

- Persona A: US2 (lectura) → US5 (whole)
- Persona B: US3 (ciclo de vida) → US8 (carga)
- Persona C: US4 (estado vacío) → US7 (pie) → US6 (diagnóstico)

`domain/PanelLayout.kt` y `ui/PanelActionDispatcher.kt` son los dos puntos de
integración; conviene integrar seguido y no acumular ramas largas.

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Cada historia debe quedar completable y testeable por separado
- Verificar que los tests fallan antes de implementar
- Commitear después de cada tarea o grupo lógico
- Parar en cualquier checkpoint para validar la historia por separado
- La referencia de producto es el panel real de la extensión
  (`vscode-extension/src/views/panelHtml.ts`), no la matriz `surface:` del
  canónico ni specs anteriores
