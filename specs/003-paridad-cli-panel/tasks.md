---

description: "Task list template for feature implementation"
---

# Tasks: Paridad de información entre la CLI y el panel del editor

**Input**: Design documents from `/specs/003-paridad-cli-panel/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[data-model.md](./data-model.md), [contracts/status-porcelain-v2.md](./contracts/status-porcelain-v2.md),
[quickstart.md](./quickstart.md)

**Tests**: incluidos. `plan.md` (sección Testing) fija explícitamente las cuatro suites — bats sobre la
CLI, `shellcheck`, unitarios de la extensión (`mocha`, sin host) e integración
(`@vscode/test-electron`) — así que no son opcionales para esta feature. Los `@test` de bats van en
ASCII puro (sin acentos, sin `ñ`, sin em dashes), aunque el resto de estos documentos esté en
español, por la misma regla que ya sigue `specs/001-contrato-porcelain/tasks.md`.

**Organization**: dos historias de usuario (US1 = P1, US2 = P2, del orden de [spec.md](./spec.md)),
cada una implementable y verificable de forma independiente. Dentro de cada una, el lado CLI va antes
que el lado extensión, porque la extensión sólo puede proyectar un dato que la CLI ya emite (FR-001).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: puede correr en paralelo (archivo distinto, sin dependencias pendientes)
- **[Story]**: a qué historia de usuario pertenece (US1, US2)
- Cada tarea incluye la ruta exacta de archivo

## Path Conventions

Monorepo con dos artefactos que esta feature toca a la vez (ver `plan.md` § Project Structure):

```text
bin/git-review-verbs/status     # emite los registros subject/author/base
bin/git-review-lib.sh           # helper que produce asuntos y autores en bloque
tests/status-porcelain.bats     # tests funcionales de los registros nuevos (archivo existente)
tests/porcelain-bytes.bats      # bytes hostiles (archivo nuevo, research.md Decisión 6)
tests/sandbox.sh                # commits con asunto/autor hostiles, para probar a mano

vscode-extension/src/cli/porcelain.ts       # parser: subject/author/base
vscode-extension/src/review/state.ts        # ReviewState los carga
vscode-extension/src/views/panelModel.ts    # los proyecta al PanelModel
vscode-extension/src/views/panelHtml.ts     # los dibuja
vscode-extension/src/commands/pickEntry.ts  # asunto en el selector de la secuencia
vscode-extension/preview/fixtures.ts        # estados nuevos del preview

