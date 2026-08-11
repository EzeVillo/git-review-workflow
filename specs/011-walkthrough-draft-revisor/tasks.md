---

description: "Task list for 011-walkthrough-draft-revisor"
---

# Tasks: Walkthrough del revisor (draft local)

**Input**: Design documents from `/specs/011-walkthrough-draft-revisor/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/)

**Tests**: incluidos y **no opcionales**. `CLAUDE.md` los exige como estándar del
proyecto (asserts fuertes, sin falsos positivos, efecto real sobre el estado de
git verificado) y CI corre las suites en ubuntu, macOS y Windows.

**Organization**: agrupadas por user story, para que cada una se implemente,
pruebe y entregue por separado.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: puede ir en paralelo (archivos distintos, sin dependencias pendientes)
- **[Story]**: a qué user story pertenece (US1, US2, US3)
- Cada tarea nombra su archivo exacto

## Path Conventions

Monorepo, según [plan.md](plan.md) § Project Structure: CLI de shell en `bin/`,
suites bats en `tests/`, extensión en `vscode-extension/`, plugin en
`intellij-plugin/`.

**Recordatorios que aplican a toda la lista**:

- Todo script de shell pasa `./lint-docker.sh` (shellcheck). Nada de
  `A && B || C` (SC2015): guardas con `if` invertido.
- Las suites se corren **en el contenedor**: `./tests/run-docker.sh` y
  `./vscode-extension/test/run-docker.sh`. Nunca bats bajo Git Bash.
- Los nombres de `@test` van en **ASCII puro** (sin acentos ni em dashes):
  `tests/test-names.bats` lo verifica sobre toda la suite.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: dejar el entorno listo para iterar sin sorpresas.

- [X] T001 Verificar que la imagen de tests construye y la suite actual pasa en verde, para tener un baseline: `./tests/run-docker.sh` y `./lint-docker.sh`
- [X] T002 [P] Agregar al sandbox un caso que hoy no cubre: una rama sin walkthrough **con** archivos de nombre hostil (espacio y byte no ASCII) para ejercitar la comparación de paths del borrador, en `tests/sandbox.sh`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: la resolución de precedencia y sus helpers. **Bloquea todo lo
demás**: sin esto ningún verbo puede leer un borrador y ningún cliente puede
ofrecerlo.

**⚠️ CRÍTICO**: completar antes de empezar cualquier user story.

- [X] T003 Implementar `walk_draft_path <src>` en `bin/git-review-lib.sh`: devuelve `<gitdir>/review-walkthrough/<src>.md` resolviendo `git rev-parse --git-dir` (el del working tree, para que cada `git worktree` tenga el suyo)
- [X] T004 Implementar `walk_saved_draft_path <src>` en `bin/git-review-lib.sh`, espejo del anterior sobre `review-saved-walkthrough/`
- [X] T005 Implementar `walk_use_draft <src>` en `bin/git-review-lib.sh`: fija la variable de contexto `walk_draft_src` que consume la resolución de precedencia
- [X] T006 Extender `walk_read` en `bin/git-review-lib.sh` con la precedencia de [data-model.md](data-model.md) § Precedencia: si `${walk_draft_src:-}` está fijada y existe su borrador, leerlo por redirección (**sin** `git show`, ver [research.md](research.md) § Decisión 7); si no, el sidecar del tip como hoy. La normalización de CR/BOM (`walk_normalize`) MUST aplicarse por igual a los dos caminos
- [X] T007 Implementar `walk_is_draft <src>` en `bin/git-review-lib.sh` (test de archivo, cero procesos), para el marcado de `status`
- [X] T008 Llamar `walk_use_draft "$src"` desde `load_walk_review_meta` y `load_step_review_meta` en `bin/git-review-lib.sh`, de modo que todo verbo con review activa herede el contexto sin tocarlo (mitigación (a) de [research.md](research.md) § Decisión 2)
- [X] T009 [P] Test bats de los helpers y la precedencia en `tests/walkthrough-draft-read.bats`: sin borrador lee el sidecar; con borrador lee el borrador; con los dos gana el borrador; CRLF y BOM en el borrador no descuelgan ninguna entrada del orden

**Checkpoint**: los helpers existen y la precedencia es correcta, pero todavía
no hay forma de crear un borrador.

---

## Phase 3: User Story 1 — El revisor se arma el orden desde la terminal (Priority: P1) 🎯 MVP

**Goal**: que un revisor genere, complete, valide y use su propio orden de
lectura sin commitear, stagear ni deshacer nada.

**Independent Test**: sobre un PR sin walkthrough, generar el borrador,
completarlo, iniciar la review y comprobar modo walk con ese orden —
verificando que `git status` no cambia en ningún momento
([quickstart.md](quickstart.md) § Escenario 1).

### Subcomando

- [X] T010 [US1] Extender el parseo de `bin/git-review-verbs/walkthrough` con el subcomando `draft` y sus flags (`--build`, `--force`, `--local`, `--offline`, `--delta`, `<branch>` posicional, `--`), incluyendo las incompatibilidades de [contracts/cli-walkthrough-draft.md](contracts/cli-walkthrough-draft.md) (`--local` con `--offline`; `--force` con `--build`)
- [X] T011 [US1] Extraer la generación del esqueleto de `init` a una función reutilizable en `bin/git-review-verbs/walkthrough`, sin cambiar un byte de su salida (el esqueleto es idéntico para autor y revisor, [research.md](research.md) § Decisión 8)
- [X] T012 [US1] Implementar la resolución de rango de `draft` en `bin/git-review-verbs/walkthrough` con la misma política que `emit_reading_offers` (tip remoto/local, base, marcador de `--delta`, `fold_lower`), de modo que el esqueleto liste exactamente los archivos de la review (FR-002)
- [X] T013 [US1] Implementar la creación del borrador en `bin/git-review-verbs/walkthrough`: `mkdir -p` del directorio padre (los nombres con `/` crean subdirectorios), escritura vía archivo temporal + `mv` (patrón `sed_i`), rechazo sin `--force` si ya existe, y mensaje de salida con ruta y cantidad de archivos
- [X] T014 [US1] Extraer el cuerpo de validación de `build` en `bin/git-review-verbs/walkthrough` para que `draft --build` lo reuse contra el borrador y el rango de la rama, sin duplicar ninguna regla (placeholders, encabezados mal formados, `> key` con valor, duplicados, drift, renumerado canónico)
- [X] T013a [US1] Emitir en `bin/git-review-verbs/walkthrough` la nota de FR-005a cuando se crea un borrador para un tip que **ya trae walkthrough del autor**: el borrador tendrá precedencia mientras exista. Nota en stderr, exit `0` — nunca rechazo
- [X] T015 [US1] Implementar los errores de `draft` según la tabla de [contracts/cli-walkthrough-draft.md](contracts/cli-walkthrough-draft.md), cada uno accionable y sin efecto colateral

### Ciclo de vida

- [X] T016 [P] [US1] `bin/git-review-verbs/save`: mover el borrador de `review-walkthrough/` a `review-saved-walkthrough/`, junto al movimiento de refs que ya hace
- [X] T017 [P] [US1] `bin/git-review-verbs/continue`: movimiento inverso, **antes** de reconstruir el estado de la review, para que la lectura ya lo encuentre
- [X] T018 [P] [US1] `bin/git-review-verbs/clean`: podar `review-walkthrough/` y **nunca** `review-saved-walkthrough/`, misma asimetría que ya existe entre `refs/review-edits/` y `refs/review-saved-edits/`
- [X] T019 [P] [US1] `bin/git-review-verbs/forget`: `--saved <branch>` borra también el borrador guardado de esa rama

### Reporte y descubrimiento

- [X] T020 [US1] Emitir los ids `draft` / `draft-resume` en `emit_reading_offers` de `bin/git-review-lib.sh` según [contracts/config-porcelain-draft.md](contracts/config-porcelain-draft.md), respetando el orden estable y la exclusión mutua, y **sin agregar procesos** (test de archivo)
- [X] T021 [US1] Emitir el registro de presencia `draft` en `git review status --porcelain` y el sufijo `(draft)` en la línea de modo legible, en `bin/git-review-verbs/status`, según [contracts/status-porcelain-draft.md](contracts/status-porcelain-draft.md)
- [X] T021a [US1] Marcar `(draft)` junto al modo `walk` en `bin/git-review-verbs/list`, para reviews **activas y pausadas** — FR-014a dice "todas las superficies donde se informa el modo", y `list` es una de ellas ([list:100](../../bin/git-review-verbs/list:100))
- [X] T022 [US1] Agregar en `bin/git-review-verbs/start` la nota accionable cuando el PR no trae walkthrough ni el revisor tiene borrador, señalando `git review walkthrough draft`
- [X] T022a [US1] Fijar el contexto con `walk_use_draft` en `bin/git-review-verbs/compare` cuando el argumento nombra una rama con borrador, y **no** fijarlo cuando son revisiones sueltas (FR-011a, [research.md](research.md) § Decisión 2 · caso especial)

### Tests

- [X] T023 [P] [US1] `tests/walkthrough-draft.bats`: creación (ruta, cantidad, esqueleto idéntico al de `init`), `--force`, persistencia entre invocaciones (FR-004: el borrador sigue ahí y con el mismo contenido en una invocación posterior), y cada error de la tabla del contrato afirmando exit code + stderr + **ausencia de efecto colateral**
- [X] T023a [P] [US1] `tests/walkthrough-draft.bats`: crear un borrador sobre una rama **con** walkthrough del autor emite la nota de precedencia y sale `0`; el sidecar del PR queda intacto (FR-005a)
- [X] T024 [P] [US1] `tests/walkthrough-draft.bats`: `--build` válido (reescritura canónica, orden y renumerado) e inválido (cada regla de rechazo), afirmando que en rechazo el borrador queda **byte por byte** como estaba
- [X] T025 [P] [US1] `tests/walkthrough-draft.bats`: invariante de FR-003 — capturar `git status --porcelain` antes y después de crear y validar, y afirmar igualdad exacta
- [X] T026 [P] [US1] `tests/walkthrough-draft-lifecycle.bats`: `save` mueve, `continue` devuelve, `clean` poda sólo el activo, `forget --saved` borra el guardado, y `finish` deja `review-fixes/` **sin** rastro del borrador (FR-009)
- [X] T027 [P] [US1] `tests/config-offers-draft.bats`: las tres situaciones de la tabla de [quickstart.md](quickstart.md) § Escenario 6, afirmando el conjunto **exacto** de ids emitidos y su orden
- [X] T028 [P] [US1] `tests/walkthrough-draft-read.bats`: paridad entre superficies de una misma review (`status`, `status --why`, `next`, `preview`) — todas leen el borrador, ninguna el sidecar (mitigación (b) de [research.md](research.md) § Decisión 2)
- [X] T029 [P] [US1] `tests/walkthrough-draft-read.bats`: un borrador viejo o dañado degrada a whole con nota y **nunca** aborta la review (FR-013)
- [X] T029a [P] [US1] `tests/walkthrough-draft-read.bats`: un borrador **sin** `--build` (numerado a mano, sin renumerar) entra en walk y respeta el orden escrito (FR-012)
- [X] T029b [P] [US1] `tests/walkthrough-draft-read.bats`: `compare` sobre una rama con borrador usa el borrador; sobre dos SHAs usa el walkthrough del autor (FR-011a)
- [X] T029c [P] [US1] `tests/walkthrough-draft-lifecycle.bats`: crear o validar un borrador con una review **ya activa** no cambia su modo ni su cursor — afirmar la config de la rama antes y después (FR-014)
- [X] T029d [P] [US1] `tests/walkthrough-draft-lifecycle.bats`: el registro de presencia `draft` aparece en `status --porcelain` sólo cuando corresponde, y `list` marca `(draft)` en la review activa y en la pausada (FR-014a)

### Documentación de la CLI

- [X] T030 [P] [US1] Documentar `walkthrough draft` en `README.md` (tabla de verbos, flags y un ejemplo del flujo del revisor), dejando explícito que el producto no completa el borrador ni se conecta a ningún servicio (FR-023)
- [X] T031 [P] [US1] Espejar exactamente ese cambio en `README.es.md` — los dos README se actualizan **siempre** en el mismo cambio

**Checkpoint**: US1 entregable por sí sola. Un revisor de terminal ya tiene la
feature completa.

---

## Phase 4: User Story 2 — El asistente de VS Code lo ofrece (Priority: P2)

**Goal**: que la feature sea descubrible desde el editor, en el paso donde el
revisor se pregunta cómo leer el PR.

**Independent Test**: [quickstart.md](quickstart.md) § Escenario 7.

**Depends on**: US1 (los ids `offer` son dependencia dura).

- [X] T032 [US2] Agregar `draft` y `draft-resume` al tipo `OfferId` en `vscode-extension/src/cli/configPorcelain.ts`
- [X] T033 [US2] Agregar sus entradas a `OFFER_META` y `OFFER_ORDER` en `vscode-extension/src/review/layoutOffers.ts` con los textos de [contracts/client-draft-flow.md](contracts/client-draft-flow.md)
- [X] T034 [US2] Crear `vscode-extension/src/review/draftFlow.ts` con la máquina del bucle como **lógica pura** (estados: crear → esperar → validar → recargar ofertas → elegir walk/keys → confirmar; y la rama de cancelar que vuelve a forma de lectura), sin dependencias de `vscode`
- [X] T035 [US2] Extender la lista cerrada de invocaciones en `specs/002-extension-vscode/contracts/cli-invocation.md` con las dos formas de `walkthrough draft`, ambas `network: false`
- [X] T036 [US2] Implementar el argv de las dos invocaciones en `vscode-extension/src/review/reviewIntent.ts`, reusando los flags de origen y rango que el asistente ya resolvió
- [X] T037 [US2] Conectar la rama del asistente en `vscode-extension/src/commands/startReview.ts`: crear el borrador, abrirlo en el editor, y esperar con una notificación **con acciones** (`Continue` / `Cancel`) — nunca `{modal: true}`, que bloquearía la edición
- [X] T038 [US2] Implementar el reintento: en fallo de `--build`, mostrar el stderr aplanado y volver a presentar la notificación, sin límite de intentos
- [X] T039 [US2] Implementar el re-pick tras validación en verde: recargar ofertas y preguntar completo vs sólo esenciales **únicamente** si `keys` aparece; si no, continuar sin preguntar (FR-019)
- [X] T040 [US2] Implementar `Cancel`: volver al paso de forma de lectura conservando el borrador (FR-018a)
- [X] T041 [US2] Mostrar el badge de draft en `vscode-extension/src/views/panelHtml.ts` a partir del registro de presencia — **texto dentro de un bloque existente**, sin agregar bloques ni controles (ojo: el archivo entero es un template literal, **ningún backtick**, ni en comentarios)
- [X] T042 [P] [US2] Agregar el estado con badge de draft a `vscode-extension/preview/fixtures.ts` para que aparezca en `npm run preview`
- [X] T043 [P] [US2] Unit tests de `draftFlow` en `vscode-extension/test/unit/draftFlow.spec.ts`: transiciones, bucle de reintento, rama de cancelar, y el condicional del re-pick de keys
- [X] T044 [P] [US2] Unit test del parser en `vscode-extension/test/unit/`: los ids nuevos se parsean y ordenan; un id desconocido se sigue ignorando
- [X] T045 [US2] Test de integración en `vscode-extension/test/integration/`: el asistente ofrece la opción sobre un PR sin walkthrough y no la ofrece cuando hay sidecar del autor

**Checkpoint**: US1 + US2 entregables juntas.

---

## Phase 5: User Story 3 — Lo mismo desde IntelliJ (Priority: P3)

**Goal**: paridad de producto en el plugin.

**Independent Test**: [quickstart.md](quickstart.md) § Escenario 8.

**Depends on**: US1. Independiente de US2, aunque conviene portar el flujo ya
estabilizado.

- [X] T046 [US3] Agregar los ids nuevos en `intellij-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/ConfigPorcelain.kt`
- [X] T047 [US3] Agregar sus entradas a `OFFER_META` y `OFFER_ORDER` en `intellij-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/LayoutOffers.kt`, con **los mismos textos** que la extensión
- [X] T048 [US3] Portar la máquina del bucle a `intellij-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/DraftFlow.kt` como dominio puro (sin `com.intellij`)
- [X] T049 [US3] Implementar `intellij-plugin/src/main/kotlin/com/ezevillo/gitreview/ui/DraftWaitDialog.kt` con `DialogWrapper` e `isModal = false` — toda la familia `Messages.*` bloquea el IDE y no sirve
- [X] T050 [US3] Conectar la rama en `intellij-plugin/src/main/kotlin/com/ezevillo/gitreview/ui/StartWizard.kt`: como el asistente es síncrono, corta y se reanuda desde el callback del diálogo, con rama/origen/rango capturados en la closure
- [X] T051 [US3] Mostrar el badge de draft en `intellij-plugin/src/main/kotlin/com/ezevillo/gitreview/domain/PanelLayout.kt` y su render, **sin** modificar la estructura de bloques (`PanelLayoutContractTest` debe seguir verde sin tocar el YAML)
- [X] T052 [P] [US3] Tests de dominio en `intellij-plugin/src/test/kotlin/com/ezevillo/gitreview/domain/`: ids nuevos, orden, y paridad de `DraftFlow` con la máquina de la extensión
- [X] T053 [P] [US3] Agregar el estado con badge a `intellij-plugin/fixtures/com/ezevillo/gitreview/fixtures/PanelFixtures.kt` para `./gradlew runPanelPreview`

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T054 [P] Documentar la superficie de la extensión en `vscode-extension/README.md` (inglés, con links **absolutos** — `vsce` reescribe los relativos)
- [X] T055 [P] Agregar la entrada correspondiente a `vscode-extension/CHANGELOG.md`
- [X] T056 Revisar `contracts/client-product-surface.yaml`: subir `min_cli_version` porque los clientes pasan a depender de los ids nuevos, y **confirmar que `panel_layout` no cambió** (si cambió, el diseño se desvió del plan)
- [X] T057 Verificar que `node scripts/check-client-product-surface.mjs` sigue en verde (27 acciones, sin acciones nuevas)
- [X] T058 [P] Actualizar `CLAUDE.md` § Modelo de estado con el borrador del revisor y su ciclo de vida, en el párrafo del modo walk
- [ ] T059 Correr las cinco suites en verde: `./lint-docker.sh`, `./tests/run-docker.sh`, `npm run test:unit`, `./vscode-extension/test/run-docker.sh`, `cd intellij-plugin && ./gradlew test`
  - **Cuatro de cinco en verde**: shellcheck; 713 bats; 368 unit de la extensión;
    69 de integración (66 previos + 3 nuevos). Más
    `node scripts/check-client-product-surface.mjs` (27 acciones, `panel_layout`
    sin cambios).
  - **`./gradlew test` no se pudo correr**: en esta máquina el daemon de Gradle
    aborta con `java.io.IOException: Unable to establish loopback connection`
    antes de compilar nada — falla igual en `./gradlew help`, o sea que es del
    entorno y no del cambio (un `ServerSocket` sobre 127.0.0.1 desde el mismo
    JDK 25 sí conecta). Los archivos Kotlin de US3 quedan **sin compilar ni
    probar**: hay que correr `./gradlew test` en un entorno donde el daemon
    levante antes de dar la fase por cerrada.
- [ ] T060 Recorrer [quickstart.md](quickstart.md) a mano de punta a punta sobre el sandbox, incluidos los escenarios 7 y 8 (los dos avisos **no** deben bloquear la edición)
  - **Escenarios 1 a 6 recorridos a mano** sobre `tests/sandbox.sh` y
    `feature/telemetry` / `feature/pagos`: creación y `--build` del borrador con
    `git status --porcelain` idéntico antes y después; `start` entrando en walk
    con el orden escrito; `mode walk (draft)` y el registro `draft` en
    porcelain; `(draft)` en `list`; `next` / `--why`; `save` moviendo el
    borrador y `continue` devolviéndolo; `finish` dejando `review-fixes/` sin
    rastro; `clean` podando el activo; y las tres situaciones de ofertas.
  - **Escenario 7 (VS Code)**: cubierto por las tres specs de integración
    nuevas, que corren el asistente real contra la CLI real; falta la pasada a
    ojo en un editor de verdad para confirmar que el aviso no estorba la edición.
  - **Escenario 8 (IntelliJ)**: pendiente — depende de que `./gradlew runIde`
    pueda levantar (ver T059).

---

## Dependencies

```text
Setup (T001–T002)
   └─► Foundational (T003–T009)   ⚠️ bloquea todo
          ├─► US1 · CLI (T010–T031)          🎯 MVP, entregable sola
          │      ├─► US2 · VS Code (T032–T045)
          │      └─► US3 · IntelliJ (T046–T053)
          │
          └─► Polish (T054–T060)
