# Tasks: Superficie completa del panel

**Input**: Design documents from `/specs/006-superficie-panel-completa/`

**Prerequisites**: [plan.md](./plan.md), [research.md](./research.md),
[data-model.md](./data-model.md),
[contracts/cli-invocation.md](./contracts/cli-invocation.md),
[quickstart.md](./quickstart.md)

**Tests**: asserts fuertes (CLAUDE.md); unit + integration como en `005`.

**Organization**: US1 housekeeping → US2 preview → US3 compare → US4 walkthrough.

## Format: `[ID] [P?] [Story] Description`

## Path Conventions

`vscode-extension/src`, `vscode-extension/test`, `vscode-extension/package.json`,
`vscode-extension/README.md`. CLI sin cambios esperados.

---

## Phase 1: Setup

- [x] T001 Puntero en `specs/005-ciclo-review-panel/contracts/cli-invocation.md`
  (o nota al inicio) de que la lista de verbos prohibidos de clean/forget/… la
  enmienda `006/contracts/cli-invocation.md`. Actualizar
  `.specify/feature.json` a `specs/006-superficie-panel-completa`.

---

## Phase 2: Foundational

- [x] T002 [P] Crear `vscode-extension/src/review/housekeeping.ts`: tipos
  `HousekeepingAction`, builders de args puros
  `argsForHousekeeping(action): string[]` y `verbForHousekeeping` → siempre
  `clean` o `forget` según kind (data-model.md). Sin vscode.
- [x] T003 [P] Unit tests en `vscode-extension/test/unit/housekeeping.spec.ts`
  para cada kind → args exactos (lista cerrada).
- [x] T004 [P] Helper compartido
  `vscode-extension/src/commands/confirmMutation.ts` (o similar): modal
  warning + detail + button label; retorna boolean. Reutilizar estilo de
  abortReview.
- [x] T005 Registrar en `vscode-extension/package.json` los command ids
  placeholder (clean, forget*, preview*, compare, walkthrough*) y category
  `git review`.

---

## Phase 3: User Story 1 — Housekeeping (P1)

**Goal**: forget/clean/orphans desde inventario y palette.

**Independent Test**: quickstart P1 + integration specs.

- [x] T006 [US1] `vscode-extension/src/commands/cleanReview.ts`: clean-one /
  clean-all con confirmación, lock, progress, refresh, stderr.
- [x] T007 [US1] `vscode-extension/src/commands/forgetReview.ts`: saved-one,
  saved-all, delta-one, delta-all, delta-stale; network en stale; picker de
  source cuando hace falta.
- [x] T008 [US1] `vscode-extension/src/views/panelHtml.ts` +
  `walkthroughViewProvider.ts` / `extension.ts`: mensajes webview
  `discardSaved` / `discardOrphan` / clean; botones en filas.
- [x] T009 [US1] Wire commands en `extension.ts` + when-clauses palette.
- [x] T010 [US1] Unit: confirm copy / source extraction from inventory name
  (`review-saved/x` → `x`).
- [x] T011 [US1] Integration
  `test/integration/housekeeping.spec.ts`: discard saved, clean leftover,
  cancel modal no-op (ASCII test names).
- [ ] T012 [US1] Integration orphan discard path.

---

## Phase 4: User Story 2 — Preview (P2)

- [x] T013 [US2] `vscode-extension/src/views/previewContentProvider.ts`: scheme
  virtual para mostrar stdout como diff.
- [x] T014 [US2] `vscode-extension/src/commands/previewEdits.ts`: invoke
  preview / --stat; abrir documento; errores CLI.
- [x] T015 [US2] Registrar + README fragmento.
- [ ] T016 [US2] Unit o integration mínima: exit 0 con fixture ediciones;
  working tree intacto.

---

## Phase 5: User Story 3 — Compare (P3)

- [x] T017 [US3] `vscode-extension/src/commands/compareReview.ts`: pick a/b
  (candidates + input), layout, confirm, invoke compare, refresh.
- [x] T018 [US3] Wire package.json + extension.ts.
- [ ] T019 [US3] Integration: compare two branches → status porcelain mode.

---

## Phase 6: User Story 4 — Walkthrough (P4)

- [x] T020 [US4] `vscode-extension/src/commands/walkthrough.ts`: init (retry
  --force tras confirm si CLI dice exists), open file; build.
- [x] T021 [US4] Wire package.json + extension.ts.
- [ ] T022 [US4] Integration o unit del flujo force.

---

## Phase 7: Polish

- [x] T023 Actualizar `vscode-extension/README.md` (tabla de acciones) en
  inglés.
- [x] T024 Puntero en contrato 005 + checklist de que no hay `git branch -D`
  en src (grep).
- [x] T025 `npm test` unit + integration relevantes en verde.
- [ ] T026 Preview fixtures si el panel vacío gana botones visibles en
  preview HTML (opcional si no cambian estados frozen).

---

## Dependencies

T002–T005 → US1 → US2/US3/US4 (US2–4 independientes entre sí tras foundational).

## MVP

US1 sola ya entrega valor (inventario operable).