README.md / README.es.md                    # formato porcelain: los tres registros nuevos
```

---

## Phase 1: Setup

**Purpose**: confirmar el punto de partida en los dos artefactos antes de tocar nada, para poder
demostrar después que la feature no regresó nada (SC-004, SC-008).

- [X] T001 Correr la línea base actual sin cambios y confirmar todo en verde antes de empezar:
  `shellcheck $(find bin -type f ! -name '.gitkeep') install.sh uninstall.sh web-install.sh web-uninstall.sh bump-version.sh tests/sandbox.sh`,
  `./tests/run-docker.sh`, y (`cd vscode-extension && npm test`)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: la única pieza que usan las dos historias del lado de la extensión — cómo se lee un campo
de texto libre que puede contener el separador de campos.

**⚠️ CRITICAL**: ninguna historia puede parsear un registro `subject`/`author`/`base` real antes de
esto.

- [X] T002 Agregar a [vscode-extension/src/cli/porcelain.ts](../../vscode-extension/src/cli/porcelain.ts)
  un helper de lectura de campo libre (p. ej. `restAfterTab(line, n)`) que devuelve **todo lo que sigue
  al n-ésimo tab de `line`, hasta el fin de línea** — no `line.split("\t")[n]`, que partiría un asunto
  u autor con un tab interno en varios elementos (data-model.md § "Lectura de un campo de texto
  libre"; el motivo exacto por el que `split` no sirve acá está medido en research.md Decisión 1).
  `n` es la cantidad de tabs a saltar: 2 para `subject`/`author` (`subject<TAB>position<TAB>texto`), 1
  para `base` (`base<TAB>texto`)

**Checkpoint**: helper listo — las dos historias pueden empezar del lado de la extensión. (El lado CLI
no depende de esto: `porcelain_row` ya existe sin cambios.)

---

## Phase 3: User Story 1 - Saber qué commit estoy revisando (Priority: P1) 🎯 MVP

**Goal**: en una review commit por commit, el panel muestra el asunto y el autor del commit actual, y
el selector de la secuencia identifica cada commit por su asunto además de por su SHA.

**Independent Test**: con una review `--step` sobre commits de asunto y autor conocidos, verificar que
`status --porcelain` emite `subject`/`author` por posición y que el panel los muestra y los actualiza
al navegar (spec.md, Escenarios 1-4 de US1). No depende de US2.

### Lado CLI

- [X] T003 [US1] Agregar el helper `load_step_texts` a
  [bin/git-review-lib.sh](../../bin/git-review-lib.sh): dos invocaciones de `git log --reverse
  --first-parent --no-merges --format=%s "$start..$tip"` y `--format='%an <%ae>' "$start..$tip"`
  (research.md Decisión 2 — número **constante** de procesos, independiente de `total`, FR-014),
  guardando el resultado en dos globals nuevos (`subjects`, `authors`) alineados por número de línea
  con `commits`. Documentar la invariante de alineación (data-model.md § "Derivación de la secuencia
  de asuntos y autores": ninguno de los dos formatos puede emitir un newline interno). Se llama después
  de `load_step_review_meta`, no la reemplaza ni la extiende — los demás verbos que la usan (`next`,
  `prev`, `start`, `continue`, `compare`) no necesitan `subjects`/`authors` y no deben pagar los dos
  procesos extra
- [X] T004 [US1] En la rama `step` de la ruta porcelain de
  [bin/git-review-verbs/status](../../bin/git-review-verbs/status) (líneas ~106-119), llamar a
  `load_step_texts` y emitir, dentro del mismo bucle que ya emite `entry` por posición, una línea
  `subject<TAB>$i<TAB>$asunto` y una línea `author<TAB>$i<TAB>$autor` por posición (usar `sed -n
  "${i}p"` sobre `subjects`/`authors`, igual que ya hace el bucle con `commits`), pasadas por
  `porcelain_row`. Sólo en modo step; en whole y walk estos registros no se emiten. No tocar la salida
  humana (Decisión 7)
- [X] T005 [P] [US1] bats: nueva sección "subject/author records (003 US1)" en
  [tests/status-porcelain.bats](../../tests/status-porcelain.bats) — con el fixture ya existente
  (`feature/x`, dos commits `c1-touch-a`/`c2-touch-b-add-c`, autor `tester <t@example.com>`) tras `git
  review start feature/x --step`, afirmar línea por línea que `status --porcelain` emite exactamente
  `subject\t1\tc1-touch-a`, `subject\t2\tc2-touch-b-add-c`, `author\t1\ttester <t@example.com>`,
  `author\t2\ttester <t@example.com>`; y que estos registros están **ausentes** en modo whole y en modo
  walk (mismo fixture, sin `--step`)
- [X] T006 [P] [US1] Agregar a [tests/sandbox.sh](../../tests/sandbox.sh) uno o más commits con un tab
  literal en el asunto y otro en el nombre del autor, en la rama de juguete que ya usa `--step`
  (research.md Decisión 6: "commits con asunto y autor hostiles agregados al sandbox"). Es para probar
  a mano (quickstart.md §3); no lo usan los tests automatizados
- [X] T007 [P] [US1] Archivo nuevo [tests/porcelain-bytes.bats](../../tests/porcelain-bytes.bats), con
  su propio fixture `--step` (no depende de T006): un commit con tab en el asunto, uno con tab en el
  autor (`git -c user.name="$(printf 'no\tmbre')" commit -m "$(printf 'con\ttab')"`), uno con asunto y
  autor no-ASCII/con emoji, y uno con asunto vacío (`git commit --allow-empty -m ""`). Para cada caso,
  afirmar (a) el tab o los bytes no-ASCII sobreviven literales en el campo, y (b) **el registro
  siguiente no se desplazó** — sigue siendo una línea `subject`/`author`/`entry` con su etiqueta en el
  primer campo y su posición en el segundo (la aserción que protege FR-011 de verdad, per quickstart.md
  §3); y que el asunto vacío produce `subject\t<n>\t` (campo vacío), no la ausencia de la línea

### Lado extensión

- [X] T008 [US1] En [vscode-extension/src/cli/porcelain.ts](../../vscode-extension/src/cli/porcelain.ts):
  agregar `subjects?: Map<number, string>` y `authors?: Map<number, string>` a `PorcelainResult`;
  en `parsePorcelain`, agregar los casos `"subject"` y `"author"` al `switch`: leer `position` con
  `toInt(fields[1])` y el texto con el helper de T002 (`restAfterTab(line, 2)`); crear el `Map`
  correspondiente perezosamente (sólo si al menos una línea de ese tipo aparece) y hacer `.set(position,
  texto)`. Etiquetas desconocidas siguen cayendo en el `default:` sin tocar (FR-003)
- [X] T009 [P] [US1] Unitarios nuevos en
  [vscode-extension/test/unit/porcelain.spec.ts](../../vscode-extension/test/unit/porcelain.spec.ts)
  para T008: `subjects`/`authors` se pueblan por posición en modo step; ambos mapas quedan `undefined`
  cuando el stdout no trae ninguna línea `subject`/`author` (CLI vieja, FR-004); un asunto con un tab
  literal en el medio se lee entero (no se corta en el primer tab) y la línea `entry`/`subject`
  siguiente se parsea sin desplazarse
- [X] T010 [US1] En [vscode-extension/src/review/state.ts](../../vscode-extension/src/review/state.ts):
  agregar `subjects?: Map<number, string>` y `authors?: Map<number, string>` a `ReviewState`, y en
  `doRefresh()` asignarlos desde `parsed.subjects`/`parsed.authors` junto al resto del resultado de
  `parsePorcelain` (depende de T008)
- [X] T011 [US1] En [vscode-extension/src/views/panelModel.ts](../../vscode-extension/src/views/panelModel.ts):
  agregar `subject?: string` y `author?: string` a `PanelEntry`; cambiar `toPanelEntry` para que reciba
  además `subjects`/`authors` (los mapas de T010) y setee esos dos campos por `entry.position` si están
  presentes; actualizar el único call site (`base.current = toPanelEntry(current)` en
  `buildPanelModel`) para pasarle `state.subjects`/`state.authors` (depende de T010)
- [X] T012 [US1] En el mismo
  [vscode-extension/src/views/panelModel.ts](../../vscode-extension/src/views/panelModel.ts): extender
  `entryPickLabel(entry, position, subject?)` para que, cuando `subject` esté presente, lo incluya en
  el `label` junto al SHA (FR-007). Actualizar el llamador en
  [vscode-extension/src/commands/pickEntry.ts](../../vscode-extension/src/commands/pickEntry.ts) para
  pasar la nueva `subjects` map (parámetro nuevo de `pickEntry`) al construir cada `EntryItem`. Y en
  `vscode-extension/src/extension.ts` (registro de `gitReview.goToEntry`, ~línea 291), pasar
  `state.subjects` a la llamada a `pickEntry` (depende de T010)
- [X] T013 [US1] En
  [vscode-extension/src/views/panelHtml.ts](../../vscode-extension/src/views/panelHtml.ts),
  `renderEntry` (~líneas 468-506): cuando `model.mode === "step"`, dibujar `model.current.subject`
  (si está presente) como cuerpo principal de la entrada, en el lugar donde hoy va `model.current.display`
  (el `<p class="id">`); mover el SHA corto (`model.current.display`) y `model.current.author` (si está
  presente) a la línea de metadatos (`head`), junto al número de posición y las marcas (research.md
  Decisión 4). Cuando `subject`/`author` no están presentes (CLI vieja), el panel dibuja exactamente lo
  que dibuja hoy — SHA como cuerpo principal, sin línea de autor (FR-003) (depende de T011)
- [X] T014 [P] [US1] Unitarios nuevos en
  [vscode-extension/test/unit/panelModel.spec.ts](../../vscode-extension/test/unit/panelModel.spec.ts):
  `buildPanelModel` proyecta `current.subject`/`current.author` cuando el `ReviewState` trae los mapas
  poblados; los deja `undefined` cuando `state.subjects`/`state.authors` son `undefined` (degradación
  FR-003); `entryPickLabel` incluye el asunto en el `label` cuando se le pasa, y se comporta como hoy
  cuando no
- [X] T015 [US1] En
  [vscode-extension/preview/fixtures.ts](../../vscode-extension/preview/fixtures.ts): agregar filas
  `subject`/`author` al pane `step` existente (líneas ~134-147), y un pane nuevo `step-legacy-cli` con
  los mismos registros `state`/`entry` pero **sin** las líneas `subject`/`author` — el estado de
  degradación de FR-003/SC-004 que quickstart.md §5 pide poder mirar
- [X] T016 [US1] En
  [vscode-extension/test/integration/step-mode.spec.ts](../../vscode-extension/test/integration/step-mode.spec.ts),
  extender el test "AC1" (líneas 29-83): afirmar que `model.current?.subject`/`model.current?.author`
  coinciden con el commit en la posición actual antes y después de `git review next` (Escenario 2 de
  US1 — no queda mostrando el asunto/autor del commit anterior), y que
  `entryPickLabel(entry, position, subjects.get(entry.position))` de cada entrada de `state.entries`
  incluye su asunto (Escenario 3) (depende de T010-T012)

**Checkpoint**: US1 completa y verificable por sí sola — el modo commit por commit deja de necesitar la
terminal para saber qué se está revisando.

---

## Phase 4: User Story 2 - Reconocer de qué review se trata (Priority: P2)

**Goal**: la barra del panel muestra el origen de la review y el tip fijado (los tres modos), y una
review sin walkthrough muestra además la base del rango cuando la hay.

**Independent Test**: con reviews en los tres modos, verificar que el panel identifica origen y tip; y
que en una review sin walkthrough con base configurada el panel la muestra, y sin base configurada no
muestra nada en su lugar (spec.md, Escenarios de US2). No depende de US1 — el origen y el tip ya llegan
al panel sin cambiar la CLI (research.md Decisión 0); sólo la base necesita contrato nuevo.

### Lado CLI

- [X] T017 [US2] En la rama `whole` (el `*)` final) de la ruta porcelain de
  [bin/git-review-verbs/status](../../bin/git-review-verbs/status) (líneas ~133-144): leer `base="$(git
  config "branch.$cur.reviewbase" || true)"` (el mismo `|| true` defensivo que ya usa la salida humana
  en la línea 225, por si la clave se borró a mano) y, sólo si `$base` no está vacío, emitir
  `base<TAB>$base` con `porcelain_row` **antes** de la línea `state` — el orden entre grupos de
  registros no es significativo (contracts/status-porcelain-v2.md). Omitir el registro entero cuando no
  hay base, nunca emitirlo vacío
