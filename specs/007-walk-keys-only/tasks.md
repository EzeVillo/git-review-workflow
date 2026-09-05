# Tasks: Submodo walk solo-keys

**Input**: Design documents from `/specs/007-walk-keys-only/`

**Prerequisites**: [plan.md](./plan.md), [research.md](./research.md),
[data-model.md](./data-model.md),
[contracts/status-porcelain-keys.md](./contracts/status-porcelain-keys.md),
[contracts/cli-invocation-keys.md](./contracts/cli-invocation-keys.md),
[quickstart.md](./quickstart.md)

**Tests**: sÃ­ â€” `../../AGENTS.md` exige asserts fuertes; el proyecto usa
test-first en cambios de porcelain/CLI. Cada historia incluye tests que
deben fallar antes de la implementaciÃ³n de esa historia.

**Organization**: por user story (P1 â†’ P2 â†’ P3). US1 es el MVP CLI. US2
es persistencia del ciclo. US3 es paridad extensiÃ³n.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: paralelizable (archivos distintos, sin dependencia incompleta)
- **[Story]**: [US1] CLI cursor, [US2] save/continue/finish, [US3] extensiÃ³n
- Cada tarea nombra el path exacto

## Path Conventions

- CLI: `bin/`, tests en `tests/` vÃ­a `./tests/run-docker.sh`
- ExtensiÃ³n: `vscode-extension/src/`, tests en `vscode-extension/test/`

---

## Phase 1: Setup

**Purpose**: baseline y archivo de tests del feature.

- [x] T001 Crear `tests/keys.bats` vacÃ­o con `load`/`setup` del estilo de
  `tests/walk.bats` (helpers de repo temporal + walkthrough con keys) y
  un `@test` placeholder ASCII que pase, para tener hogar de los casos
  US1/US2.
- [x] T002 [P] Confirmar en `bin/git-review-verbs/start` y
  `bin/git-review-lib.sh` los puntos de inserciÃ³n documentados en
  research.md (parseo de flags, decisiÃ³n walk pre-switch,
  `load_walk_review_meta`) â€” nota de 5 lÃ­neas en el cuerpo del PR o
  comentario de commit, sin cambiar comportamiento aÃºn.

---

## Phase 2: Foundational (CLI shared)

**Purpose**: helper de secuencia y metadata compartidos. Bloquea US1â€“US2.

**âš ï¸ CRITICAL**: completar antes de marcar verdes los tests de historias.

- [x] T003 En `bin/git-review-lib.sh`, implementar `walk_keys_order <tip>
  <lower>`: emite paths de `walk_sequence` que tienen `> key`, una lectura
  de walkthrough (patrÃ³n `walk_entry_fields` / `walk_count_keys`), sin
  tercer punto de normalizaciÃ³n de paths.
- [x] T004 En `bin/git-review-lib.sh`, extender `load_walk_review_meta`
  para leer `branch.$cur.reviewwalkkeys`: si estÃ¡ activo, `walkpaths`
  sale de `walk_keys_order` (no de `walk_reading_order`) y `total` es su
  longitud; guards de step/count/rango iguales.
- [x] T005 [P] En `bin/git-review-lib.sh` (o el sitio de guards de
  `finish`), documentar/preparar el invariante: `reviewwalkkeys` sin
  `reviewmode=walk` es metadata corrupt (implementaciÃ³n del die en T014).

---

## Phase 3: User Story 1 â€” Primer pase solo-keys en CLI (P1) ðŸŽ¯ MVP

**Goal**: `start`/`compare --keys`, secuencia solo keys, next/prev,
status humano + porcelain `keys`.

**Independent Test**: sandbox/PR con K keys; `git review start <src>
--keys`; recorrer con next hasta el final; porcelain lista K entries +
registro `keys`.

### Tests US1 (escribir primero; deben fallar)

- [x] T006 [P] [US1] En `tests/keys.bats`: start --keys con walkthrough de
  N>K keys visita solo K paths; status exit 0; asserts de output y de
  `reviewwalkkeys`/`reviewwalkcount`.
- [x] T007 [P] [US1] En `tests/keys.bats`: next/prev solo entre keys; al
  final de K, next no avanza a no-key (mismo comportamiento fin de
  secuencia que walk).
