---

description: "Task list template for feature implementation"
---

# Tasks: Contrato de salida legible por programas

**Input**: Design documents from `/specs/001-contrato-porcelain/`

**Prerequisites
**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: Incluidos. No los pide explícitamente el spec, pero son la práctica
estándar ya vigente en el repo (cada verbo tiene cobertura bats con asserts
fuertes — regla de `../../AGENTS.md`); tratarlos como opcionales acá sería una
excepción sin justificación. Los tests nuevos van a `tests/status-porcelain.bats`
(archivo nuevo) y a `tests/list.bats` / `tests/errors.bats` (existentes).
**Los nombres de `@test` van en ASCII puro** —sin acentos, sin `ñ`, sin em
dashes— aunque el resto de estos documentos esté en español: bats convierte
cada nombre en nombre de función y el bats de Windows en CI se rompe con los
bytes UTF-8. Es sólo el nombre; el cuerpo del test puede tener lo que sea.

**Organization**: Tareas agrupadas por historia de usuario (US1..US6, en el
orden y prioridad de `spec.md`), para poder implementar y probar cada una de
forma independiente.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Puede correr en paralelo (archivos distintos, sin dependencias)
- **[Story]**: A qué historia de usuario pertenece (US1..US6)
- Cada tarea incluye la ruta exacta de archivo
- Las tareas T030+ se agregaron después del primer `/speckit-analyze` y viven en
  la fase que les corresponde, no al final. El **orden de ejecución lo da la
  fase**, no el número: los IDs nunca se renumeran, para que no cambien de
  significado entre lecturas

## Path Conventions

Proyecto único (CLI de shell POSIX), sin nuevos directorios: `bin/` para los
verbos y el helper compartido, `tests/` para bats. Ver "Project Structure" en
[plan.md](./plan.md).

---

## Phase 1: Setup

**Purpose**: Confirmar el punto de partida antes de tocar nada, para poder
demostrar después que la feature no regresó nada (SC-008).

- [X] T001 Correr la línea base actual sin cambios:
  `shellcheck $(find bin -type f ! -name '.gitkeep') install.sh uninstall.sh web-install.sh web-uninstall.sh bump-version.sh`
  y `./tests/run-docker.sh`; confirmar ambos en verde antes de empezar

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: La única pieza que usan *todas* las historias: el formato de
línea porcelain en sí (etiqueta + campos separados por tab, contrato de
`contracts/status-porcelain.md` y `contracts/list-porcelain.md`).

**⚠️ CRITICAL**: Ninguna historia puede escribir una línea porcelain real
antes de esto.

- [X] T002 Agregar el helper `porcelain_row` a [bin/git-review-lib.sh](../../bin/git-review-lib.sh):
  recibe los campos de un registro como argumentos y los imprime en una sola línea separados por
  tab (`IFS`/`printf`, sin depender de bashisms); es el único punto que **escribe** una línea
  porcelain — `state`, `entry`, `uncovered` (en `status`) y `branch` (en `list`) salen todas por
  acá. Los helpers de derivación (T010) producen campos, no líneas: quien los emite los pasa por
  `porcelain_row`. Un campo que no aplica se **omite** de la llamada, nunca se pasa vacío (
  `data-model.md`: omitir, nunca vaciar, nunca rellenar con centinela)

**Checkpoint**: helper listo — las historias de usuario pueden empezar.

---

## Phase 3: User Story 1 - Leer el estado de la review actual (Priority: P1) 🎯 MVP

**Goal**: `git review status --porcelain` imprime una línea `state` con los
campos correctos para los tres modos (whole/step/walk), sin alterar la salida
humana existente.

**Independent Test**: iniciar una review en cada uno de los tres modos y
verificar que `status --porcelain` devuelve los campos y valores exactos de
`contracts/status-porcelain.md`, sin depender de ninguna otra historia.

### Implementation for User Story 1

- [X] T003 [US1] Agregar guarda explícita de "no es un repositorio git" (`git rev-parse --git-dir`)
  al inicio de [bin/git-review-verbs/status](../../bin/git-review-verbs/status), igual a la que ya
  tiene [bin/git-review-verbs/list](../../bin/git-review-verbs/list)
