# Tasks: Listado de archivos del rango en modo whole

**Input**: Design documents from `/specs/004-listado-archivos-whole/`

**Prerequisites**: [plan.md](./plan.md), [research.md](./research.md),
[data-model.md](./data-model.md), [contracts/consolidacion-porcelain.md](./contracts/consolidacion-porcelain.md),
[quickstart.md](./quickstart.md)

**Tests**: la spec (`review con asserts fuertes` en `../../AGENTS.md`) manda tests para
todo comportamiento observable, y `003` fijó el precedente de test-first para
cambios de porcelain — se incluyen.

**Organization**: por historia de usuario. US1 (CLI) es la base de la que dependen
US2 (panel) y — indirectamente — US3 (contrato, que documenta lo que US1 hace). US4
es independiente de las tres: toca sólo `walk` y no depende de que exista el
listado de `whole`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: puede correr en paralelo (archivos distintos, sin dependencia de una
  tarea sin terminar)
- **[Story]**: US1 (listado en la CLI), US2 (panel del editor), US3 (contrato
  consolidado), US4 (el walkthrough entra al orden de lectura de walk)
- Cada tarea nombra el archivo exacto que toca

## Path Conventions

Proyecto único, dos subárboles: `bin/` (CLI, shell POSIX) y `vscode-extension/src`
(la extensión, TypeScript). Tests en `tests/` (bats, vía Docker) y
`vscode-extension/test/` (unit + integración).

---

## Phase 1: Setup

**Purpose**: no hace falta inicialización de proyecto — la CLI y la extensión ya
existen y compilan. Esta fase se reduce a confirmar el punto de partida antes de
tocar código compartido por varias historias.

- [X] T001 Correr `./tests/run-docker.sh status-porcelain.bats walk.bats` y
  `npm test --prefix vscode-extension` en el estado actual del branch, para tener
  una línea base verde antes de invertir ningún test.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: el helper compartido que US1 y US4 consumen. Sin esto, cualquier
implementación de esas dos historias repite la llamada a `changed_paths` con el
riesgo de divergir en el orden de argumentos (research.md Decisión 2).

**⚠️ CRITICAL**: T002 bloquea toda tarea de implementación de US1 y US4. Los tests
de esas historias (que deben escribirse y fallar primero) no dependen de T002.

- [X] T002 Agregar el helper `range_files <tip> <lower>` a
  `bin/git-review-lib.sh`, envolviendo `changed_paths` con el orden de argumentos
  que usan los verbos (`changed_paths "$lower" "$tip"`, ver
  `walk_reading_order` en la misma línea de hoy). Una línea de implementación más
  el comentario que explica por qué existe como wrapper (research.md Decisión 2).

**Checkpoint**: con T002 hecho, US1 y US4 pueden implementarse en paralelo.

---

## Phase 3: User Story 1 - Ver los archivos del PR en una review sin walkthrough (Priority: P1) 🎯 MVP

**Goal**: `git review status` y `git review status --porcelain` listan, en modo
`whole`, los archivos que toca el rango de la review — con éxito y un mensaje
explícito cuando no hay ninguno, y sin agregar cursor ni navegación.

**Independent Test**: en un repo con una review `whole` activa sobre un PR de N
archivos, correr `git review status` y verificar que aparecen los N paths y
coinciden con `git diff --name-only` sobre el mismo rango (quickstart.md § 1).

### Tests for User Story 1 ⚠️

> **Escribir estos tests primero; deben fallar antes de tocar `bin/git-review-verbs/status`.**

- [X] T003 [P] [US1] En `tests/status-porcelain.bats`, invertir el test existente
  `"status --porcelain emits zero entry lines for whole mode without an
  applicable walkthrough"` (línea ~236): sobre un PR con archivos, debe emitir un
  registro `entry` por archivo tocado, con posiciones 1..N y sin campos después
  del path; sobre un PR sin archivos, debe seguir emitiendo cero. Afirmar además
  que el registro `state` sigue sin `position`/`total`/`recorded`/`current`
  (FR-004).
- [X] T004 [P] [US1] Agregado en `tests/status-porcelain.bats` en vez de
  `tests/porcelain-bytes.bats`: ese archivo está documentado (línea 1-16) como
  específico de bytes hostiles en campos de texto libre (`subject`/`author`);
  los tests de paths hostiles (espacios, comillas, no-ASCII) ya viven en
  `status-porcelain.bats`, así que el test nuevo sigue esa convención existente.
  Compara `entry` de whole, ordenado, contra `git diff --name-only
  --core.quotePath=false` sobre el mismo rango, con el mismo guard de
  plataforma que el test de paths con comilla ya usa.