- [x] T008 [P] [US1] En `tests/keys.bats`: `status --porcelain` emite
  registro `keys`, `total=K`, solo entries con essential=1; sin
  uncovered.
- [x] T009 [P] [US1] En `tests/keys.bats`: rechazos â€” `--keys --step`,
  `--keys --no-walk`, `--keys` con K=0, `--keys` sin walkthrough: exit â‰ 0,
  mensaje en stderr, **sin** rama `review/*` nueva.
- [x] T010 [P] [US1] En `tests/keys.bats`: `compare <a> <b> --keys` con
  walkthrough en b y Kâ‰¥1 arma review readonly keys-only (registro `keys`
    + `readonly` si aplica).

### Implementation US1

- [x] T011 [US1] En `bin/git-review-verbs/start`: parsear `--keys`;
  rechazar con `--step`/`--no-walk`; si keys y walk aplicable con K=0 o
  sin walk, `die` **antes** de `switch -c`; si ok, set
  `reviewwalkkeys=1`, `reviewwalkcount=K`, `walkpaths` filtrado, mensaje
  ready con K, `show_walk_entry 1`.
- [x] T012 [US1] En `bin/git-review-verbs/compare`: mismo flag y reglas
  que start para el branch walk (research.md D7).
- [x] T013 [US1] En `bin/git-review-verbs/status`: humano indica
  keys-only; porcelain emite `keys` cuando el filtro estÃ¡ activo
  (contracts/status-porcelain-keys.md). `next`/`prev` no requieren
  cambios si T004 filtra.
- [x] T014 [US1] En `bin/git-review` (help del dispatcher) y usage de
  `start`/`compare`: documentar `--keys` en el texto de ayuda.
- [x] T015 [US1] Correr `./tests/run-docker.sh tests/keys.bats` (y
  walk/status relacionados si se tocaron) hasta verde; shellcheck de
  scripts tocados.

**Checkpoint**: MVP CLI usable sin extensiÃ³n.

---

## Phase 4: User Story 2 â€” Persistencia en el ciclo (P2)

**Goal**: save/continue preservan filtro y cursor; finish/abort/preview
como walk.

**Independent Test**: start --keys, avanzar, save, continue â†’ misma
posiciÃ³n y registro `keys`; finish con ediciÃ³n trivial ok.

### Tests US2

- [x] T016 [P] [US2] En `tests/keys.bats`: save + continue restaura
  `reviewwalkkeys`, step y secuencia filtrada (assert porcelain + config).
- [x] T017 [P] [US2] En `tests/keys.bats`: finish tras solo-keys con
  ediciÃ³n produce review-fixes (o el efecto canÃ³nico de finish) sin
  exigir no-keys; abort limpia la review keys-only.
- [x] T018 [P] [US2] En `tests/keys.bats`: preview en solo-keys no muta
  filtro ni step.

### Implementation US2

- [x] T019 [US2] En `bin/git-review-verbs/continue`: `restore_meta
  reviewwalkkeys` en el path walk.
- [x] T020 [US2] En `bin/git-review-verbs/finish` (y abort si limpia
  keys a mano): guard corrupt si `reviewwalkkeys` sin `reviewmode=walk`;
  finish/abort/preview sin lÃ³gica extra de cobertura.
- [x] T021 [US2] Verificar `save` mueve la config de branch sin perder
  `reviewwalkkeys` (si save ya copia todas las `branch.*`, solo test; si
  hay lista blanca de keys, aÃ±adir `reviewwalkkeys` en
  `bin/git-review-verbs/save`).
- [x] T022 [US2] `./tests/run-docker.sh tests/keys.bats` verde.

**Checkpoint**: ciclo completo CLI.

---

## Phase 5: User Story 3 â€” Paridad extensiÃ³n (P3)

**Goal**: layout keys en start del panel; porcelain `keys` â†’ modelo;
next/prev del panel ya delegan en CLI.

**Independent Test**: unit del intent/parser; panel model con fixture
keys-only; start pasa `--keys`.

### Tests US3

- [x] T023 [P] [US3] En `vscode-extension/test/unit/` (p. ej.
  `reviewIntent.spec.ts` o el archivo de intent existente): layout keys
  produce argv con `--keys` y sin `--step`/`--no-walk`.