- [X] T018 [P] [US2] bats: nueva sección "base record (003 US2)" en
  [tests/status-porcelain.bats](../../tests/status-porcelain.bats) — tras `git review start feature/x`
  (whole, con `reviewworkflow.base develop` ya fijado por `setup()`), afirmar `base\tdevelop` en
  `status --porcelain`; luego `git config --unset "branch.review/feature/x.reviewbase"` (simula
  metadata sin esa clave) y afirmar que la línea `base` **no aparece** — ni vacía ni con un centinela;
  y que el registro está ausente en modo step y en modo walk (usa el mismo fixture con `--step` / con
  un walkthrough recommiteado)

### Lado extensión

- [X] T019 [US2] En [vscode-extension/src/cli/porcelain.ts](../../vscode-extension/src/cli/porcelain.ts):
  agregar `base?: string` a `PorcelainResult`; en `parsePorcelain`, agregar el caso `"base"` al
  `switch`: el texto sale de `restAfterTab(line, 1)` (helper de T002 — el registro `base` tiene un solo
  campo libre, sin `position`)
- [X] T020 [P] [US2] Unitarios nuevos en
  [vscode-extension/test/unit/porcelain.spec.ts](../../vscode-extension/test/unit/porcelain.spec.ts):
  `base` se puebla en modo whole cuando la línea está presente; queda `undefined` cuando está ausente
  (CLI vieja o sin base registrada — los dos casos son indistinguibles para el consumidor y eso es
  correcto, FR-004 sólo exige distinguir ausencia de vacío, y `base` nunca se emite vacío)