```

- **US2 y US3 son independientes entre sí**: una vez cerrada US1 pueden ir en
  paralelo. Conviene US2 primero sólo para estabilizar el flujo antes de
  portarlo.
- Dentro de US1, el bloque de ciclo de vida (T016–T019) es paralelo al del
  subcomando (T010–T015) salvo por T013, que define dónde vive el archivo.

## Parallel Execution Examples

**Foundational**: T009 en paralelo con T003–T008 sólo si se escribe primero el
test y se lo deja fallando (los helpers no existen todavía).

**US1 — ciclo de vida**: T016, T017, T018 y T019 tocan cuatro verbos distintos y
van juntas.

**US1 — tests**: T023 a T029d son cuatro archivos bats distintos; todas en
paralelo una vez que existe el subcomando.

> **Sobre los ids con sufijo** (`T013a`, `T021a`, `T022a`, `T023a`,
> `T029a`–`T029d`): salieron de `/speckit-analyze`, que encontró seis huecos de
> cobertura y una ambigüedad de diseño (`compare`) después de numerar la lista.
> Se insertan en su lugar de ejecución en vez de renumerar sesenta tareas, con
> el mismo patrón que el repo ya usa en otras specs (`T030a`).

**US1 — documentación**: T030 y T031 son dos archivos, pero **se revisan como un
solo cambio**: la regla del proyecto es que ningún cambio toca un README sin el
otro.

**US2**: T042, T043 y T044 en paralelo con el trabajo de UI.

## Implementation Strategy

**MVP = Phase 1 + Phase 2 + Phase 3 (US1).** Es un incremento completo y
defendible: un revisor de terminal puede armarse el orden de lectura de
cualquier PR sin tocar el repositorio, que es el problema que originó la
feature. Los dos clientes son descubrimiento, no capacidad.

**Orden sugerido**: US1 → validar a mano con el sandbox → US2 → US3.

**Punto de no retorno**: T020 y T021 fijan contratos porcelain. Una vez
publicados, cambiar la forma de esos registros rompe clientes instalados; por
eso los contratos se cierran antes de escribir el código de los clientes, y son
aditivos por diseño.
