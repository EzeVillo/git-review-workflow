# Tasks: Ofertas de lectura al iniciar review

**Input**: Design documents from `/specs/008-start-layout-offers/`

**Prerequisites**: [plan.md](./plan.md), [research.md](./research.md),
[data-model.md](./data-model.md),
[contracts/config-porcelain-offers.md](./contracts/config-porcelain-offers.md),
[contracts/extension-start-offers.md](./contracts/extension-start-offers.md),
[quickstart.md](./quickstart.md)

**Tests**: sí — el proyecto exige asserts fuertes (CLAUDE.md). Cada historia
incluye tests que deben fallar antes de la implementación de esa historia.
Nombres de `@test` en ASCII puro.

**Organization**: por user story (P1 → P2 → P3). US1 es el MVP (CLI offers +
asistente sin auto). US2 es recommended. US3 es orden del wizard (puede
mezclarse con US1 en implementación pero se valida aparte). US4 es la
garantía sin-red del tip remoto.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: paralelizable (archivos distintos, sin dependencia incompleta)
- **[Story]**: [US1] ofertas honestas, [US2] recommended, [US3] orden wizard,
  [US4] tip remoto sin fetch
- Cada tarea nombra el path exacto

## Path Conventions

- CLI: `bin/`, tests en `tests/` vía `./tests/run-docker.sh`
- Extensión: `vscode-extension/src/`, tests en `vscode-extension/test/`

---

## Phase 1: Setup

**Purpose**: hogar de tests y puntos de inserción.

- [x] T001 Crear `tests/config-offers.bats` con `load`/`setup` al estilo de
  `tests/` existentes (repo temporal, base, ramas con/sin walkthrough y con
  keys) y un `@test` placeholder ASCII que pase.
- [x] T002 [P] Anotar en el cuerpo de la primera PR/commit los puntos de
  inserción: parseo de flags en `bin/git-review-verbs/config`, helpers de
  tip/lower a reutilizar o extraer desde `bin/git-review-verbs/start` /
  `bin/git-review-lib.sh`, y el reorden de `vscode-extension/src/commands/startReview.ts`.

---

## Phase 2: Foundational (CLI — emisión de offer)

**Purpose**: contrato porcelain de ofertas. Bloquea todas las US.

**CRITICAL**: completar antes de marcar verdes los tests de historias de UI.

- [x] T003 En `bin/git-review-verbs/config` (y lib si hace falta): parsear
  `--local`, `--offline`, `--delta` solo en modo porcelain; rechazar
  combinaciones inválidas (`--local`+`--offline`, `--delta` sin rama, etc.)
  con exit 1 y usage actualizado.
- [x] T004 En `bin/git-review-lib.sh` o `config`: función de resolución
  tip/lower **sin fetch** alineada con start (remote tracking / heads /
  offline base / delta marker del origin del contexto). Fallar si tip o
  lower no resuelven.
- [x] T005 En lib o config: emitir registros `offer id rank` según
  [contracts/config-porcelain-offers.md](./contracts/config-porcelain-offers.md)
  usando `walk_read` / `walk_sequence` / `walk_keys_order` (007). Orden
  walk → keys → step → whole; solo walk con rank recommended.
- [x] T006 [P] Tests en `tests/config-offers.bats` (red-first): matrix sin
  walk / walk sin keys / walk con keys; delta que no intersecta; tip remote
  missing; `--local` vs default remote con tips distintos. Assert status y
  líneas `offer` exactas (grep o igualdad de subconjunto estable).

**Checkpoint**: `git review config --porcelain … -- <branch>` emite offers
correctas en Docker bats.

---

## Phase 3: User Story 1 — Solo formas de lectura posibles (P1) 🎯 MVP

**Goal**: el asistente no muestra Automatic ni opciones inviables; cada
opción arranca el modo prometido.

**Independent Test**: matrix de tres ramas en el asistente o unit del
builder de items + start real en integration.

### Tests US1

- [x] T007 [P] [US1] En `vscode-extension/test/unit/configPorcelain.spec.ts`:
  parsear líneas `offer`; ignorar etiquetas desconocidas; result con lista
  de offers.
- [x] T008 [P] [US1] En `vscode-extension/test/unit/reviewIntent.spec.ts`:
  `ReviewLayout` sin `auto`; `intentToArgs` para walk/keys/step/whole
  (`whole` → `--no-walk`, `walk` sin flag de layout).
- [x] T009 [P] [US1] En unit del helper de items de layout (nuevo o en
  startReview tests): dado offers A, solo se construyen esos ítems; sin
  offers (CLI vieja) → whole+step sintéticos; **informe exit≠0** → no
  items / path de error (FR-012).
- [x] T009b [P] [US1] Unit de `layoutSummary` / frase de confirmación:
  walk/keys/step/whole sin la palabra "automatic" (FR-011).
- [x] T010 [P] [US1] Ajustar/extender
  `vscode-extension/test/integration/start-review.spec.ts`: labels
  Whole diff / Walkthrough / Commit by commit; orden de pasos
  branch→source→range?→layout; sin Automatic.

### Implementation US1

- [x] T011 [US1] Extender `vscode-extension/src/cli/configPorcelain.ts`:
  tipo `ReadingOffer`, parse de `offer`, export en `ConfigPorcelainResult`.
