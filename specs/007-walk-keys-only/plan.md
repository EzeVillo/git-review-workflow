# Implementation Plan: Submodo walk solo-keys

**Branch**: `007-walk-keys-only` | **Date**: 2026-08-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/007-walk-keys-only/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the
execution workflow.

## Summary

Agregar un submodo de lectura **solo-keys** sobre walk: el revisor inicia con
`--keys` y la secuencia efectiva (humano, porcelain, `next`/`prev`) contiene
únicamente las entradas del walkthrough marcadas `> key` que están en rango.
No es un cuarto `mode`: sigue `reviewmode=walk` más
`reviewwalkkeys=1`. La extensión ofrece el mismo layout al start y pinta el
filtro desde un registro porcelain aditivo `keys`.

Enfoque: un helper de secuencia filtrada en `git-review-lib.sh`, un flag en
`start`/`compare`, re-derivación en `load_walk_review_meta`, persistencia en
`continue`, registro `keys` en `status --porcelain`, y paridad mínima en el
asistente de start + parser/modelo del panel.

## Technical Context

**Language/Version**: shell POSIX (`sh`) para la CLI; TypeScript + esbuild para
la extensión VS Code.

**Primary Dependencies**: `git` (config, diff, show); API VS Code;
`cross-spawn`. Sin dependencias nuevas.

**Storage**: clave de branch config `branch.review/<src>.reviewwalkkeys=1`
mientras vive la review (y su espejo en `review-saved/` vía save/continue).
Sin archivos en el working tree.

**Testing**: `bats` 1.13.0 (`./tests/run-docker.sh`) + `shellcheck` para CLI;
`npm test` (unit + integration) para la extensión.

**Target Platform**: Linux, macOS, Windows (CI en los tres).

**Project Type**: CLI de review + extensión consumidora de porcelain.

**Performance Goals**: re-derivar la secuencia keys con **una** lectura del
walkthrough por invocación (mismo presupuesto que `walk_entry_fields`), no
O(n) `git show`.

**Constraints**: POSIX + `set -eu`; sin `A && B || C`; paths solo por
`walk_normalize` / `changed_paths`; extensión sin leer config git cruda;
README EN+ES juntos; nombres `@test` ASCII; porcelain aditivo (v1).

**Scale/Scope**: PRs con decenas–cientos de entradas walk; K keys << N.
Toca ~8–12 archivos de producto (lib, start, compare, status, continue,
finish guards, dispatcher help) + parser/intent/panel de la extensión +
tests + 2 README.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` está vacío (plantilla). Gates = `../../AGENTS.md`

+ contratos `001`/`002`/`005`:

| Gate                                  | Estado | Nota                                          |
|---------------------------------------|--------|-----------------------------------------------|
| Espejar idioms de git                 | ✅      | Flag de layout en start, como `--step`        |
| Shell POSIX, `set -eu`                | ✅      | Mismos patrones que walk existente            |
| Sin SC2015 (`A && B \|\| C`)          | ✅      | Guards con `if` explícito                     |
| Dos puntos de normalización de paths  | ✅      | Filtro sobre `walk_sequence` (ya normalizado) |
| Extensión no deriva estado            | ✅      | Solo porcelain + flag en argv de start        |
| Dos README juntos                     | ✅      | Tarea única EN+ES                             |
| Tests asserts fuertes + nombres ASCII | ✅      | Planificado en tasks                          |
| Porcelain aditivo v1                  | ✅      | Registro presencia `keys` (como `readonly`)   |
| Landing no se toca si no hace falta   | ✅      | No entra en las 4 superficies duplicadas      |

**Sin violaciones.** Complexity Tracking vacío.

### Re-evaluación post Phase 1

- El helper de secuencia keys cierra el gate de normalización (un solo
  camino: sequence → filter by key marker already parsed from walk body).
- El registro `keys` no rompe consumidores: etiqueta nueva ignorable.
- `reviewwalkkeys` en guards de finish evita metadata a medias (espejo de
  walkstep sin mode).

## Project Structure

### Documentation (this feature)

```text
specs/007-walk-keys-only/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── status-porcelain-keys.md   # enmienda aditiva al contrato status
│   └── cli-invocation-keys.md     # enmienda: --keys en start/compare
├── checklists/
│   └── requirements.md
└── tasks.md                       # /speckit-tasks
```

### Source Code (repository root)

```text
bin/
├── git-review                     # help: --keys
├── git-review-lib.sh              # walk_keys_order; load_walk_review_meta filtra
└── git-review-verbs/
    ├── start                      # --keys, validaciones, walkcount=K
    ├── compare                    # idem
    ├── status                     # humano + registro porcelain `keys`
    ├── continue                   # restore_meta reviewwalkkeys
    ├── finish                     # guard metadata
    ├── next / prev                # sin cambio si load_* filtra
    └── save                       # mueve branch config tal cual (sin tocar)

tests/
├── walk.bats / review.bats / …    # casos --keys (o archivo nuevo keys.bats)
└── run-docker.sh

vscode-extension/src/
├── review/reviewIntent.ts         # layout keys → --keys
├── commands/startReview.ts        # ítem de layout
├── cli/porcelain.ts               # parse registro `keys`
├── views/panelModel.ts            # keysOnly
└── views/panelHtml.ts             # indicador UI

README.md / README.es.md
```

**Structure Decision**: reusar el layout del monorepo CLI + extensión; no
nuevos paquetes ni verbos en PATH.

## Complexity Tracking

> Vacío — sin violaciones de constitución que justifiquen.
