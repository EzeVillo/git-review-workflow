---

description: "Task list template for feature implementation"
---

# Tasks: Extensión de VS Code para revisar con walkthrough

**Input**: Design documents from `/specs/002-extension-vscode/`

**Prerequisites
**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/cli-invocation.md](./contracts/cli-invocation.md), [contracts/extension-surface.md](./contracts/extension-surface.md), [quickstart.md](./quickstart.md)

**Tests**: incluidas. `plan.md` (sección Testing) y `research.md` (Decisión 11) fijan explícitamente
la estrategia de dos suites — unitaria (`mocha`, sin host) e integración (`@vscode/test-electron`
con fixtures construidos por la CLI real) — así que no son opcionales para esta feature.

**Organization**: las tareas están agrupadas por historia de usuario del [spec](./spec.md), en su
orden de prioridad (P1 → P3), para que cada una sea implementable y verificable de forma
independiente.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: puede correr en paralelo (archivo distinto, sin dependencias pendientes)
- **[Story]**: a qué historia de usuario pertenece (US1..US6)
- Todas las rutas son relativas a la raíz del repo; el subdirectorio del proyecto es
  `vscode-extension/` (ver `plan.md` § Project Structure)

## Path Conventions

Proyecto de extensión de editor, autocontenido en su propio subdirectorio (no es el layout
single-project/web/mobile genérico del template — ver `plan.md` § Structure Decision):

```text
vscode-extension/
├── src/{cli,review,views,commands}/
├── test/{unit,integration}/
├── package.json, esbuild.js, tsconfig.json, .vscodeignore
```

---

## Phase 1: Setup

**Purpose**: inicialización del subproyecto — no toca la raíz del monorepo salvo el job de CI (Phase
Polish).

- [X] T001 Crear el árbol de directorios de `vscode-extension/` (`src/cli`, `src/review`,
  `src/views`, `src/commands`, `test/unit`, `test/integration`) por `plan.md` § Project Structure
- [X] T002 Crear `vscode-extension/package.json`: `name`, `engines.vscode: ^1.75.0` (research.md
  Decisión 12), `devDependencies` (`typescript`, `esbuild`, `@types/vscode`, `@types/node`, `mocha`,
  `@vscode/test-electron`, `@vscode/vsce`), scripts `compile`/`watch`/`package`/`test`/`pretest`
- [X] T003 [P] Crear `vscode-extension/tsconfig.json` (TypeScript 5.x estricto, target Node ≥18)
- [X] T004 [P] Crear `vscode-extension/esbuild.js` (bundle de `src/extension.ts` para el extension
  host)
- [X] T005 [P] Crear `vscode-extension/.vscodeignore` (excluye `src/`, `test/`, `node_modules` del
  `.vsix`)
- [X] T006 [P] Configurar el runner de la suite unitaria en
  `vscode-extension/test/unit/.mocharc.json` (mocha + `node:assert`, sin host de VS Code)
- [X] T007 [P] Crear `vscode-extension/test/integration/runTests.ts` (bootstrap de
  `@vscode/test-electron`, research.md Decisión 11)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: lo que toda historia necesita para existir — invocación a la CLI, parseo del contrato
porcelain, resolución del repositorio objetivo, y el esqueleto de activación/vista. Nada de esto es
visible por sí solo; es lo que hace posible US1..US6.

**⚠️ CRITICAL**: ninguna historia de usuario puede empezar hasta que esta fase esté completa.