- [X] T004 [US1] Agregar parseo del flag `--porcelain` y actualizar `usage()`
  en [bin/git-review-verbs/status](../../bin/git-review-verbs/status), bifurcando a una ruta
  porcelain nueva antes de los `printf` de salida humana existentes
- [X] T005 [US1] Implementar el registro `state` para modo whole en la ruta porcelain
  de [bin/git-review-verbs/status](../../bin/git-review-verbs/status):
  `state<TAB>branch<TAB>source<TAB>tip<TAB>mode<TAB>walkthrough`, derivando `walkthrough` (`none`/
  `applied`/`degraded`) con `walk_read "$tip"` + `walk_sequence "$tip" "$(git rev-parse HEAD)"` (
  research.md, Decisión 4 — HEAD ya es el lower bound en reposo, sin recalcular nada más)
- [X] T006 [US1] Extender el registro `state` para modo step con `position`/`total`/`recorded`/
  `current` (SHA corto), reusando `load_step_review_meta`
  de [bin/git-review-lib.sh](../../bin/git-review-lib.sh): `total` es el derivado con `rev-list` (el
  mismo que valida el rango), `recorded` es `reviewcount` (Decisión 6). `walkthrough` vale siempre
  `none` en step — no se omite, el registro es posicional (Decisión 4)
- [X] T007 [US1] Extender el registro `state` para modo walk con `position`/`total`/`recorded`/
  `current`/`essential`, reusando `load_walk_review_meta` y `walk_is_key`
  de [bin/git-review-lib.sh](../../bin/git-review-lib.sh): `total` es el largo de la secuencia
  derivada (idéntico a la cantidad de líneas `entry` que emite T011), `recorded` es
  `reviewwalkcount` — ojo que la ruta humana imprime hoy `${walkcount:-$total}`, que es `recorded`,
  no `total`
- [X] T008 [P] [US1] bats: tests de salida exacta para la línea `state` en modo whole/step/walk en
  tests/status-porcelain.bats (archivo nuevo; nombres de `@test` en ASCII puro — regla de
  `../../AGENTS.md`), incluido un caso donde `total` ≠ `recorded` con el cursor todavía en rango
- [X] T009 [US1] bats: test de no-regresión — reescribir un mensaje humano de `status` y verificar
  que la salida de `--porcelain` no cambia un solo byte (FR-003/SC-004) en
  tests/status-porcelain.bats

**Checkpoint**: US1 completa y verificable por sí sola.

---

## Phase 4: User Story 2 - Obtener la secuencia de lectura completa (Priority: P2)

**Goal**: `status --porcelain` también emite líneas `entry` (una por posición
de la secuencia), en walk **y** en step por igual (Q2 = C).

**Independent Test**: crear un walkthrough con entradas conocidas —algunas
fuera del rango de la review, alguna marcada esencial— iniciar la review y
verificar que la secuencia devuelta trae exactamente las entradas esperadas,
en el orden esperado.

### Implementation for User Story 2

- [X] T010 [US2] Agregar el helper `walk_entries_with_essential`
  a [bin/git-review-lib.sh](../../bin/git-review-lib.sh): lee el walkthrough **una sola vez** (
  extendiendo el patrón de una-lectura de `walk_count_keys`) y produce los campos `position`, `path`
  y `essential` de cada path de una secuencia dada — el requisito de performance O(1) en lecturas de
  `research.md`. Produce campos, no líneas terminadas: el emisor (T011) los pasa por
  `porcelain_row` (T002)
- [X] T011 [US2] Emitir líneas `entry` para modo walk en la ruta porcelain
  de [bin/git-review-verbs/status](../../bin/git-review-verbs/status), usando el helper de T010; la
  cantidad de líneas emitidas debe ser exactamente el `total` que reporta el registro `state` (T007)
- [X] T012 [US2] Emitir líneas `entry` para modo step (`position`, `shortsha`, `banked`) en la ruta
  porcelain, reusando el bucle de verificación de `refs/review-edits/<src>/<i>` que ya existe en la
  ruta humana de `status`; recorrer el `total` derivado con `rev-list`, no el `reviewcount`
  persistido que usa hoy ese bucle (Decisión 6), para que la cantidad de líneas coincida con
  `state.total`