- [X] T021 [US2] En [vscode-extension/src/review/state.ts](../../vscode-extension/src/review/state.ts):
  agregar `base?: string` a `ReviewState`, asignado desde `parsed.base` en `doRefresh()` junto a
  `subjects`/`authors` de T010 (depende de T019)
- [X] T022 [US2] En [vscode-extension/src/views/panelModel.ts](../../vscode-extension/src/views/panelModel.ts):
  agregar `source?: string` y `tip?: string` a `PanelModel`, poblados siempre que `situation ===
  "review"` desde `review.source`/`review.tip` (ya vienen en `StateRecord`, sin cambio de contrato —
  research.md Decisión 0); agregar `base?: string`, poblado sólo cuando `review.mode === "whole"` y
  `state.base !== undefined` (research.md Decisión 5, FR-008/FR-009) (depende de T021)
- [X] T023 [US2] En
  [vscode-extension/src/views/panelHtml.ts](../../vscode-extension/src/views/panelHtml.ts):
  `renderBar` (~líneas 425-436) — reemplazar el uso de `model.branch` por `model.source` (con
  `model.repoLabel` concatenado igual que hoy), y agregar el tip **abreviado** (primeros 7 caracteres)
  junto a él (research.md Decisión 5: reemplazar, no acumular — la rama no se dibuja más, es derivable
  del origen). En `render()` (~líneas 579-596), rama `model.mode === "whole"`: cuando `model.base` esté
  presente, mostrarlo (p. ej. con el helper `note()`) junto al mensaje existente de "no hay walkthrough
  curado"; cuando esté ausente, el mensaje queda exactamente como hoy — sin hueco ni valor vacío
  (depende de T022)
