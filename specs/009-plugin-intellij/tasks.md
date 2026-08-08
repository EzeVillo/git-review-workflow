# Tasks: Plugin de IntelliJ IDEA (paridad VS Code)

**Input**: Design documents from `/specs/009-plugin-intellij/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md),
[research.md](./research.md), [data-model.md](./data-model.md),
[contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: sí — SC-007 y CLAUDE.md. Cada bloque de dominio es red-first:
JUnit que falla antes del port. Nombres de tests en ASCII.

**Organization**: Setup → Foundation (domain + invoke + anti-drift) →
historias US1…US8 → Polish. El **release** es paridad total; el **MVP
interno** usable es US1+US2+US7 (leer panel + abrir + CLI missing).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: paralelizable
- **[Story]**: [US1]…[US8] según [spec.md](./spec.md)
- Paths bajo `intellij-plugin/` salvo canónico en `contracts/`

## Path Conventions

- Plugin: `intellij-plugin/src/main/kotlin/com/ezevillo/gitreview/…`
- Tests: `intellij-plugin/src/test/kotlin/com/ezevillo/gitreview/…`
- Canónico: `contracts/client-product-surface.yaml` (raíz del repo)
- Extensión (anti-drift): `vscode-extension/test/unit/…` + script CI

**Nota de paquete**: el groupId es **`com.ezevillo`** (como el usuario git del
repo y el id de plugin de research § Decisión 12). Si al registrar el plugin
en Marketplace hiciera falta otro, se renombra de una vez en T001 — nunca
mezclado con el anterior.

---

## Phase 1: Setup

**Purpose**: scaffold Gradle + esqueleto de paquetes.

- [X] T001 Crear `intellij-plugin/` con IntelliJ Platform Gradle Plugin 2.x,
  `settings.gradle.kts`, `build.gradle.kts`, `gradle.properties`, wrapper, y
  paquete base `com.ezevillo.gitreview`. **Verificar primero** la línea
  estable y su JDK contra la tabla oficial de build ranges de JetBrains del
  día: al planear es IDEA **2026.2 → branch 262** (`20YY.N → (YY)(N)`; el 261
  del primer borrador era 2026.1). `gradle.properties` es la **única** fuente
  del pin — plan, research y quickstart lo citan, no lo fijan.
- [X] T002 [P] Añadir `intellij-plugin/src/main/resources/META-INF/plugin.xml`
  (nombre, vendor, dependencia `com.intellij.modules.platform` + Git4Idea,
  tool window stub con id **`gitReview.walkthrough`** — confirmar que la
  validación del descriptor acepta el punto; si no, `GitReviewWalkthrough` y
  actualizar `contracts/plugin-surface.md`), `since-build`/`until-build`
  tomados de `gradle.properties`.
- [X] T003 [P] Crear árbol de fuentes vacío:
  `domain/`, `host/`, `vcs/`, `diff/`, `ui/`, `settings/` bajo el paquete base
  + `src/test/kotlin/…/domain/`.
- [X] T004 [P] README del módulo `intellij-plugin/README.md` (build, runIde,
  test) en inglés de producto; una línea en `README.md` + `README.es.md` de
  la raíz apuntando al plugin (ambos README).
- [X] T005 Configurar job CI en `.github/workflows/` que corra
  `./gradlew -p intellij-plugin test` en **ubuntu, macos y windows** (unit
  domain) y, **solo en ubuntu**, `platformTest` (el harness headless llega en
  T030a; hasta entonces el target puede estar vacío). runIde no corre en CI.

**Checkpoint**: `gradlew test` (vacío o placeholder) y `runIde` arrancan.

---

## Phase 2: Foundational (domain + invoke + anti-drift)

**Purpose**: bloquea todas las US. Paridad de parsers y máquina de estados.

**CRITICAL**: no tool window de producto hasta T020+.

- [X] T006 Crear `contracts/client-product-surface.yaml` (raíz del repo)
  rellenado **leyendo el código**, no el ejemplo del contrato: constantes de
  `vscode-extension/src/cli/{version,installHint}.ts` y strings de
  `panelHtml.ts` / `state.ts` / `commands/setBase.ts` — min 0.4.0, npm
  install/update, multi-root error, `cli_outdated_title` con el `"installed"`
  que el borrador del esquema se comía, `no_base_candidates`. Incluir la
  clave `actions` con las 27 acciones × situaciones × superficie
  (panel|action|both): es la **fuente normativa** de la matriz, de la que
  `plugin-surface.md` y § Acciones de la spec pasan a ser resúmenes.
- [X] T007 [P] Script `scripts/check-client-product-surface.mjs` (o `.sh`)
  que parsea el YAML y falla si no existe; cablear en CI.
- [X] T008 [P] Test JUnit `domain/VersionTest.kt` port de
  `vscode-extension/test/unit/version.spec.ts` (red-first).
- [X] T009 Implementar `domain/Version.kt` (`MIN_CLI_VERSION` desde canónico
  o constante verificada por check) hasta verde.
- [X] T010 [P] Tests+impl `domain/Unquote.kt` / `PathRef` port de
  `unquote.spec.ts` + `unquote.ts`.
- [X] T011 [P] Tests+impl `domain/Porcelain.kt` port de `porcelain.spec.ts`
  + `porcelain.ts` (status + list).
- [X] T012 [P] Tests+impl `domain/ConfigPorcelain.kt` port de
  `configPorcelain.spec.ts`.
- [X] T013 [P] Tests+impl `domain/NameStatus.kt` port de `nameStatus.spec.ts`.
- [X] T014 [P] Tests+impl `domain/Situation.kt` port de reglas en
  `situation.ts` + casos de `state.spec.ts`.
- [X] T015 [P] Tests+impl `domain/PanelModel.kt` port de
  `panelModel.spec.ts` + `panelModel.ts`.
- [X] T016 [P] Tests+impl `domain/ReviewIntent.kt` + `LayoutOffers.kt` port
  de `reviewIntent.spec.ts` + `layoutOffers.spec.ts`.
- [X] T016a [P] Tests+impl `domain/SourcePreference.kt`, `Housekeeping.kt`,
  `FinishOutcome.kt`, `StartFailure.kt` ports de los unit specs homónimos.
- [X] T016b [P] Tests+impl `domain/StaleGuard.kt` (`staleGuard.spec.ts`),
  `MutationLock.kt` (`mutationLock.spec.ts`), `EntryArg.kt`
  (`entryArg.spec.ts`), `CliProbe.kt` (`cliProbe.spec.ts`) y `SoleTarget.kt`
  — este último port de **`repository.spec.ts`**, que no es homónimo.
- [X] T016c [P] Tests+impl `domain/CliLog.kt` port de `cliLog.spec.ts` y
  `domain/InstallHint.kt` port de `installCli.spec.ts` + `cli/installHint.ts`
  (comandos npm y links salen del canónico, no hardcodeados). Cierra el
  alcance de SC-007: los únicos specs de `test/unit/` sin port son
  `panelHtml.spec.ts` (markup de otro editor) y `userDataDir.spec.ts`
  (infra de test de VS Code).
- [X] T016d [P] Test table-driven `domain/ActionArgvParityTest.kt`: para las
  **27** acciones de `contributes.commands`, `(acción, parámetros) → argv`
  exacto contra la tabla de `contracts/cli-invocation.md` § Mutaciones —
  incluido el orden de flags de start, el `--` antes de la rama y el
  `--onto-source` solo desde porcelain. Es la verificación automatizada de
  SC-003 y FR-008; sin ella la paridad de argv depende de leer un log a ojo.
- [X] T017 Tests+impl `domain/ResolveCommand.kt` + `TimeoutClass.kt` port de
  `invokeClass.spec.ts` + `invokeTimeout.spec.ts` (sin spawn). `TimeoutClass`
  incluye las cuatro clases: READ 15 s, LOCAL_MUTATION 120 s, NETWORK 300 s y
  **SUPPORT_GIT 30 s** (el git de apoyo de los diffs, hoy constante suelta en
  `openEntry.ts` de la extensión).
- [X] T017a [P] Copiar/adaptar fixtures de strings porcelain desde
  `vscode-extension/test/unit/*.spec.ts` a
  `intellij-plugin/src/test/resources/fixtures/` para no re-inventar casos.
- [X] T018 Implementar `host/CliInvoker.kt`: `GeneralCommandLine` +
  capturadores UTF-8, timeouts, kill best-effort, env network, askpass
  no-op embebido en resources; log a `host/CliLog.kt`.
- [X] T019 Tests de integración ligeros de invoker (process real `git
  review --version` si hay CLI; skip si no) en
  `src/test/kotlin/…/host/CliInvokerIT.kt`.
- [X] T020 Implementar `host/ReviewStateManager.kt` (refresh coalescido,
  version generation, list/config solo en empty) port de `state.ts` **sin**
  depender de UI.
- [X] T021 [P] `settings/GitReviewSettings.kt` (`path`, `defaultSource`) +
  UI configurable mínima.
- [X] T022 [P] `vcs/RepositoryTargets.kt`: GitRepositoryManager +
  `pickSoleTarget`; listener de cambios → callback refresh.
- [X] T023 Regla de arquitectura: test o detekt que falle si `domain/**`
  importa `com.intellij`.

**Checkpoint**: domain 100 % unit verde (incluida la tabla de paridad argv de
T016d); invoker puede hablar con CLI; state machine sin UI.

---

## Phase 3: User Story 1 — Panel de estado (P1) 🎯

**Goal**: tool window nativo muestra ReviewState/PanelModel en las 8
situaciones.

**Independent Test**: sandbox walk/step/whole; contrastar con porcelain.

- [X] T024 [US1] `ui/GitReviewToolWindowFactory.kt` con construcción de
  contenido **solo al show**; no CLI en `isApplicable`.
- [X] T025 [US1] `ui/ReviewPanel.kt` (Swing): pinta `PanelModel` — empty
  setup, inventario, review walk/step/whole, finish banners, cli-*, error,
  out-of-range (estructura, no todos los botones mutativos aún).
- [X] T026 [US1] `host/GitReviewService.kt` (project service): target +
  stateManager + lock + update panel en EDT; refresh en open + git change
  coalescido.
- [X] T027 [US1] Acción `Refresh` + title actions stub; busy flag en model.
- [X] T028 [US1] Why diferido/cancelable (`status --why`) en walk; estados
  loading/present/absent/failed.
- [X] T029 [P] [US1] Preview standalone `preview/PanelPreviewMain.kt` +
  fixtures desde strings porcelain de tests; task Gradle `runPanelPreview`.
- [X] T030 [US1] Verificar SC-006 en un platform test (no “si viable”): abrir
  proyecto con el tool window cerrado no invoca CLI — spy sobre `CliInvoker` +
  log vacío.
- [X] T030a [US1] Harness de platform tests: source set / target Gradle
  `platformTest` con el intellij-platform test framework headless, fixture de
  proyecto con un root git, y el `PATH` apuntando al `bin/` del checkout
  (mismo truco que `runTests.ts` de la extensión, para que el test corra la
  CLI de este árbol). Primeros casos: wiring del tool window, SC-006 (T030) y
  una lectura de estado real contra un sandbox. Cablear en el job ubuntu de
  T005.

**Checkpoint**: lectura de las 8 situaciones en UI nativa; `platformTest`
verde en Linux.

---

## Phase 4: User Story 2 — Abrir archivo / diff / why (P1)

**Goal**: open entry, change, all, show why con git directo.

**Independent Test**: paths con espacio/acento; deleted file; post-start diff.

- [X] T031 [US2] `diff/RangeChanges.kt` + git name-status (UTF-8, timeout)
  usando GitExecutableManager.
- [X] T032 [US2] `diff/OpenEntryActions.kt`: WT file, HEAD fallback,
  DiffManager requests, multi-file chain whole, commit chain step.
- [X] T033 [US2] Cablear botones/actions panel → open entry/change/all/why.
- [X] T034 [US2] Persistencia lastOpened whole en
  `settings/LastOpenedStore.kt`.
- [X] T035 [P] [US2] Tests unit de mapeo name-status → lados diff; test
  manual checklist en quickstart § smoke #2/#4.

**Checkpoint**: SC-004 y SC-010 validables.

---

## Phase 5: User Story 3 — Navegación (P1)

**Goal**: next/prev/go-to con reglas de situation.

- [X] T036 [US3] Actions Next/Prev: MutationLock + stale token + invoke +
  refresh + openChange de nueva entrada (fuera del lock).
- [X] T037 [US3] GoTo: popup lista de entradas; open sin mover cursor CLI.
- [X] T038 [US3] Deshabilitar nav en finish-conflict y extremos (model
  atFirst/atLast).
- [X] T039 [P] [US3] Tests domain ya cubren locks; test de integración
  opcional navigate en sandbox.

**Checkpoint**: walk/step navegables solo en `review`.

---

## Phase 6: User Story 4 — Start / Continue (P1)

**Goal**: asistente start completo + continue desde inventario.

- [X] T040 [US4] Wizard start (diálogos JB): base → branch → source →
  range → layout desde offers; `intentToArgs`; confirm; network start.
- [X] T041 [US4] Fallo red → “Run in Terminal” con ResolvedCommand.
- [X] T042 [US4] Continue(index) con confirm + `continue <source>` +
  validación resumable.
- [X] T043 [US4] Discard inventory fila → housekeeping kind correcto.
- [X] T044 [US4] Set base / set remote en las **dos** superficies, como la
  extensión: dibujados en el panel solo en `no-review` (setup inline sin base,
  sección Settings con base) y registrados como acción global habilitada con
  cwd único y sin mutación en curso, incluso en `cli-*`. Sin candidatas leídas
  degrada con el `no_base_candidates` del canónico; en `error` sin cwd único
  la acción va deshabilitada (FR-003).
- [X] T045 [P] [US4] Tests domain intent/offers ya verdes; smoke start
  offline en sandbox.

**Checkpoint**: empty → review sin terminal (salvo red).

---

## Phase 7: User Story 5 — Finish / Abort / Save (P1)

**Goal**: ciclo de riesgo completo.

- [X] T046 [US5] Finish con pick destino; toast vía FinishOutcome post-refresh.
- [X] T047 [US5] Undo finish (+ force solo tras stderr); Resume con onto
  porcelain.
- [X] T048 [US5] Abort y Save con modales y stale guard.
- [X] T049 [US5] Banners finish-pending / finish-conflict en panel.

**Checkpoint**: SC-001 ciclo completo.

---

## Phase 8: User Story 6 — Auxiliares (P2)

**Goal**: clean, forget, compare, preview, walkthrough, log.

- [X] T050 [US6] `runHousekeeping` UI + confirms + network stale.
- [X] T051 [US6] Compare wizard + readonly note.
- [X] T052 [US6] Preview / preview --stat en editor LightVirtualFile.
- [X] T053 [US6] Walkthrough init/force/build + open file.

**Checkpoint**: SC-003 sobre acciones auxiliares.

---

## Phase 9: User Story 7 — CLI missing / multi-root / busy (P1)

**Goal**: diagnósticos y concurrencia.

- [X] T054 [US7] Acción **Show CLI Log** (vive acá, no en los auxiliares P2:
  es la herramienta de diagnóstico de esta historia y está disponible en las
  8 situaciones según la matriz; `CliLog` ya existe desde T016c/T018).
- [X] T055 [US7] UI cli-missing/outdated + copy npm desde canónico + probe
  10s solo visible.
- [X] T056 [US7] Mensaje multi-root / sin repo (FR-003).
- [X] T057 [US7] MutationLock toast “already in progress”; invalidate
  version al cambiar path setting.
- [X] T058 [P] [US7] Tests `CliProbe` + settings listener.

**Checkpoint**: SC-005, SC-006, first-run sin CLI con log inspectable.

---

## Phase 10: User Story 8 — Multiplataforma / theming (P1)

**Goal**: Win/macOS/Linux + LAF nativo.

- [X] T059 [US8] Verificar resolveCommand sh-on-Windows en máquina real o
  CI windows job.
- [X] T060 [US8] Forzar UTF-8 en todos los capturadores; test con fixture
  path no-ASCII en unit (bytes).
- [X] T061 [US8] Panel solo JBColor/UIManager — sin hex hardcodeados de VS
  Code; checklist a11y básica (contraste, teclado en controles custom).
- [X] T062 [US8] Documentar matriz smoke tres SO en
  `intellij-plugin/README.md` + quickstart.

**Checkpoint**: SC-004, SC-009, SC-010 en checklist de release.

---

## Phase 11: Polish & cross-cutting

- [X] T063 Completar check anti-drift: extensión lee/verifica YAML (test
  unit o script) + plugin; CI falla en divergencia (`min_cli_version`, npm,
  `multi_root_error`, `no_base_candidates`, y la matriz `actions` contra
  `contributes.commands` + `menus` de la extensión).
- [X] T063a Re-verificar la superficie contra la extensión antes de cerrar el
  release: diff de `contributes.commands`/`menus` y de los strings del
  canónico entre el 2026-08-08 (fecha en que la spec congela la paridad) y
  HEAD. Lo que haya cambiado se enmienda en spec + YAML, o se declara fuera
  de v1 por escrito en esta feature. Nunca se resuelve en silencio.
- [X] T064 `verifyPlugin` / pluginVerifier en Gradle; artefact zip.
- [X] T065 Iconos tool window (reusar o adaptar `vscode-extension/media`).
- [X] T066 CHANGELOG del plugin + mención versión en monorepo si aplica.
- [X] T067 Actualizar `CLAUDE.md`: sección del plugin con los comandos Gradle
  (`test`, `platformTest`, `runIde`, `runPanelPreview`), la regla “CLI y
  extensión en contenedor / plugin con Gradle”, y el nuevo `contracts/` de la
  raíz como fuente canónica multi-cliente (junto a la regla de los dos README).
- [X] T068 Pasar quickstart end-to-end y marcar SC-001…SC-010 con evidencia
  en checklist de release (archivo
  `specs/009-plugin-intellij/checklists/release.md` opcional).

---

## Dependencies

```text
Phase1 Setup
  → Phase2 Foundation (domain+invoke+state+vcs+settings)
    → US1 Panel
      → US2 Diffs (needs panel+state)
      → US3 Nav (needs panel+invoke)
      → US7 Diagnostics (can parallel US2 after US1)
    → US4 Start/Continue (needs foundation+panel)
      → US5 Finish cycle
      → US6 Auxiliares
    → US8 Multi-OS (throughout; formalize late)
  → Polish (anti-drift full, packaging)
```

**Parallel examples (Phase 2)**: T008–T017a domain ports en paralelo tras
T006/T007 (T016c/T016d incluidos; T016d necesita el canónico de T006 para la
lista de acciones); T021/T022 en paralelo a T018–T020.

## Implementation strategy

1. **Foundation first** — sin esto no hay paridad confiable.
2. **US1+US2+US7** = demo interna “se puede revisar”.
3. **US4+US5** = reemplazo de terminal para el ciclo.
4. **US3** se puede intercalarse tras US2.
5. **US6+US8+Polish** cierran el release de paridad total.
6. No etiquetar v1 Marketplace hasta SC-001–010 + anti-drift CI verde.

## Task count

| Phase | Tasks | Story |
|-------|-------|-------|
| Setup | T001–T005 | — |
| Foundation | T006–T023 (+T016a/b/c/d, T017a) | — |
| US1 | T024–T030a | Panel |
| US2 | T031–T035 | Diff |
| US3 | T036–T039 | Nav |
| US4 | T040–T045 | Start |
| US5 | T046–T049 | Finish |
| US6 | T050–T053 | Aux |
| US7 | T054–T058 | Diag |
| US8 | T059–T062 | Multi-OS |
| Polish | T063–T068 (+T063a) | — |
| **Total** | **75** (T001–T068 + T016a/b/c/d + T017a + T030a + T063a) | |

**MVP interno sugerido**: T001–T035 + T054–T057 (panel + open + cli missing +
log de invocaciones).  
**Release paridad**: todas las tasks.