- [X] T013 [P] [US2] bats: la secuencia excluye entradas fuera de rango, incluye la marca
  `essential` correcta, y paths no-ASCII salen literales e idénticos a los que reporta git (SC-006)
  en tests/status-porcelain.bats
- [X] T014 [P] [US2] bats: modo whole sin walkthrough aplicable → cero líneas `entry`, exit 0, sin
  reportarse como error en tests/status-porcelain.bats
- [X] T030 [P] [US2] bats: un walkthrough con BOM UTF-8 y otro con finales de línea CRLF producen la
  **misma** secuencia, byte a byte, que su equivalente ASCII limpio (SC-006 nombra las tres cosas;
  T013 sólo cubre no-ASCII) en tests/status-porcelain.bats
- [X] T031 [P] [US2] bats: paths con espacios salen enteros en su campo (los límites los marca el
  tab, no el espacio) y un path con `"` o `\` sale citado por git tal cual, sin desarmar (
  FR-015/FR-016 y la sección *Paths* de `contracts/status-porcelain.md`) en
  tests/status-porcelain.bats

**Checkpoint**: la secuencia completa es navegable por programas, en ambos modos con cursor.

---

## Phase 5: User Story 3 - Distinguir "no hay review" de "algo se rompió" (Priority: P2)

**Goal**: cuatro códigos de salida estables y distinguibles — `0` éxito, `1`
error, `2` "no hay review activa", `3` "el cursor quedó fuera de rango porque
HEAD se movió de la base" — aplicados en **toda la CLI**, no sólo bajo
`--porcelain` ni sólo en `status` (research.md, Decisión 5; FR-017, FR-023).

**Independent Test**: invocar `status` en un repo sin review activa, con una
review sana, con metadata deliberadamente corrupta y con la base movida bajo
una review walk; verificar que cada situación produce un código de salida
distinto y estable, y el mismo desde cualquier verbo que la detecte.

### Implementation for User Story 3

- [X] T015 [US3] Cambiar a `2` el exit de "not on a review/\* branch" en los siete puntos que hoy lo
  emiten con `1`: [bin/git-review-lib.sh](../../bin/git-review-lib.sh) `load_step_review_meta` (~
  L39) y `load_walk_review_meta` (~L411), y los
  verbos [abort](../../bin/git-review-verbs/abort), [finish](../../bin/git-review-verbs/finish), [preview](../../bin/git-review-verbs/preview), [save](../../bin/git-review-verbs/save)
  y [status](../../bin/git-review-verbs/status). Ningún mensaje cambia: cambia el código con el que
  se sale después de imprimirlo. Mantener `1` para metadata ausente o corrupta y para "no es un
  repositorio git" (T003)
- [X] T032 [US3] Cambiar a `3` el exit de la rama de drift de `walk_range_error`
  en [bin/git-review-lib.sh](../../bin/git-review-lib.sh) (~L380) — la que ya detecta que el total
  vigente cayó por debajo de `reviewwalkcount` y emite el diagnóstico accionable. La otra rama de la
  misma función (corrupción genuina, HEAD en la base) se queda en `1`. Alcanza a `status`, `next` y
  `prev` sin tocarlos: los tres pasan por ese helper. No tocar `load_step_review_meta`/`goto_step`:
  en step no hay drift, HEAD avanza por diseño
- [X] T033 [US3] Actualizar las dos aserciones de exit code alcanzadas por
  T032: [tests/walk.bats:194](../../tests/walk.bats) (`next` tras el drift)
  y [tests/walk.bats:201](../../tests/walk.bats) (`status` tras el drift), de `-eq 1` a `-eq 3`,
  anotando en cada una el requisito que las cambia (FR-023). No tocar ningún
  `[[ "$output" == ... ]]` ni [tests/walk.bats:220](../../tests/walk.bats), que fija la corrupción
  genuina en `1` y es justamente la prueba de que las dos ramas siguen separadas (SC-008)
- [X] T016 [P] [US3] bats: fuera de una rama de review → exit exactamente `2`; rama `review/*` hecha
  a mano sin metadata → exit exactamente `1`; fuera de un repositorio git → exit exactamente `1`;
  base movida bajo una review walk → exit exactamente `3` desde `status` **y** desde `next` (
  extender tests/errors.bats, que hoy sólo fija `-ne 0`)

**Checkpoint**: las cuatro situaciones de US3 son distinguibles por código, sin inspeccionar texto,
y devuelven lo mismo desde cualquier verbo.

---

## Phase 6: User Story 4 - Obtener el porqué de una entrada (Priority: P3)

**Goal**: `status --why <path>` vuelca sólo el texto explicativo de una
entrada, sin marcadores reservados, separado por completo de la obtención de
la secuencia (FR-014).

**Independent Test**: pedir el porqué de entradas conocidas y verificar que el
texto sale completo, sin marcadores, y vacío para una entrada sin cuerpo.

### Implementation for User Story 4

- [X] T017 [US4] Agregar parseo del flag `--why <path>` y actualizar `usage()`
  en [bin/git-review-verbs/status](../../bin/git-review-verbs/status) (mutuamente excluyente con
  `--porcelain`)
- [X] T018 [US4] Implementar la salida de `--why`: exigir modo walk (si no, exit 1 con diagnóstico),
  resolver `<path>` contra la secuencia actual (si no está, exit 1 con diagnóstico), e imprimir
  `walk_why "$tip" "$path"` tal cual y nada más
- [X] T019 [P] [US4] bats: texto multilínea preservado verbatim, marcadores `> key`/`> at:` ausentes
  del resultado, cuerpo vacío → stdout vacío con exit 0, path desconocido → exit 1 con diagnóstico
  en stderr, modo no-walk → exit 1 con diagnóstico en stderr, en tests/status-porcelain.bats

**Checkpoint**: el porqué de cualquier entrada es consultable sin transferir el resto de la
secuencia.

---

## Phase 7: User Story 5 - Saber qué archivos no están cubiertos (Priority: P3)

**Goal**: `status --porcelain` emite líneas `uncovered`, uno por path que
cambia en el rango y no tiene entrada en el walkthrough.

**Independent Test**: una review cuyo rango incluya archivos deliberadamente
ausentes del walkthrough; verificar que se reportan todos y sólo ésos.

### Implementation for User Story 5

- [X] T020 [US5] Emitir líneas `uncovered` en la ruta porcelain
  de [bin/git-review-verbs/status](../../bin/git-review-verbs/status) para modo walk (y whole
  degradado), reusando `changed_paths "$lower" "$tip"` menos los paths ya parseados del
  walkthrough — el mismo cálculo que `start` ya hace inline para su nota
- [X] T021 [P] [US5] bats: exactamente los paths deliberadamente no cubiertos se reportan cuando
  existen; cero líneas `uncovered` cuando el walkthrough cubre todo el rango, en
  tests/status-porcelain.bats

**Checkpoint**: los huecos de cobertura son consultables sin re-derivar nada del lado del
consumidor.

---

## Phase 8: User Story 6 - Inventario de reviews abiertas (Priority: P4)

**Goal**: `git review list --porcelain` enumera todas las reviews (activas y
guardadas) con su modo y posición.

**Independent Test**: crear varias reviews en distintos modos, pausar alguna,
y verificar que el inventario las lista todas con su estado, marcando cuál es
la actual.

### Implementation for User Story 6

- [X] T022 [US6] Agregar parseo del flag `--porcelain` y actualizar `usage()`
  en [bin/git-review-verbs/list](../../bin/git-review-verbs/list)
- [X] T023 [US6] Emitir líneas `branch` para ramas activas `review/*` (`name`/`saved=0`/`current`/
  `orphan`/`mode`/`position`/`total`) en la ruta porcelain, reusando la lógica ya existente en
  `describe()`: `position`/`total` salen de la **config** de cada rama (`reviewstep`/`reviewcount`,
  `reviewwalkstep`/`reviewwalkcount`), sin re-derivar la secuencia (Decisión 7). Donde `describe()`
  humano rellena con `?`, la ruta porcelain **omite los dos campos** — el contrato no admite
  centinelas no numéricos
- [X] T024 [US6] Emitir líneas `branch` para ramas guardadas `review-saved/*` (`saved=1`) en la
  misma ruta porcelain
- [X] T025 [P] [US6] bats: dos reviews activas (una step, una walk) más una guardada, todas listadas
  con los campos correctos; una rama huérfana aparece con `orphan=1` en vez de omitirse; una rama
  con `reviewsource` pero sin `reviewcount` sale sin `position`/`total` y sin ningún `?`;
  repositorio sin reviews → exit 0, cero líneas, en tests/list.bats (archivo existente)

**Checkpoint**: el inventario completo está disponible para programas.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: documentación, no-regresión y validación de punta a punta.

- [X] T034 [P] bats: **cero mutación** (FR-022) — snapshot de
  `git config --get-regexp 'branch\..*\.review'`, de `git status --porcelain` (el de git) y de
  `git for-each-ref refs/review-edits/` antes y después de correr `status --porcelain`,
  `status --why` y `list --porcelain`; los tres idénticos, en los tres modos, en
  tests/status-porcelain.bats
- [X] T035 [P] bats: **canales separados** (FR-019) — capturar stdout y stderr por separado y
  verificar que ninguna línea porcelain sale por stderr y que ningún diagnóstico o nota informativa
  sale por stdout, en tests/status-porcelain.bats
- [X] T036 [P] bats: **aditividad** (FR-002) — un consumidor que sólo lee los campos que conoce (
  `cut -f1-2` sobre `entry`/`uncovered`) obtiene etiqueta y path intactos, y una línea con una
  etiqueta desconocida no rompe ese recorte; fija por prueba la promesa que hoy sólo está escrita en
  el contrato, en tests/status-porcelain.bats
- [X] T026 [P] Documentar `--porcelain`, `--why` y el contrato de exit codes (0/1/2/3) de `status` y
  `list` en README.md y README.es.md, incluida la nota de que `2` y `3` valen para todos los verbos
  que detectan esas situaciones, no sólo para las superficies porcelain (regla de `../../AGENTS.md`: los
  dos README se actualizan juntos)
- [X] T027 Correr
  `shellcheck $(find bin -type f ! -name '.gitkeep') install.sh uninstall.sh web-install.sh web-uninstall.sh bump-version.sh`
  sobre el estado final y corregir cualquier hallazgo introducido por esta feature
- [X] T028 Correr `./tests/run-docker.sh` (suite completa) y confirmar que toda aserción existente
  sobre el **texto** de la salida humana sigue pasando sin modificarse, y que las únicas aserciones
  tocadas en todo el repo son las dos de exit code de T033 (SC-008). Cualquier otro test que haya
  que editar para que pase es una regresión, no un ajuste
- [X] T029 Recorrer [quickstart.md](./quickstart.md) de punta a punta a mano, las 6 historias,
  confirmando que los códigos de salida y la forma de los registros documentados en `contracts/*.md`
  coinciden con la salida real

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: sin dependencias — puede arrancar de inmediato
- **Foundational (Phase 2)**: depende de Setup — bloquea toda historia de usuario
- **User Stories (Phase 3-8)**: dependen de Foundational; entre sí, cada una
  construye sobre la ruta porcelain que US1 deja andando en `status` (agregando
  su propio tipo de registro), con dos excepciones: US6 extiende `list` por
  separado, y US3 no emite ninguna línea porcelain (son códigos de salida), así
  que ninguna de las dos depende de Foundational ni de US1
- **Polish (Phase 9)**: depende de que todas las historias deseadas estén completas

### User Story Dependencies

- **US1 (P1)**: después de Foundational — sin dependencia de otras historias. Es la base: T004 crea
  la bifurcación `--porcelain` en `status` que US2/US3/US4/US5 extienden.
- **US2 (P2)**: después de Foundational y de que T004 (US1) exista la ruta porcelain de `status` —
  independientemente testeable con su propio walkthrough de fixture
- **US3 (P2)**: **no depende de Foundational ni de US1** — son códigos de salida, no líneas
  porcelain. T015/T032/T033/T016 tocan verbos y helpers existentes y pueden hacerse primero, incluso
  como cambio aparte. Es además la historia con el radio de impacto más grande (siete puntos de
  emisión, dos helpers compartidos, cinco verbos que no son `status`), así que conviene aislarla en
  su propio commit
- **US4 (P3)**: después de Foundational y de que exista la ruta porcelain de `status` (US1); usa la
  misma noción de "secuencia actual" que US2 pero no depende de que US2 esté implementada (puede
  resolver el path directamente con `walk_sequence`)
- **US5 (P3)**: después de Foundational; ortogonal a US2/US3/US4 (otro tipo de registro más)
- **US6 (P4)**: después de Foundational — toca `list`, no `status`; totalmente independiente de
  US1-US5

### Within Each User Story

- Helpers en `git-review-lib.sh` antes que su uso en el verbo
- Registro whole antes que sus extensiones step/walk (US1)
- Implementación antes que sus tests
- Historia completa y con checkpoint antes de pasar a la siguiente por prioridad

### Parallel Opportunities

- T008 corre en paralelo con el resto de US1 una vez que T005-T007 están (mismo archivo de test,
  pero es la única tarea de test de la fase)
- T013, T014, T030 y T031 en paralelo entre sí (todas escriben en el mismo archivo de test, en
  secciones distintas — coordinar el punto de inserción antes de escribirlas simultáneamente)
- US6 completa (T022-T025) puede correr en paralelo con cualquier otra historia (P2-P5), porque toca
  `list`, no `status`
- US3 completa (T015, T032, T033, T016) puede correr en paralelo con todo lo demás, y de hecho
  conviene: no comparte una sola línea de código con la ruta porcelain
- T034, T035 y T036 en paralelo entre sí, después de que estén US1/US2/US5 (necesitan una salida
  porcelain real sobre la que aserir)
- T026 (README) puede correr en paralelo con T027/T028/T029 una vez que todas las historias deseadas
  estén implementadas

---

## Parallel Example: User Story 1

```bash
# T003, T004 son secuenciales (mismo archivo, cambios que se acumulan uno sobre otro)
# T005-T007 son secuenciales entre sí (mismo bloque de código, un modo a la vez)
# T008 y T009 pueden escribirse en paralelo con la implementación una vez que el
# contrato de campos (data-model.md) está fijado, pero corren en bats después:
Task: "bats: tests de salida exacta para state en whole/step/walk en tests/status-porcelain.bats"
Task: "bats: test de no-regresión sobre reescritura de mensaje humano en tests/status-porcelain.bats"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Completar Phase 1: Setup
2. Completar Phase 2: Foundational (bloquea todo lo demás)
3. Completar Phase 3: US1
4. **Parar y validar**: `status --porcelain` reporta el estado correcto en los tres modos, de forma
   independiente
5. Es un MVP genuino: SC-001 ("reconstruir la vista completa... sin leer texto humano") ya es
   parcialmente cierto para el estado, aunque falten secuencia/cobertura

### Incremental Delivery

1. Setup + Foundational → base lista
2. US1 → validar independientemente → MVP
3. US2 → validar independientemente (secuencia navegable)
4. US3 → validar independientemente (códigos de salida)
5. US4 → validar independientemente (porqué de una entrada)
6. US5 → validar independientemente (cobertura)
7. US6 → validar independientemente (inventario)
8. Polish → README, shellcheck, suite completa, quickstart de punta a punta

### Parallel Team Strategy

Con más de una persona: Setup + Foundational en conjunto; después hay tres
frentes que no se pisan. US1→US2→US4→US5 se acumulan sobre `status` y conviene
mantenerlas en secuencia (T004 de US1 crea la bifurcación que las demás
extienden). US6 toca `list`. US3 no toca ninguna ruta porcelain: son códigos de
salida sobre verbos y helpers existentes, y es la que más superficie ajena
roza, así que va en su propio commit para que el diff se lea solo.

---

## Notes

- `[P]` = archivos distintos o lectura pura, sin dependencia de una tarea sin terminar
- La etiqueta de historia asocia cada tarea a su US para trazabilidad
- Cada historia es completable y verificable por sí sola (ver *Independent Test* de cada fase)
- Commitear tras cada tarea o grupo lógico
- Parar en cualquier checkpoint para validar la historia de forma independiente
- Evitar: tareas vagas, conflictos de archivo dentro de un mismo `[P]`, dependencias cruzadas entre
  historias que rompan su independencia
