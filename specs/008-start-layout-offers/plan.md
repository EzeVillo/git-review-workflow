# Implementation Plan: Ofertas de lectura al iniciar review

**Branch**: `008-start-layout-offers` | **Date**: 2026-08-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/008-start-layout-offers/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the
execution workflow.

## Summary

La CLI reporta, vía `git review config --porcelain` con contexto de origen y
rango, las **formas de lectura viables** (`offer`) para un tip ya presente en
el clone **sin red**. La extensión reordena el asistente de start a
rama → origen → rango → forma de lectura, elimina el layout `auto`, construye
el QuickPick solo con ofertas del informe, marca `walk` como recommended
cuando aplica, y traduce cada oferta a argv unívoco (`walk` sin flag de
layout, `keys` → `--keys`, `step` → `--step`, `whole` → `--no-walk`).

## Technical Context

**Language/Version**: shell POSIX (`sh`) para la CLI; TypeScript + esbuild para
la extensión VS Code.

**Primary Dependencies**: `git` (rev-parse, config, show); API VS Code
(`QuickPick`); sin dependencias nuevas.

**Storage**: ninguno nuevo. Las ofertas no se persisten. Se reutilizan
helpers de walk (`walk_read`, `walk_sequence`, `walk_keys_order`) y la
resolución tip/lower alineada con `start` **sin** `git fetch`.

**Testing**: `bats` 1.13.0 (`./tests/run-docker.sh`) + `shellcheck` para CLI;
`npm test` (unit + integration) para la extensión.

**Target Platform**: Linux, macOS, Windows (CI en los tres).

**Project Type**: CLI + extensión consumidora de porcelain.

**Performance Goals**: costo acotado por invocación de ofertas (constante en
procesos git + una lectura de walkthrough), no O(n) por candidata ni por
archivo del PR. El informe se pide **una vez** por (rama, origen, rango), no
por cada candidata del listado.

**Constraints**: POSIX + `set -eu`; sin SC2015; paths solo por
`walk_normalize` / `changed_paths`; extensión no deriva estado ni parsea el
sidecar; porcelain aditivo v1; dos README si cambia superficie documentada;
nombres `@test` ASCII; probe **sin red**; start remoto puede seguir con fetch.

**Scale/Scope**: repositorios con cientos de ramas (ofertas solo tras elegir
una); walkthroughs con decenas–cientos de entradas. Toca `config` + helpers
compartidos de resolución de rango, parser/intent/startReview de la
extensión, tests bats + unit/integration, contratos 005 enmendados.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` es plantilla vacía. Gates = `../../AGENTS.md` +
contratos `001`/`002`/`005`:

| Gate | Estado | Nota |
|------|--------|------|
| Espejar idioms de git | ✅ | Flags de contexto en `config` espejo de `start` (`--local`/`--offline`/`--delta`) |
| Shell POSIX, `set -eu` | ✅ | Mismo estilo que `config`/`start` |
| Sin SC2015 | ✅ | Guards con `if` |
| Paths solo por normalización compartida | ✅ | Ofertas reusan `walk_*` existentes |
| Extensión no deriva estado | ✅ | Solo porcelain `offer` |
| Dos README juntos | ✅ | Si se documenta el informe / asistente |
| Tests asserts fuertes + ASCII en `@test` | ✅ | Planificado |
| Porcelain aditivo v1 | ✅ | Registro `offer` ignorable |
| Landing | ✅ | No toca las 4 superficies duplicadas |
| Red | ✅ | Probe sin fetch; start no cambia su política de red |

**Sin violaciones.** Complexity Tracking vacío.

### Re-evaluación post Phase 1

- Contrato `offer` + flags en `config` cierra FR-001/009/010 sin nuevo verbo.
- `whole` unificado en producto con argv siempre `--no-walk` evita el layout
  `auto` y mantiene un mapeo 1:1 intent→argv.
- Fallback CLI vieja (sin líneas `offer`) documentado en research y tasks.

## Project Structure

### Documentation (this feature)

```text
specs/008-start-layout-offers/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── config-porcelain-offers.md   # enmienda aditiva a config --porcelain
│   └── extension-start-offers.md    # orden wizard + ReviewLayout + argv
├── checklists/
│   └── requirements.md
└── tasks.md                         # /speckit-tasks
```

### Source Code (repository root)

```text
bin/
├── git-review-lib.sh              # helpers tip/lower/offers si se extraen
└── git-review-verbs/
    └── config                     # parse flags + emisión offer

tests/
└── config-offers.bats             # o ampliar tests de config existentes

vscode-extension/
├── src/
│   ├── cli/configPorcelain.ts     # parse offer
│   ├── review/reviewIntent.ts     # ReviewLayout sin auto; intentToArgs
│   └── commands/startReview.ts    # orden wizard + QuickPick dinámico
└── test/
    ├── unit/
    │   ├── configPorcelain.spec.ts
    │   ├── reviewIntent.spec.ts
    │   └── (panelModel si aplica)
    └── integration/
        └── start-review.spec.ts
```

## Implementation Phases (overview)

| Phase | Entrega |
|-------|---------|
| 0 | research.md (decisiones cerradas) |
| 1 | data-model, contracts, quickstart |
| 2 | tasks.md vía `/speckit-tasks` |
| impl | CLI offers → parser extensión → wizard → tests → README si aplica |

## Risks

| Riesgo | Mitigación |
|--------|------------|
| Tip/lower del probe diverge de `start` | Extraer o copiar la misma resolución; tests matrix alineados con start |
| Fetch en start cambia el tip tras ofertas | Aceptado (FR-009/US4); panel post-start es la verdad |
| CLI vieja sin `offer` | Fallback whole+step (FR-013) |
| Costo de walk_sequence en PRs grandes | Una vez por elección; no por candidata |

## Complexity Tracking

> Vacío — no hay violaciones de constitución que justificar.