- [X] T024 [P] [US2] Unitarios nuevos en
  [vscode-extension/test/unit/panelModel.spec.ts](../../vscode-extension/test/unit/panelModel.spec.ts):
  `source`/`tip` presentes en los tres modos (whole/step/walk) siempre que `situation === "review"`;
  `base` presente sólo en whole y sólo cuando `ReviewState.base` está poblado; `base` ausente (no
  vacío) en cualquier otro caso
- [X] T025 [US2] En
  [vscode-extension/preview/fixtures.ts](../../vscode-extension/preview/fixtures.ts): agregar un pane
  `whole-with-base` (fila `state` de modo whole + fila `base`), dejando el pane `whole` existente como
  el caso sin base registrada — los dos costados de FR-009 que quickstart.md §4 pide poder comparar
- [X] T026 [US2] En
  [vscode-extension/test/integration/walkthrough-panel.spec.ts](../../vscode-extension/test/integration/walkthrough-panel.spec.ts),
  extender el test "mode = whole sin walkthrough" (líneas 125-148): afirmar `model.source === branch`,
  `model.tip` definido y coincidente con `state.state?.tip`, y `model.base === "main"` (el fixture
  `createTempRepo()` ya fija `reviewworkflow.base main`, así que `start` lo hereda sin configuración
  adicional) (depende de T017, T022, T023)

**Checkpoint**: US1 y US2 completas — el panel identifica cualquier review sin ambigüedad, en los tres
modos.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: documentación y no-regresión de punta a punta, en los dos artefactos.

- [X] T027 [P] Documentar los registros `subject`, `author` y `base` en la sección `--porcelain
  format` de [README.md](../../README.md) (~líneas 554-587, junto a `state`/`entry`): su forma, en qué
  modo se emiten, la regla de "texto libre siempre último campo, a lo sumo uno por registro" (Decisión
  1) y que un consumidor los lee como "resto de línea desde el n-ésimo tab", no como campo por índice
- [X] T028 [P] Mismo cambio, mismo alcance, en [README.es.md](../../README.es.md) (~líneas 544-600) —
  regla de `CLAUDE.md`: los dos README se actualizan juntos, en el mismo cambio
- [X] T029 Correr
  `shellcheck $(find bin -type f ! -name '.gitkeep') install.sh uninstall.sh web-install.sh web-uninstall.sh bump-version.sh tests/sandbox.sh`
  sobre el estado final y corregir cualquier hallazgo introducido por esta feature
- [X] T030 Correr `./tests/run-docker.sh` (suite completa) y confirmar que toda aserción existente
  sobre la salida humana sigue pasando sin modificarse (Decisión 7 — la salida humana no cambia), y que
  ninguna aserción de `--porcelain` previa a esta feature cambió de valor, sólo se agregaron líneas
  nuevas
- [X] T031 Correr `cd vscode-extension && npm test` (unitarios + integración) y `npm run preview`;
  recorrer [quickstart.md](./quickstart.md) §4-§6 a mano en el Extension Development Host, comparando
  el panel con `git review status` en una terminal al lado, y confirmando que una review de decenas de
  commits no se siente lenta al navegar (SC-008)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: sin dependencias — puede arrancar de inmediato