- [X] T005 [P] [US1] Hecho en `tests/extras.bats` en vez de `tests/review.bats`:
  ese archivo (`review status reports a whole review`) ya era el dueño de la
  salida humana de `status` en whole. Se extendió con la aserción de listado
  (`1  f.txt`) y se agregó un `@test` nuevo para el rango vacío (fixture
  add-then-remove, mismo patrón que T003) que afirma el mensaje explícito y
  exit `0`.
- [X] T006 [P] [US1] En `tests/errors.bats`, agregado
  `"review next requires step mode on a whole review, even after listing its
  files"` junto al test ya existente de `prev` — corre `status --porcelain`
  primero (para que la lista se calcule) y confirma que `next` sigue fallando
  con el mismo exit code y mensaje.

### Implementation for User Story 1

- [X] T007 [US1] En `bin/git-review-verbs/status`, rama `whole` de la salida
  `--porcelain` (después de `porcelain_row state ...` en el bloque `case "$mode"`,
  alrededor de la línea 190): emitir un registro `entry` por línea de
  `range_files "$tip" "$(git rev-parse HEAD)"`, numerando desde 1. Depende de T002.
- [X] T008 [US1] En `bin/git-review-verbs/status`, rama `whole` de la salida humana
  (después de `printf '  mode    whole%s\n' ...`, línea ~293): listar los archivos
  de `range_files` con su posición, uno por línea; si la lista está vacía, imprimir
  una línea que lo diga explícitamente en vez de omitir la sección. Depende de T002.
- [X] T009 [US1] `shellcheck` limpio sobre `bin/git-review-verbs/status` y
  `bin/git-review-lib.sh` (vía Docker). `./tests/run-docker.sh` sobre
  status-porcelain.bats, extras.bats, errors.bats, walk.bats, step.bats,
  review.bats y compare.bats: 216/216 en verde, incluidas T003-T006.

**Checkpoint**: `whole` lista sus archivos por las dos salidas, sin cursor. US1 es
demostrable de punta a punta sin que exista la extensión.

---

## Phase 4: User Story 4 - El walkthrough también es contenido revisable (Priority: P2)

**Goal**: el orden de lectura de `walk` y las listas de archivos sin cubrir al
degradar dejan de filtrar `.review/`; el generador de entradas de `walkthrough
build` sigue sin proponerlo.

**Independent Test**: en una review `walk` sobre un PR que commitea un
walkthrough, el total del orden de lectura incluye `.review/walkthrough.md` y
`next` termina parando en él (quickstart.md § 3).

**Nota de secuencia**: esta historia es independiente de US1/US2/US3 en el sentido
de que no depende de que exista el listado de `whole` — pero comparte T002 y toca
el mismo helper y el mismo archivo de lib que la Foundational phase, así que
conviene implementarla después de T002 y antes de tocar la extensión, para no
tener dos ramas editando `git-review-lib.sh` en paralelo.

### Tests for User Story 4 ⚠️

> **Escribir primero; deben fallar contra el filtro actual.**

- [X] T010 [P] [US4] `tests/walk.bats`: `"the committed walkthrough itself is
  the last entry, uncovered, in --porcelain"` — total cuenta el sidecar,
  `annotated=0`.
- [X] T011 [P] [US4] `tests/walk.bats`: `"next walks all the way through the
  sidecar before reporting the end"`.
- [X] T012 [P] [US4] `tests/walk.bats`: `"a walk review opened before this
  feature (walkcount predates the sidecar entry) reaches it without error"`
  (FR-023).
- [X] T013 [P] [US4] `tests/walkthrough.bats`: `"build's drift check never
  flags the committed sidecar itself as missing (FR-022)"` — complementa el
  test ya existente de `init` con uno equivalente para `build --check`.