- [x] T012 [US1] Actualizar `vscode-extension/src/review/reviewIntent.ts`:
  quitar `auto`; layouts `walk|keys|step|whole`; `intentToArgs` según
  contrato extension-start-offers.
- [x] T013 [US1] En `vscode-extension/src/commands/startReview.ts`: **reordenar
  wizard** a rama→origen→rango→lectura (US3 unificado aquí, O1); cargar
  offers tras origen/rango; QuickPick dinámico; fallback whole+step;
  eliminar Automatic; confirmación sin “automatically”; error de offers
  aborta sin start (FR-012). Dependencia: helper `walk_keys_order` de 007
  ya en CLI (D1).
- [x] T014 [US1] Correr unit de extensión y `./tests/run-docker.sh
  tests/config-offers.bats` hasta verde; shellcheck de scripts CLI
  tocados.

**Checkpoint**: MVP usable — listado honesto + start correcto.

---

## Phase 4: User Story 2 — Walk recommended (P2)

**Goal**: solo walk lleva recommended; orden/preselección del QuickPick.

**Independent Test**: offers con walk → primer ítem walk+(recommended);
offers solo step+whole → ningún recommended.

### Tests US2

- [x] T015 [P] [US2] Unit: builder de items pone walk primero cuando
  rank=recommended; description o label incluye recommended; keys no.

### Implementation US2

- [x] T016 [US2] En `startReview.ts` (o helper puro testable): aplicar rank
  al label/description y ordenar según contrato; sin recommended sintético
  en fallback.

**Checkpoint**: US2 verificable en unit sin UI manual.

---

## Phase 5: User Story 3 — Orden del wizard (P2)

**Goal**: rama → origen → rango → lectura → confirmación.

**Nota (O1)**: el reorden se implementa en **T013**. Esta fase solo
verifica y documenta.

### Tests US3

- [x] T017 [P] [US3] Integration: `stepKinds` en orden
  `branch, source, …, layout` (layout después de source); offers con
  flags `--local` cuando source=Local.

### Implementation US3

- [x] T018 [US3] Checklist: confirmar que T013 dejó comentarios
  Decisión 9/FR-008 actualizados y que no queda `pickLayout` antes de
  source. Sin código nuevo si T013 está completo.

**Checkpoint**: cambiar origen/rango cambia el conjunto de ofertas.

---

## Phase 6: User Story 4 — Tip remoto sin red (P3)

**Goal**: el path de ofertas no hace fetch; start remoto sigue pudiendo.

**Independent Test**: bats o traza: config porcelain offers no llama fetch;
documentar en test con stub o con assert de que la ref tracking preexistente
basta.

### Tests US4

- [x] T019 [P] [US4] En `tests/config-offers.bats`: con solo
  `refs/remotes/origin/branch` (sin red), offers se emiten; opcionalmente
  instrumentar que no se corrió fetch (p. ej. `GIT_TRACE` filtrado o remote
  URL inalcanzable que haría fallar un fetch).

### Implementation US4

- [x] T020 [US4] Revisar `config`/helpers: **ningún** `git fetch` en el
  camino de offers; comentarios que apunten a research Decisión 5. Start
  no se modifica en política de red.

**Checkpoint**: US4 verde en Docker.

---

## Phase 7: Polish & cross-cutting

- [x] T021 [P] Actualizar README.md y README.es.md si documentan el
  asistente o `config --porcelain` (ofertas / desaparición de Automatic);
  landing **no** tocar salvo que se verifique una de las 4 superficies
  (no aplica).
- [x] T022 [P] Alinear tests rotos por `auto` en
  `reviewIntent.spec.ts`, `start-review.spec.ts`, y cualquier fixture de
  007 que listara keys estático.
- [x] T023 Verificar [quickstart.md](./quickstart.md) a mano o vía bats;
  shellcheck de todos los scripts tocados; `npm run test:unit` en
  vscode-extension.
- [x] T024 Marcar checklist de requirements y dejar nota de done en
  tasks o PR.

---

## Dependencies

```text
Phase1 → Phase2 (CLI offers)
Phase2 → US1 (parser + wizard)
US1 → US2 (recommended es presentación sobre offers)
US1 → US3 (reorden; puede implementarse junto con T013)
US1 → US4 (garantía de red sobre el mismo camino CLI)
Polish al final
```

**MVP**: Phase1 + Phase2 + US1 (T001–T014).

## Parallel opportunities

- T001 ∥ T002
- T006 tests CLI ∥ T007–T009 tests unit extensión (tras T005 en CLI para
  no mockear de más)
- T015 ∥ T017 ∥ T019 una vez existe el builder/helpers puros
- T021 ∥ T022

## Implementation strategy

1. Rojo CLI (T006) → verde emisión offer (T003–T005).
2. Rojo unit extensión → parser + intent + items (T007–T013).
3. Recommended + orden wizard como refinamiento del mismo archivo.
4. Test de no-fetch y docs.

## Task count

| Phase | Tasks |
|-------|-------|
| Setup | T001–T002 (2) |
| Foundational | T003–T006 (4) |
| US1 | T007–T014 (8) |
| US2 | T015–T016 (2) |
| US3 | T017–T018 (2) |
| US4 | T019–T020 (2) |
| Polish | T021–T024 (4) |
| **Total** | **24** |