- [X] T008 [P] `vscode-extension/src/cli/invoke.ts` —
  `execFile('git', ['review', verbo, ...args], { cwd, shell: false, timeout, signal })`, resolviendo
  el ajuste `gitReview.path` como fallback del dispatcher (contracts/cli-invocation.md § "Forma de
  toda invocación")
- [X] T009 [P] `vscode-extension/src/cli/unquote.ts` — decodifica el citado estilo C de git (`\\`,
  `\"`, escapes de control, octales `\nnn` reensamblados como bytes y decodificados UTF-8) —
  research.md Decisión 8
- [X] T010 [P] `vscode-extension/test/unit/unquote.spec.ts` — unitarios de T009: path sin citar pasa
  igual, path citado con espacios/backslash/octales se decodifica correcto
- [X] T011 `vscode-extension/src/cli/porcelain.ts` — tokenizador de registros `state`/`entry`/
  `uncovered` con aridad decidida por `mode` (leído primero, nunca al revés — data-model.md),
  etiquetas desconocidas y campos extra al final ignorados (FR-003); construye cada
  `PathRef {raw, display}` con T009 (depende de T009)
- [X] T012 [P] `vscode-extension/test/unit/porcelain.spec.ts` — unitarios de T011: aridad de
  `whole`/`step`/`walk`, `essential` vs `banked` según el modo, etiqueta desconocida ignorada,
  campos extra ignorados, `PathRef.raw`/`display` correctos (research.md Decisión 2/11)
- [X] T013 [P] `vscode-extension/src/review/repository.ts` — `RepositoryTarget` vía la API de
  `vscode.git` (enumera repos del workspace, desambigua multi-root por FR-029); fallback
  `FileSystemWatcher` sobre `HEAD`/`config` si la extensión git está deshabilitada (research.md
  Decisión 7)
- [X] T014 `vscode-extension/src/review/state.ts` — deriva `Situation` del exit code (`0`→`review`,
  `2`→`no-review`, `3`→`out-of-range`, `1` u otro→`error`), arma `ReviewState`/`SequenceEntry[]`/
  `UncoveredFile[]` desde `status --porcelain` (T008+T011), coalesce de refrescos concurrentes en
  una sola re-ejecución (research.md Decisión 9, política de lecturas) — depende de T008, T011, T013
- [X] T015 [P] `vscode-extension/test/unit/state.spec.ts` — unitarios de T014: mapeo exit code→
  `Situation`, un exit code desconocido (`>3`) se trata como `error`
- [X] T016 `vscode-extension/test/integration/helpers/fixture.ts` — construye repos fixture
  invocando el `bin/git-review` real del checkout (vía `gitReview.path`, research.md Decisión 11 "
  deuda anotada"), usado por todas las suites de integración
- [X] T017 `vscode-extension/package.json` (manifiesto) —
  `activationEvents: ["onView:gitReview.walkthrough"]`, `contributes.viewsContainers` (Activity Bar
  `gitReview`), `contributes.views` (`gitReview.walkthrough`, tipo `tree`),
  `contributes.configuration` (`gitReview.path`, string, default `""`) —
  contracts/extension-surface.md
- [X] T018 `vscode-extension/src/extension.ts` — `activate()`: instancia `RepositoryTarget` + el
  manejador de `ReviewState`, registra el `TreeView` vacío en `gitReview.walkthrough`, se suscribe a
  los cambios del repositorio para refrescar (FR-019), publica el `setContext` inicial de
  `gitReview.situation`/`gitReview.mode`/`gitReview.busy` — depende de T013, T014, T017

**Checkpoint**: con esto compilando y los unitarios en verde, cualquier historia de usuario puede
empezar.

---

## Phase 3: User Story 1 - Ver el walkthrough como panel de lectura (Priority: P1) 🎯 MVP

**Goal**: al abrir un repositorio con una review activa en modo walk, el panel lista las entradas en
el orden del walkthrough, marca la actual y las esenciales, y agrupa aparte los archivos sin
cobertura — sin escribir ningún comando.

**Independent Test**: abrir un repositorio con una review en modo walk y verificar que el panel
lista exactamente las entradas de la secuencia, en orden, con la posición actual y las esenciales
distinguibles (no depende de otra historia).

- [X] T019 [US1] `vscode-extension/src/views/walkthroughTreeProvider.ts` — `TreeDataProvider`: ítems
  desde `SequenceEntry[]` en el orden del registro (FR-005), entrada actual por coincidencia de
  `position` con `ThemeIcon` distintivo (FR-006), esencial con `ThemeIcon`+`description` en modo
  walk (FR-007), `label` = `PathRef.display` (FR-012)
- [X] T020 [US1] `walkthroughTreeProvider.ts` — nodo colapsable "Sin cobertura" agrupando
  `UncoveredFile[]`, separado de las entradas (FR-008)
- [X] T021 [US1] `walkthroughTreeProvider.ts` / `extension.ts` — `TreeView.description` = `N/M` (
  posición/total derivado, FR-009) con advertencia cuando `total ≠ recorded` (FR-011)
- [X] T022 [US1] `walkthroughTreeProvider.ts` — `TreeView.message` con el motivo cuando
  `walkthrough = degraded`, sin impedir el uso de la review (FR-010)
- [X] T023 [US1] `package.json` + `walkthroughTreeProvider.ts` — mensaje/estado para `mode = whole`
  sin walkthrough: árbol vacío explicado, sin listar entradas y sin presentarlo como error (FR-026)
- [X] T024 [P] [US1] `vscode-extension/test/integration/walkthrough-panel.spec.ts` — fixture walk de
  7 entradas (3ª esencial, cursor en la 2ª, con archivos sin cobertura): verifica
  orden/actual/esencial/cobertura/descripción contra `git review status --porcelain` (quickstart
  §1); sub-casos whole-sin-walkthrough y walkthrough-degradado (spec US1 AC3/AC4)

**Checkpoint**: User Story 1 funcional y verificable de forma independiente — el MVP.

---

## Phase 4: User Story 2 - Saltar al archivo de una entrada (Priority: P1)

**Goal**: un clic en una entrada del panel abre el archivo correspondiente con los cambios de la
review visibles y editables.

**Independent Test**: con una review activa, hacer clic en cada entrada del panel y verificar que
abre el archivo correcto y que los cambios son visibles y editables.

- [X] T025 [US2] `vscode-extension/src/commands/openEntry.ts` — comando `gitReview.openEntry`: abre
  el documento del working tree desde el `Uri` de `PathRef.display`; si el archivo no existe (
  eliminado en el rango) cae al diff vía `git.openChange` (research.md Decisión 10)
- [X] T026 [US2] `walkthroughTreeProvider.ts` — asigna `TreeItem.command = gitReview.openEntry` a
  los ítems de entrada (comando por defecto del clic)
- [X] T027 [US2] `package.json` — registra `gitReview.openEntry` y `gitReview.openChange` (acción
  inline que delega en el comando incorporado `git.openChange`)
- [X] T028 [P] [US2] `vscode-extension/test/integration/open-entry.spec.ts` — el clic abre el
  archivo correcto incluidos paths con espacios/no ASCII (spec US2 AC2), cae a diff en archivo
  eliminado (AC3), y las ediciones se aplican al working tree (AC1)

**Checkpoint**: User Stories 1 y 2 funcionan juntas de forma independiente.

---

## Phase 5: User Story 3 - Leer el porqué de cada entrada (Priority: P2)

**Goal**: el revisor lee la explicación de una entrada, con formato y saltos de línea preservados,
sin salir del editor.

**Independent Test**: con un walkthrough de textos conocidos, seleccionar cada entrada y verificar
que se muestra su texto con el formato preservado.

- [X] T029 [US3] `vscode-extension/src/views/whyContentProvider.ts` — `TextDocumentContentProvider`
  para el esquema `git-review-why:`, invoca `status --why <raw>` bajo demanda, sin caché (
  data-model.md § `Why`)
- [X] T030 [US3] `walkthroughTreeProvider.ts` — `resolveTreeItem` devuelve un `MarkdownString` con
  el *why* en el hover, llamado sólo cuando VS Code lo pide (research.md Decisión 6)
- [X] T031 [US3] `vscode-extension/src/commands/` + `package.json` — comando `gitReview.showWhy` (
  acción inline, paleta) que abre el documento virtual completo con vista previa Markdown
- [X] T032 [US3] `whyContentProvider.ts` — distingue `present = false` (cuerpo vacío, exit `0`, "sin
  explicación") de un fallo al obtenerlo (exit `1`) — FR-018
- [X] T033 [P] [US3] `vscode-extension/test/integration/why.spec.ts` — hover muestra el *why*, la
  lectura completa preserva saltos de línea/formato (spec US3 AC1); una entrada sin texto se indica
  sin error (AC2)

**Checkpoint**: User Stories 1-3 funcionan juntas de forma independiente.

---

## Phase 6: User Story 4 - Avanzar y retroceder en la secuencia (Priority: P2)

**Goal**: avanzar/retroceder desde el editor mueve el cursor igual que el verbo de la CLI, y el
panel refleja el cambio.

**Independent Test**: con una review activa, avanzar y retroceder desde el editor y verificar contra
la CLI que la posición registrada coincide.

- [X] T034 [US4] `vscode-extension/src/review/mutationLock.ts` — cola serializada de profundidad 1
  para `next`/`prev`; una segunda invocación mientras la primera está en vuelo se descarta, no se
  encola; publica `gitReview.busy` (research.md Decisión 9, FR-020)
- [X] T035 [P] [US4] `vscode-extension/test/unit/mutationLock.spec.ts` — una segunda llamada
  concurrente se descarta; el flag `busy` alterna correctamente
- [X] T036 [US4] `vscode-extension/src/commands/navigate.ts` — `gitReview.next`/`gitReview.prev`:
  invoca el verbo de la CLI a través de `mutationLock`, refresca con `status --porcelain`
  inmediatamente después (nunca parsea la salida humana del verbo), abre el archivo de la entrada
  resultante (FR-015)
- [X] T037 [US4] `navigate.ts` — propaga tal cual la respuesta de la CLI al intentar pasarse de un
  extremo de la secuencia, sin deshabilitar el comando por cuenta propia (FR-016)
- [X] T038 [US4] `package.json` — registra `gitReview.next`/`gitReview.prev` en el título de la
  vista y la paleta, `when: !gitReview.busy`
- [X] T039 [US4] `extension.ts` — `TreeView.message` = "trabajando…" mientras `gitReview.busy` es
  verdadero (FR-030)
- [X] T040 [P] [US4] `vscode-extension/test/integration/navigate.spec.ts` — avanzar/retroceder
  actualiza el panel y coincide con `git review status --porcelain` (spec US4 AC1); los intentos en
  los límites propagan la respuesta de la CLI sin dejar el panel inconsistente (AC2/AC3); correr el
  verbo en la terminal actualiza el panel sin reabrirlo (AC4, FR-019)

**Checkpoint**: User Stories 1-4 funcionan juntas de forma independiente.

---

## Phase 7: User Story 5 - Entender por qué no hay nada que mostrar (Priority: P2)

**Goal**: sin review, sin CLI, con CLI vieja, o con el cursor fuera de rango, el revisor entiende
qué pasa y qué puede hacer.

**Independent Test**: colocar el entorno en cada uno de los cinco estados y verificar que el panel
explica el estado y ofrece la salida correspondiente.

- [X] T041 [US5] `vscode-extension/src/cli/version.ts` — parsea la línea de `--version` y compara
  contra el mínimo `0.3.0` (research.md Decisión 1)
- [X] T042 [P] [US5] `vscode-extension/test/unit/version.spec.ts` — casos límite de comparación de
  versión (igual, menor en major/minor/patch, formato inválido)
- [X] T043 [US5] `review/state.ts` — invoca `--version` una vez por activación y al reintentar tras
  `cli-missing`; distingue `cli-missing` (`ENOENT` o subcomando no reconocido) de `cli-outdated` (<
  `0.3.0`), ambos distintos de `error`
- [X] T044 [US5] `vscode-extension/src/commands/installOrUpdateCli.ts` — comando
  `gitReview.installCli` que abre la guía de instalación de la CLI
- [X] T045 [US5] `package.json` — contribuciones `viewsWelcome` por `situation` (`no-review`/
  `out-of-range`/`cli-missing`/`cli-outdated`/`error`), `when: gitReview.situation == <valor>`,
  botón por cada una salvo `error` (research.md Decisión 5)
- [X] T046 [US5] contenido de los `viewsWelcome` — `out-of-range` con la acción concreta
  `git reset --soft` (FR-023); `error` muestra el `stderr` de la CLI preservado tal cual, sin
  botón (FR-024)
- [X] T047 [P] [US5] `vscode-extension/test/integration/empty-states.spec.ts` — las cinco
  preparaciones de quickstart §4 (sin review, sin CLI, CLI vieja, cursor fuera de rango, metadata
  corrupta/no-repo) renderizan pantallas distinguibles; "sin review" no se presenta como error (spec
  US5 AC1-AC5)

**Checkpoint**: User Stories 1-5 funcionan juntas de forma independiente — cubre todo salvo el modo
step.

---

## Phase 8: User Story 6 - Revisar commit por commit (Priority: P3)

**Goal**: con una review en modo step, el mismo panel lista los commits en orden, marca el actual y
distingue los que tienen ediciones guardadas.

**Independent Test**: con una review en modo step, verificar que el panel lista los commits en
orden, marca el actual y distingue los que tienen ediciones guardadas.

- [X] T048 [US6] `walkthroughTreeProvider.ts` — renderiza las entradas de modo step como commits (
  label por SHA), marca la actual reusando la coincidencia de `position`, distingue "con ediciones
  guardadas" (`banked`) con `ThemeIcon`+`description` propio, distinto del marcador de esencial de
  walk (FR-027)
- [X] T049 [US6] `commands/openEntry.ts` — el clic en una entrada de modo step muestra los cambios
  de ese commit (delega en `git.openChange` para el commit) en vez de abrir un archivo del working
  tree
- [X] T050 [P] [US6] `vscode-extension/test/integration/step-mode.spec.ts` — fixture step de 9
  commits, cursor en el 2º, ediciones guardadas en el 1º distinguidas, orden coincide con la CLI (
  spec US6 AC1); clic en un commit muestra sus cambios (AC2)

**Checkpoint**: las seis historias de usuario funcionan de forma independiente.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: lo que atraviesa varias historias y lo que sólo se puede verificar por revisión manual.

- [X] T051 [P] `.github/workflows/ci.yml` — agregar el job de `vscode-extension` (unitarios +
  integración) a la matriz ubuntu/macOS/windows existente, `xvfb-run` en Ubuntu para la
  integración (research.md Decisión 11, SC-007)
- [X] T052 [P] `vscode-extension/README.md` — notas de uso/empaquetado local (`npx vsce package`);
  no es la ficha del Marketplace, que queda fuera de alcance
- [X] T053 Verificar que `gitReview.path` resuelve el shim de npm en Windows cuando `git` no
  descubre el dispatcher desde el extension host (research.md Decisión 3, riesgo a validar en el
  primer entregable ejecutable, no al final)
- [X] T054 Correr manualmente los escenarios de `quickstart.md` de punta a punta
- [X] T055 Revisión manual del código contra la tabla de prohibiciones de
  `contracts/cli-invocation.md` para confirmar SC-005 (sin lecturas de config/refs/ramas, sin
  invocar verbos fuera de la lista cerrada, sin re-citar `PathRef.display`)

---

## Phase 10: Rediseño del panel — la entrada actual como contenido

**Purpose**: reemplazar el árbol por un panel dedicado a la entrada actual, con el *why* como cuerpo
y la secuencia en un `QuickPick` (spec FR-005/FR-005a/FR-017/FR-031, `research.md` Decisión 4
revisada). No cambia el origen del estado ni la superficie de invocación: sólo cómo se muestra.

**⚠️ Nota sobre las fases anteriores**: T019-T023, T026, T030, T045, T046 y T048 quedan
**superseded** por esta fase — describen el `TreeDataProvider` y las contribuciones `viewsWelcome`
que este rediseño elimina. Se dejan marcadas como estaban porque describen lo que efectivamente se
construyó; lo que las reemplaza es T056-T069.

- [X] T056 `vscode-extension/src/views/panelModel.ts` — `PanelModel` plano y serializable derivado de
  `ReviewState` + `busy` + `repoLabel` + `Why` (data-model.md § `PanelModel`): entrada actual por
  `position`, `baseMoved` = `total ≠ recorded`, `degraded`, contadores de secuencia y de no
  cubiertos, `why` con sus cuatro estados. Sin `import` de `vscode` — es la unidad testeable
- [X] T057 [P] `vscode-extension/test/unit/panelModel.spec.ts` — unitarios de T056: los tres modos,
  `current` ausente cuando ninguna entrada coincide con `position`, `baseMoved`, los cuatro estados
  de `why`, y que `PathRef.raw` no cruza al modelo
- [X] T058 `vscode-extension/src/views/walkthroughViewProvider.ts` — `WebviewViewProvider`: HTML con
  CSP + `nonce`, todo el color desde variables `--vscode-*`, controles `<button>` reales en orden de
  tab, contenido variable por `textContent` (research.md Decisión 4)
- [X] T059 `walkthroughViewProvider.ts` — barra superior: modo, rama, `N/M` (FR-009), advertencia de
  base movida (FR-011), nota de walkthrough degradado (FR-010), "trabajando…" (FR-030) y el
  repositorio en multi-root (FR-029)
- [X] T060 `walkthroughViewProvider.ts` — cuerpo de la entrada actual: posición, identificador
  (`PathRef.display` en walk, SHA en step), marca esencial/con-ediciones **con texto** (FR-007,
  FR-027, FR-031) y el *why* con saltos de línea preservados (FR-017)
- [X] T061 `walkthroughViewProvider.ts` — los cinco estados vacíos de la Historia 5 renderizados en
  el panel, con su botón salvo `error` y el `stderr` preservado (FR-024, research.md Decisión 5); y
  el caso `mode = whole` sin walkthrough (FR-026)
- [X] T062 `walkthroughViewProvider.ts` — protocolo de mensajes: conjunto cerrado de `type` del
  webview al host, `type` desconocido ignorado; el host postea el `PanelModel` entero
  (contracts/extension-surface.md § Protocolo)
- [X] T063 `vscode-extension/src/commands/pickEntry.ts` — `gitReview.goToEntry`: `QuickPick` de la
  secuencia en el orden de la CLI, con la actual marcada y preseleccionada, que **abre** lo elegido
  sin mover el cursor (FR-005a; la CLI no tiene verbo de salto — FR-002/FR-016)
- [X] T064 `pickEntry.ts` — `gitReview.showUncovered`: `QuickPick` separado con los archivos sin
  entrada, que abre el elegido (FR-008)
- [X] T065 `vscode-extension/src/extension.ts` — registra el `WebviewViewProvider` en lugar del
  `TreeView`, arma el `PanelModel` en cada cambio de estado/busy, y resuelve el *why* de **la
  entrada actual** por separado descartando respuestas de una entrada que ya no lo es (FR-018a,
  SC-009)
- [X] T066 `vscode-extension/package.json` — `views` con `"type": "webview"`, comandos
  `gitReview.goToEntry`/`gitReview.showUncovered`, `viewsWelcome` y `view/item/context` eliminados
  (no se renderizan en una vista webview — research.md Decisión 5)
- [X] T067 Eliminar `vscode-extension/src/views/walkthroughTreeProvider.ts` y migrar las suites de
  integración de `getTreeProvider()` a `getPanelModel()` (`walkthrough-panel.spec.ts`,
  `step-mode.spec.ts`, `why.spec.ts`)
- [X] T068 [P] `vscode-extension/test/unit/panelHtml.spec.ts` — el HTML sale de `panelHtml.ts`
  (función pura, sin `vscode`) y se afirman sus propiedades estructurales: CSP con `nonce` y sin
  `unsafe-inline`, un solo script y un solo style, **cero** colores literales (todo `--vscode-*`),
  nada de `innerHTML`, controles `<button>` sin handlers en atributos
- [ ] T069 Validar a ojo en el Extension Development Host `quickstart.md` §8 (tema claro/oscuro/alto
  contraste y recorrido por teclado). Parcialmente cubierto: el layout de los tres estados (walk,
  step, sin CLI) se verificó renderizando `panelHtml` en un navegador con las variables del tema
  oscuro, y T068 cubre por test que ningún color esté hardcodeado. Falta lo que sólo se ve en el
  host real: alto contraste de verdad y el recorrido con `Tab`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: sin dependencias — puede empezar de inmediato.
- **Foundational (Phase 2)**: depende de Setup. Bloquea las seis historias de usuario.
- **User Stories (Phase 3-8)**: todas dependen sólo de Foundational, no entre sí. Pueden avanzar en
  paralelo o en orden de prioridad (US1/US2 → US3/US4/US5 → US6).
- **Polish (Phase 9)**: depende de las historias que se quieran dar por terminadas antes de
  publicar (T054/T055 recorren todo lo implementado).
- **Rediseño (Phase 10)**: depende de las seis historias ya construidas — reemplaza su capa de
  presentación, no su lógica. Dentro de la fase: T056 antes que T058-T062 y T065 (todos consumen el
  `PanelModel`); T066 con T058; T067 al final, cuando ya no queda nada apuntando al árbol.

### User Story Dependencies

- **US1 (P1)**: sólo Foundational. Es el MVP.
- **US2 (P1)**: sólo Foundational. Usa el `TreeDataProvider` de US1 para el `command` del
  `TreeItem` (T026), pero su comando (`openEntry.ts`) es un archivo propio — no bloquea a US1.
- **US3 (P2)**: sólo Foundational; toca `walkthroughTreeProvider.ts` (creado en US1) para
  `resolveTreeItem`.
- **US4 (P2)**: sólo Foundational; el "trabajando…" de T039 comparte `extension.ts`/`TreeView` con
  US1.
- **US5 (P2)**: sólo Foundational; T045/T046 son contribuciones de manifiesto independientes de las
  de US1-US4.
- **US6 (P3)**: sólo Foundational; extiende el mismo `walkthroughTreeProvider.ts` y `openEntry.ts`
  que US1/US2 con ramas de modo `step` — es la primera historia a recortar si hace falta (spec.md §
  US6).

### Within Each User Story

- Los unitarios/integración de una historia van después de su implementación (no TDD estricto: el
  spec no lo pide, sólo pide las dos suites — research.md Decisión 11).
- El parser y el estado (Foundational) antes que cualquier vista.
- La vista (`walkthroughTreeProvider.ts`) antes que los comandos que la usan.
- Historia completa y su checkpoint validado antes de pasar a la siguiente si se trabaja en orden de
  prioridad.

### Parallel Opportunities

- Todo Setup marcado `[P]` (T003-T007) en paralelo.
- Dentro de Foundational: T008/T009 en paralelo (archivos independientes); T010/T012 (unitarios) en
  paralelo entre sí una vez listas sus implementaciones; T013 en paralelo con T008/T009.
- Con Foundational cerrado, US1, US2, US3, US4, US5 y US6 pueden repartirse entre desarrolladores
  distintos en paralelo — todas dependen sólo de Foundational.
- Los tests de integración de cada historia (`[P]`) son siempre el último paso de esa historia y no
  bloquean a otra.

---

## Parallel Example: Foundational

```bash
# En paralelo, apenas Setup está listo:
Task: "src/cli/invoke.ts — execFile wrapper con timeout/cancel"
Task: "src/cli/unquote.ts — des-citado estilo C de git"
Task: "src/review/repository.ts — RepositoryTarget vía API de vscode.git"

# Una vez que src/cli/unquote.ts existe:
Task: "test/unit/unquote.spec.ts"
Task: "src/cli/porcelain.ts (usa unquote.ts)"
```

## Parallel Example: User Story 1

```bash
# US1 completa (T019-T023) antes de:
Task: "test/integration/walkthrough-panel.spec.ts"
```

---

## Implementation Strategy

### MVP First (User Story 1 + 2)

1. Completar Phase 1: Setup.
2. Completar Phase 2: Foundational (crítica — bloquea todo lo demás).
3. Completar Phase 3: User Story 1 (ver el panel).
4. Completar Phase 4: User Story 2 (abrir el archivo).
5. **Parar y validar**: correr `quickstart.md` §1 contra un repo real. Con esto ya hay algo
   instalable y demostrable — es literalmente lo que spec.md llama "el mínimo que justifica instalar
   la extensión".

### Incremental Delivery

1. Setup + Foundational → base lista.
2. US1 → validar independientemente → demo (panel de sólo lectura).
3. US2 → validar independientemente → demo (MVP real: panel + navegación al archivo).
4. US3, US4, US5 → cada una se valida y demuestra por separado; no tienen orden obligado entre sí.
5. US6 → última, y la primera candidata a recortarse si el tiempo aprieta (spec.md lo dice
   explícitamente).
6. Polish → CI de la extensión, validación manual de SC-005 y del riesgo de Windows antes de dar la
   feature por cerrada.

### Parallel Team Strategy

Con más de un desarrollador, tras cerrar Foundational: uno toma US1+US2 (comparten
`walkthroughTreeProvider.ts`), otro toma US3+US4 (comparten el ciclo de refresco), otro toma US5 (
casi enteramente manifiesto + `state.ts`) y US6 queda para el final o se recorta.

---

## Notes

- `[P]` = archivos distintos, sin dependencias pendientes entre sí.
- La etiqueta `[USn]` traza cada tarea a su historia para verificar independencia.
- T019-T050 no tocan la raíz del monorepo; sólo `vscode-extension/`. Sólo T051 (CI) toca un archivo
  fuera del subdirectorio, tal como fija `plan.md` § Structure Decision.
- FR-001/FR-002/SC-005 (nada de estado derivado ni mutación fuera de la CLI) no son una tarea: son
  una restricción transversal a T008-T050 y la razón de ser de T055.
- Evitar: tareas vagas, dos tareas tocando el mismo archivo marcadas `[P]`, dependencias entre
  historias que rompan su independencia.