- [x] T024 [P] [US3] En el test del parser porcelain: lÃ­nea `keys` â†’
  `keysOnly: true`; ausencia â†’ false; entries se parsean sin filtro
  cliente.
- [x] T025 [P] [US3] En `panelModel.spec.ts` (o equivalente): fixture
  solo-keys expone `keysOnly` y lista K files; UI model listo para badge.

### Implementation US3

- [x] T026 [US3] En `vscode-extension/src/review/reviewIntent.ts` (y
  tipos): valor de layout `"keys"`; `intentToArgs` emite `--keys`.
- [x] T027 [US3] En `vscode-extension/src/commands/startReview.ts`: Ã­tem
  de quick pick â€œWalkthrough â€” keys onlyâ€ (o etiqueta final en inglÃ©s del
  producto).
- [x] T028 [US3] En `vscode-extension/src/cli/porcelain.ts`: parsear
  registro `keys`.
- [x] T029 [US3] En `vscode-extension/src/views/panelModel.ts` y
  `panelHtml.ts`: `keysOnly` + indicador visible en el panel activo walk.
- [x] T030 [US3] Si existe copia del contrato de invocaciÃ³n en
  `vscode-extension` o specs vigentes de `005`/`006`, alinear comentario
  o lista cerrada con
  `specs/007-walk-keys-only/contracts/cli-invocation-keys.md` (sin abrir
  verbos nuevos).
- [x] T031 [US3] `npm test --prefix vscode-extension` (unit; integration
  solo si hay spec barato de start con mock CLI). Actualizar
  `preview/fixtures.ts` si el preview muestra estados walk.

**Checkpoint**: paridad panel.

---

## Phase 6: Polish & cross-cutting

- [x] T032 [P] Actualizar `README.md` y `README.es.md` juntos: flag
  `--keys` en start/compare, comportamiento del submodo, lÃ­mite (pase
  acotado). No tocar `docs/index.html` salvo que se elija aÃ±adir el flag
  a ejemplos (default: no).
- [x] T033 [P] Fusionar o enlazar la enmienda porcelain en la docs de
  contrato que el repo trate como vigente (`001` o Ã­ndice) para que no
  queden dos verdades contradictorias sobre `status --porcelain`.
- [x] T034 Correr shellcheck completo segÃºn `../../AGENTS.md` y
  `./tests/run-docker.sh` (suite o subset keys+walk+status+save).
- [x] T035 Recorrer [quickstart.md](./quickstart.md) una vez en sandbox y
  anotar desviaciones si las hay.

---

## Dependencies & Execution Order

### Story order

```text
Phase 1 Setup
    â†’ Phase 2 Foundational (T003â€“T005)
        â†’ Phase 3 US1 MVP (tests T006â€“T010 â†’ impl T011â€“T015)
            â†’ Phase 4 US2 (T016â€“T022)
                â†’ Phase 5 US3 (T023â€“T031)
                    â†’ Phase 6 Polish (T032â€“T035)
```

- US2 depende de US1 (hace falta start --keys).
- US3 depende de US1 para el contrato porcelain real; puede stubear el
  parser con fixtures antes, pero el layout start requiere CLI verde.
- US1 es entregable solo (MVP).

### Parallel examples

```text
# Tras T003â€“T004:
T006 T007 T008 T009 T010   # tests US1 en paralelo (mismo archivo: serializar writes)
T023 T024 T025             # tests extensiÃ³n en paralelo una vez exista el shape
T032 T033                  # docs en paralelo
```

Nota: varios tests en el mismo `keys.bats` se escriben en serie para
evitar conflictos de merge; el marcador [P] indica independencia lÃ³gica.

### MVP scope

**T001â€“T015 (US1 + foundational)** = producto usable en CLI. US2/US3
siguen en el mismo branch antes de merge.

---

## Implementation Strategy

1. Foundational: `walk_keys_order` + `load_walk_review_meta`.
2. Tests rojos US1 â†’ start/compare/status/help â†’ verdes.
3. US2 continue/save/finish guards.
4. ExtensiÃ³n intent + porcelain + panel.
5. README + shellcheck + suite.

TDD por historia: no implementar T011+ hasta que T006â€“T010 fallen por la
razÃ³n correcta (flag desconocida / secuencia completa).