- [X] T014 [P] [US4] `tests/walk.bats`: **redefinido tras encontrar una tensión de
  diseño real.** El texto original de FR-024 pedía modo `walk` forzado para un PR
  que sólo toca `.review/`; eso choca con el gate existente `guidedcount -ge 1`
  (correcto para el caso general, cubierto por el test ya existente "a walkthrough
  whose entries do not intersect the range falls back to whole with a note") — un
  walkthrough estructuralmente NUNCA puede anotarse a sí mismo, así que ese PR
  siempre tiene `guidedcount=0`. Forzar `walk` ahí exigía una regla especial sin
  justificación sólida. Como US1 ya resuelve el problema real (el archivo nunca
  queda invisible: `whole` lo lista), el test quedó como
  `"a PR that only touches the sidecar degrades to whole but is never invisible
  there (FR-024)"`, afirmando degradación con nota + listado en `whole`, sin
  tocar el gate de `start.sh`. Ver decisión registrada más abajo.
- [X] T015 [P] [US4] `tests/walk.bats`: dos tests —
  `"start notes range files not covered..."` (ya existente, extendido) cubre el
  lado de `start`; se agregó `"compare degrades with a note naming the sidecar
  when only it changed in range (T015)"` para el lado de `compare`, que no tenía
  equivalente.

### Implementation for User Story 4

- [X] T016 [US4] `bin/git-review-lib.sh`: `walk_reading_order` usa `range_files`
  (T002) en vez de `changed_paths` + `grep -v`. Coincide el orden de argumentos.
- [X] T017 [P] [US4] `bin/git-review-verbs/start`: `degradedfiles` usa
  `range_files "$tip" "$lower"`.
- [X] T018 [P] [US4] `bin/git-review-verbs/compare`: `degradedfiles` usa
  `range_files "$bcommit" "$acommit"`.
- [X] T019 [US4] `bin/git-review-verbs/walkthrough` conserva su filtro, **pero se
  renombró** de `range_files()` a `annotatable_files()`: el verbo ya sourcea
  `git-review-lib.sh` (que ahora también define `range_files`, sin filtro), y el
  nombre compartido shadowaba silenciosamente uno de los dos según orden de
  definición — un bug real que T002 introdujo sin que ninguna tarea lo previera.
  Actualizadas las 3 llamadas y el comentario que lo explicaba por nombre viejo.
- [X] T020 [US4] `shellcheck` limpio (los 4 archivos + pase completo estilo CI).
  `./tests/run-docker.sh` completo: **560/560 en verde**, cero regresiones.
  La onda expansiva fue mayor a la anticipada: además de `walk.bats` (43→48
  tests, todas las reviews `walk` existentes ganan +1 en el total porque el
  fixture compartido commitea el walkthrough dentro del rango revisado), también
  afectó 6 tests en `status-porcelain.bats` (su propio fixture walk, vía
  `recommit_walkthrough`) y 1 en `compare.bats` — ninguno estaba en el radar de
  T010-T015 porque viven fuera de `walk.bats`. Todos corregidos con el mismo
  criterio: el sidecar se ordena antes que cualquier archivo que empiece con una
  letra (`.` < cualquier ASCII imprimible salvo otro `.`), así que aparece
  primero entre los no cubiertos cuando hay más de uno.

**Checkpoint**: ningún archivo del PR queda invisible en ninguna de las dos
superficies de listado de `walk`; el generador de entradas sigue sin circularidad.

---

## Phase 5: User Story 2 - Abrir esos archivos desde el panel del editor (Priority: P2)

**Goal**: el panel de VS Code muestra la lista de archivos de una review `whole`
con su conteo y abre cualquiera con un clic, sin cursor ni controles de
navegación.

**Independent Test**: abrir en el editor un repo con una review `whole` activa y
verificar que el panel lista los archivos del rango y que un clic abre el
correcto, incluidos paths con espacios y acentos (quickstart.md § 5).

**Depende de**: US1 completa (T007-T009) — el panel no puede mostrar un registro
que la CLI no emite todavía.

### Tests for User Story 2 ⚠️

> **Escribir primero.**

- [X] T021 [P] [US2] `porcelain.spec.ts`: nuevo caso — `entry` en whole trae
  posición + path, id como `PathRef`, sin essential/annotated/banked.
- [X] T022 [P] [US2] `panelModel.spec.ts`: 3 casos nuevos — `files` con N
  elementos en whole, vacío (no ausente) fuera de whole, sin cursor. También se
  corrigió el comentario de un test existente que decía "whole nunca tuvo
  entry" (ya no es cierto).
- [X] T023 [P] [US2] `panelHtml.spec.ts`: 3 casos nuevos — el mensaje fijo de
  "sin walkthrough" ya no es incondicional, el rango vacío tiene su propio
  mensaje explícito, whole no dibuja `renderNavRow`.
- [X] T024 [P] [US2] `open-entry.spec.ts`: 2 casos nuevos — abrir una entrada de
  la lista de whole (con path no-ASCII y espacios), y caída a diff para un
  archivo eliminado en el rango, en whole.
- [X] T025 [P] [US2] `empty-states.spec.ts`: caso nuevo — whole con rango vacío
  (commits que se cancelan), `model.files` y `entryCount` en cero, sin lista
  rota.

### Implementation for User Story 2

- [X] T026 [US2] `porcelain.ts`: `entry.id` es `PathRef` cuando el modo NO es
  step (antes: sólo cuando era walk) — la regla quedó "SHA sólo en step" en vez
  de "PathRef sólo en walk".
- [X] T027 [US2] `panelModel.ts`: campo `files: PanelEntry[]` (no opcional —
  siempre `[]` por default, poblado en whole).
- [X] T028 [US2] `panelHtml.ts`: función `renderFiles(model)` reemplaza el
  mensaje incondicional; lista con conteo si hay archivos, mensaje explícito de
  rango vacío si no. CSS `.files`/`.file-row` agregado.
- [X] T029 [US2] `extension.ts`: `handlePanelMessage` resuelve `openEntry`/
  `openChange` por `position` cuando el mensaje trae un `index` numérico (antes
  sólo `continueReview` usaba `index`) — reusa `currentEntry`, ya importado.
  Actualizado `contracts/extension-surface.md` (doc de la feature `002`), que
  documentaba `index` como exclusivo de `continueReview`.
- [X] T030 [US2] `pickEntry.ts`: título por modo vía `Record<ReviewMode,
  string>` — "Files in this review" para whole. Confirmado que `goToEntry` no
  tenía guard de modo (sólo `entries.length === 0`), así que ya funciona en
  whole sin más cambios; sólo el título estaba mal.
- [X] T031 [P] [US2] `fixtures.ts`: los dos estados `whole`/`whole-with-base`
  ganaron registros `entry` (3 archivos); se agregó un tercer estado
  `whole-empty` para el rango vacío (14→15 estados totales — la cifra "nueve
  estados" de `../../AGENTS.md` ya estaba desactualizada antes de este cambio, no se
  tocó). Verificado visualmente con el navegador: las tres tarjetas renderizan
  correctamente.
- [X] T032 [US2] `npm run compile` limpio. `npm run test:unit`: 142/142.
  `npm run test:integration`: 32/32 (subió de 27, ver nota abajo) — spinea un
  VS Code real vía `@vscode/test-electron`, ~8 min.
  **Onda expansiva no anticipada por T021-T025**: igual que en la suite bats,
  `walkthrough-panel.spec.ts` (3 tests) y `navigate.spec.ts` (2 tests) tenían
  fixtures con walkthrough commiteado y totales/posiciones hardcodeados que
  ahora son +1. Corregidos con el mismo criterio de orden que en bats. Un test
  de `navigate.spec.ts` además navegaba a la entrada del propio walkthrough vía
  el comando de la extensión, que encadena un `openChange` automático sobre un
  `.md` — se cambió esa navegación puntual a invocar la CLI directo (evita
  depender de cómo el editor abre el diff de un Markdown) y se subió el timeout
  del describe de 60s a 120s (una corrida cargada, no un cuelgue real: en
  verde reproducido dos veces).

**Checkpoint**: una review `whole` en el panel pasa de una vista vacía a N
archivos clickeables, sin cursor. US1 + US2 juntas cubren el pedido original de
principio a fin.

---

## Phase 6: User Story 3 - Un solo contrato de porcelain, sin versiones paralelas (Priority: P3)

**Goal**: `specs/001-contrato-porcelain/contracts/status-porcelain.md` queda como
el único documento vigente del formato porcelain de `status`, absorbiendo el
delta de `003` y corrigiendo la afirmación que US1 vuelve falsa; el archivo `v2`
se elimina.

**Independent Test**: `grep -ri "porcelain[- ]v2\|status-porcelain-v2" .` no
devuelve nada, y el contrato consolidado se lee completo sin remitir a otro
archivo (quickstart.md § 6).

**Depende de**: el contenido final de US1 y US4 (para documentar el registro
`entry` de `whole` y la inclusión de `.review/` correctamente) y del plan de
consolidación en [contracts/consolidacion-porcelain.md](./contracts/consolidacion-porcelain.md).
Puede escribirse en paralelo a US2 una vez que US1 y US4 están implementadas.

### Tests for User Story 3

No aplica test de comportamiento — US3 es documental (FR-015 a FR-019 no tocan
código ejecutable). La verificación es el propio criterio de aceptación:

- [X] T033 [US3] `tests/test-names.bats`: 2/2 en verde. Sin archivos de `@test`
  renombrados en esta feature (sólo se eliminó `status-porcelain-v2.md`, que no
  tenía tests propios).

### Implementation for User Story 3

- [X] T034 [US3] `001-contrato-porcelain/contracts/status-porcelain.md`:
  absorbida la regla del texto libre y los registros `subject`/`author`/`base`
  (sección nueva "Registros subject, author y base"), y la tabla de
  exclusiones al final del documento.
- [X] T035 [US3] Misma línea reemplazada por la regla de tres modos; agregada
  la fila `whole` a la explicación de `id`; sección de paths extendida a los
  tres modos.
- [X] T036 [US3] Documentado en la descripción de `annotated`: el sidecar entra
  en esa categoría igual que cualquier otro archivo sin anotar.
- [X] T037 [US3] `status-porcelain-v2.md` eliminado (`git rm`, registrado como
  `D` en `git status`).
- [X] T038 [P] [US3] Las 7 referencias reapuntadas: 2 en código
  (`bin/git-review-verbs/status:148`, `porcelain.ts:45`, ahora comentarios sin
  link roto) y 4 en los docs históricos de `003` (`tasks.md` ×2, `quickstart.md`,
  `plan.md`, `data-model.md`), todas repuntando a
  `001-contrato-porcelain/contracts/status-porcelain.md` sin reescribir el
  relato de la feature cerrada.
- [X] T039 [US3] `README.md`: tabla de `entry` actualizada para los tres modos;
  descripción de `git review status` menciona el listado de whole; sección de
  walk mode menciona que el sidecar entra en la cola sin anotar.
- [X] T040 [US3] Mismos tres cambios aplicados a `README.es.md`, en el mismo
  commit.
- [X] T041 [US3] `grep -rli "porcelain[- ]v2\|status-porcelain-v2"` desde la
  raíz: sólo 2 resultados, ambos dentro de `specs/003-paridad-cli-panel/`
  (`plan.md`, `tasks.md`) mencionando el nombre de archivo viejo en tiempo
  pasado ("antes en…", ver T038) — no una reivindicación de que el formato
  tenga una v2. `specs/004-listado-archivos-whole/` (esta feature) queda
  fuera del filtro a propósito: sus propios documentos de planificación
  necesitan nombrar la cadena para describir el trabajo y el propio criterio
  de SC-005.

**Checkpoint**: un lector nuevo encuentra el contrato completo en un solo
documento, y ningún archivo del repositorio menciona una versión de porcelain
distinta de v1.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: validación de punta a punta y limpieza que toca más de una historia.

- [X] T042 [P] `./tests/sandbox.sh -d /tmp/sandbox-004` + verificación manual
  contra el sandbox real (no sólo los tests). **Encontró un hallazgo real**: el
  texto fijo que `sandbox.sh` imprime al terminar ya decía "5 walkthrough
  entries... la última es el propio walkthrough" para `feature/checkout` — una
  cifra que no coincidía con la implementación real (6, no 5: 5 guiadas + el
  sidecar sin anotar). Verificado con `git review status --porcelain` contra el
  sandbox reconstruido: total real 6 en walk, 4 en step (sin cambios, cuenta
  commits). Mismo problema en `feature/notifications` (5 reales, no 4) y en la
  posición guardada de `feature/search` (2/3, no 2/2). Los tres corregidos en
  `tests/sandbox.sh`, reconstruido y vuelto a verificar a mano — incluida una
  corrida completa de `feature/telemetry` (whole) confirmando el listado de
  US1 de punta a punta: `files 2` + los dos paths, y los mismos dos como
  `entry` en `--porcelain`. Sandboxes de verificación borrados al terminar.
- [X] T043 [P] `shellcheck` sobre la lista completa de CI, incluido
  `tests/sandbox.sh` después de editarlo: limpio.
- [X] T044 `./tests/run-docker.sh`: 560/560. `npm test --prefix
  vscode-extension`: 142 unit + 32 integración, todas en verde. Sin
  regresiones fuera de las inversiones deliberadas de T003/T010 y el ripple
  documentado en T020/T032.
- [X] T045 Verificado (no asumido): `docs/index.html` no menciona el conteo de
  archivos ni la mecánica interna de `whole`/`walk` en ninguna de sus cuatro
  superficies duplicadas — la tabla comparativa compara contra herramientas
  externas, no describe el porcelain. No requiere cambios.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: sin dependencias.
- **Foundational (Phase 2)**: depende de Setup. Bloquea la implementación de US1
  y US4 (no sus tests).
- **US1 (Phase 3)**: tests sin dependencias; implementación depende de T002.
- **US4 (Phase 4)**: tests sin dependencias; implementación depende de T002.
  Independiente de US1 en el sentido de spec, pero comparte archivo de lib —
  conviene secuenciarla justo después de US1 para no pisar `git-review-lib.sh`
  con dos ramas de trabajo a la vez.
- **US2 (Phase 5)**: depende de US1 completa (T007-T009). Independiente de US4.
- **US3 (Phase 6)**: depende del contenido final de US1 y US4 (documenta ambas).
  Puede correr en paralelo a US2.
- **Polish (Phase 7)**: depende de todas las historias que se vayan a incluir.

### User Story Dependencies

- **US1 (P1)**: sin dependencia de otra historia. Es el MVP.
- **US4 (P2)**: sin dependencia de US1 ni de US2, más allá del helper compartido
  de Foundational.
- **US2 (P2)**: depende de US1.
- **US3 (P3)**: depende de US1 y US4 (documenta lo que ambas implementan).

### Parallel Opportunities

- T003-T006 (tests de US1) en paralelo entre sí, antes de T007.
- T010-T015 (tests de US4) en paralelo entre sí, antes de T016.
- T017 y T018 en paralelo (archivos distintos).
- T021-T025 (tests de US2) en paralelo entre sí, antes de T026.
- Con dos personas: una puede tomar US1+US2 mientras la otra toma US4, después de
  que T002 esté hecho; US3 empieza cuando ambas ramas terminan.
- T038 (siete referencias) es paralelizable internamente: son archivos distintos.

---

## Parallel Example: User Story 1

```bash
# Tests de US1, en paralelo (archivos distintos, sin dependencia entre sí):
Task: "Invertir el test de zero entry lines en tests/status-porcelain.bats"
Task: "Agregar test de paths hostiles en whole en tests/porcelain-bytes.bats"
Task: "Agregar tests de salida humana en tests/review.bats"
Task: "Confirmar rechazo de next/prev en tests/errors.bats"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: Setup (T001).
2. Phase 2: Foundational (T002) — bloquea la implementación, no los tests.
3. Phase 3: User Story 1 completa (T003-T009).
4. **Parar y validar**: correr quickstart.md § 1 y § 2 contra el sandbox.
5. Esto ya es demostrable end-to-end desde la terminal, sin la extensión.

### Incremental Delivery

1. Setup + Foundational → helper listo.
2. US1 → CLI lista archivos en whole → validar → esto es el MVP.
3. US4 → walk deja de esconder el sidecar → validar independientemente de US1.
4. US2 → el panel se vuelve accionable → validar (depende de US1 hecha).
5. US3 → el contrato queda consolidado → validar con el grep de SC-005.
6. Polish → sandbox completo + suites completas.

### Parallel Team Strategy

Con dos personas, después de T002:

- Persona A: US1 (Phase 3) → luego US2 (Phase 5), que depende de su propio US1.
- Persona B: US4 (Phase 4) en paralelo, sin esperar a US1.
- Cualquiera de las dos: US3 (Phase 6) una vez que US1 y US4 están mergeadas.

---

## Notes

- [P] = archivos distintos, sin dependencia entre sí.
- El helper `range_files` (T002) es la única pieza verdaderamente compartida
  entre historias; todo lo demás sigue la regla de "la CLI calcula, la extensión
  proyecta".
- T019 es una tarea de "no tocar, pero dejar dicho por qué": la ausencia de
  cambio en `walkthrough` (generador de entradas) es una decisión de diseño
  (FR-022), no un olvido, y merece quedar señalada donde alguien la vuelva a
  encontrar.
- Confirmar que cada test nuevo falla antes de la implementación correspondiente
  (T003-T006 antes de T007-T008; T010-T015 antes de T016-T018; T021-T025 antes de
  T026-T029).
- No hacer commit por tarea suelta si eso rompe `set -eu`/`shellcheck` a mitad de
  camino: agrupar T002 con T007-T008 si el checkout no tolera un commit
  intermedio con una función sin uso — usar criterio, la regla dura es no dejar
  el checkout roto en ningún commit.