- **Foundational (Phase 2)**: depende de Setup — bloquea el lado extensión de las dos historias (el
  lado CLI de cada historia no depende de T002)
- **User Stories (Phase 3-4)**: dependen de Foundational; US1 y US2 son independientes entre sí — cada
  una toca su propio registro porcelain y su propia porción del panel, sin que ninguna imponga cambios
  a la otra
- **Polish (Phase 5)**: depende de que las dos historias estén completas

### User Story Dependencies

- **US1 (P1)**: después de Foundational — sin dependencia de US2. Es la historia que cierra el hueco
  real (research.md Decisión 0): sin ella el modo commit por commit sigue necesitando la terminal.
- **US2 (P2)**: después de Foundational — sin dependencia de US1. El origen y el tip no necesitan
  ningún cambio de CLI (ya llegan al panel); sólo la base (T017-T021) depende de un registro nuevo,
  independiente del de US1.

### Within Each User Story

- Lado CLI antes que lado extensión (la extensión no tiene nada que parsear hasta que la CLI lo emite)
- `porcelain.ts` antes que `state.ts` antes que `panelModel.ts` antes que `panelHtml.ts` — cada uno
  consume la capa anterior
- Implementación antes que sus tests de integración (los unitarios de parseo pueden ir en paralelo con
  la implementación de la CLI una vez que el contrato de campos, `data-model.md`, está fijado)
- Historia completa y con checkpoint antes de darla por lista

### Parallel Opportunities

- T005, T006 y T007 en paralelo entre sí una vez que T003-T004 (US1, lado CLI) están: dos archivos de
  test distintos más un archivo de fixture ajeno a los tests automatizados
- T009 en paralelo con la implementación de T003-T007 (lado CLI) una vez fijado el contrato de campos;
  corre en bats/mocha después, pero puede escribirse en paralelo
- T018 en paralelo con el resto de US2 una vez que T017 está
- US1 completa y US2 completa pueden correr en paralelo por dos personas distintas, cada una siguiendo
  su propia secuencia CLI → extensión — no comparten un archivo hasta Polish (README)
- T014 y T024 en paralelo entre sí (archivos de test distintos: `panelModel.spec.ts` es el mismo
  archivo pero secciones distintas de la misma historia, no cruzadas)
- T027/T028 en paralelo entre sí, y ambos en paralelo con T029/T030/T031 una vez que US1 y US2 están
  implementadas

---

## Parallel Example: User Story 1

```bash
# T003, T004 son secuenciales (T004 usa el helper de T003)
# T005, T006, T007 corren en paralelo una vez que T004 emite los registros:
Task: "bats: subject/author records en tests/status-porcelain.bats"
Task: "sandbox.sh: commits con asunto y autor hostiles"
Task: "porcelain-bytes.bats: bytes hostiles no desplazan el registro siguiente"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Completar Phase 1: Setup
2. Completar Phase 2: Foundational
3. Completar Phase 3: US1
4. **Parar y validar**: una review commit por commit muestra asunto y autor en el panel, sin escribir
   ningún comando (SC-001, SC-003 parcial)
5. Es un MVP genuino: cierra el hueco que el spec identifica como el único sin el cual el panel no
   sustituye a la terminal en modo step

### Incremental Delivery

1. Setup + Foundational → base lista
2. US1 → validar independientemente → MVP
3. US2 → validar independientemente (origen, tip y base reconocibles en los tres modos)
4. Polish → README, shellcheck, suite completa, `npm test`, `npm run preview`, quickstart de punta a
   punta

### Parallel Team Strategy

Con dos personas: una completa US1 (lado CLI primero, después extensión), la otra US2 en paralelo — no
hay archivo compartido entre las dos hasta Polish (los dos README). Dentro de cada historia, conviene
mantener CLI → extensión en secuencia, porque cada capa de la extensión depende del contrato que la
capa anterior fija.

---

## Notes

- `[P]` = archivos distintos, o mismo archivo en una sección propia sin dependencia de una tarea sin
  terminar
- La etiqueta de historia asocia cada tarea a su US para trazabilidad
- Cada historia es completable y verificable por sí sola (ver *Independent Test* de cada fase)
- Commitear tras cada tarea o grupo lógico
- Parar en cualquier checkpoint para validar la historia de forma independiente
- Evitar: tareas vagas, conflictos de archivo dentro de un mismo `[P]`, dependencias cruzadas entre
  historias que rompan su independencia
