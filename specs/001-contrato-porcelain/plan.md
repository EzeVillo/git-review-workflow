# Implementation Plan: Contrato de salida legible por programas

**Branch**: `001-contrato-porcelain` | **Date**: 2026-08-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-contrato-porcelain/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the
execution workflow.

## Summary

Extender los verbos `status` y `list` con una salida orientada a programas
(activada por `--porcelain`), sin tocar la salida humana existente. El formato
elegido es texto plano con líneas etiquetadas y campos separados por tab
(mismo idioma que `git status --porcelain=v2` / `git for-each-ref`), no JSON:
el proyecto ya prohíbe herramientas nuevas (no hay `jq` ni `node` en el
contenedor de tests) y escribir un serializador JSON a mano en `awk`/`sh` para
prosa arbitraria (el "why" de una entrada) reintroduciría exactamente la clase
de bug de escaping invisible que el proyecto ya pagó tres veces con paths
(CRLF, BOM, whitespace). `status --porcelain` emite, en una sola invocación,
el registro de estado (US1), los registros de secuencia —walk y step por igual,
según Q2 opción C— (US2) y los de cobertura (US5); un flag separado,
`--why <path>`, vuelca el texto explicativo crudo sin ningún otro dato en el
stream (FR-014). `list --porcelain` cubre el inventario (US6). Cuatro códigos
de salida (0 / 1 error / 2 sin review activa / 3 cursor fuera de rango por
drift de la base) resuelven US3 y FR-023. Nada de esto agrega
verbos nuevos ni estado persistido nuevo: todo se deriva con los mecanismos
existentes (`walk_sequence`, `walk_is_key`, `walk_why`, `changed_paths`,
`load_step_review_meta`).

## Technical Context

**Language/Version**: POSIX `sh` (sin bashisms; corre bajo `dash` y Git Bash),
igual que el resto del proyecto. `awk`/`sed`/`grep`/`cut`/`sort`/`comm` POSIX,
ya en uso en `bin/git-review-lib.sh`.

**Primary Dependencies**: Ninguna nueva. Sólo `git` y las utilidades POSIX ya
requeridas. Explícitamente **no** `jq` ni Node para generar la salida: el
contenedor de tests (`tests/Dockerfile`, `bats/bats:latest` sobre Alpine) no
trae ninguno de los dos (ver comentario en `tests/packaging.bats:67`), y el
proyecto ya elige "instalar sin Node" como opción de primera clase (Homebrew /
PowerShell / one-liner en el README).

**Storage**: N/A. Sin claves de config ni refs nuevas — ver *Assumptions* del
spec ("Sin estado nuevo persistido"). Todo dato expuesto se deriva en el
momento de la consulta a partir de `branch.<b>.review*` y `refs/review-edits/`,
ya existentes.

**Testing**: bats, vía `./tests/run-docker.sh` (nunca bajo Git Bash en
Windows). Casos nuevos como aserciones de igualdad exacta sobre la salida
porcelain (línea por línea), más un test de no-regresión que reescribe un
mensaje humano y verifica que la salida porcelain no cambia un solo byte
(FR-003/SC-004). Los tests nuevos van a `tests/status-porcelain.bats` (archivo
nuevo) y a `tests/list.bats` / `tests/errors.bats` (existentes); `extras.bats`
ya mezcla cuatro verbos y no conviene engordarlo más. Los nombres de `@test`
van en ASCII puro, sin acentos ni em dashes — regla de `CLAUDE.md`: bats
convierte cada nombre en nombre de función y el bats de Windows en CI se rompe
con los bytes UTF-8.

**Target Platform**: Los mismos tres runners de CI (ubuntu/macos/windows) y el
mismo modelo de instalación (libexec junto al dispatcher). Sin requisitos
nuevos de entorno.

**Project Type**: CLI (proyecto único; sin frontend/backend separados).

**Performance Goals**: Refrescar la vista completa de una review de ~50
entradas no debe sentirse como demora (SC-007, deliberadamente sin ms). Meta de
diseño: costo O(1) en invocaciones de `git show` respecto del número de
entradas — leer el walkthrough **una vez** por invocación de `--porcelain` y
derivar posición/path/esencial para todas las entradas en memoria (extendiendo
el patrón que ya usa `walk_count_keys`), en vez de llamar `walk_is_key` una vez
por entrada como hace hoy la ruta humana de `status` en modo walk.

**Constraints**: Sin dependencias nuevas (arriba); salida humana byte-idéntica
(FR-021/SC-008); consultas de sólo lectura, cero mutación de config/refs/working
tree (FR-022); esquema porcelain aditivo únicamente — un consumidor viejo debe
poder ignorar campos y tipos de registro nuevos sin romperse (FR-002).

**Scale/Scope**: Cambios acotados a dos verbos existentes (`status`, `list`) y
a `bin/git-review-lib.sh` (helpers compartidos de derivación). Sin verbos
nuevos, sin cambios al dispatcher.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` no está ratificado en este repo (conserva
los placeholders de la plantilla, sin principios reales que evaluar). En su
lugar, las restricciones operativas vinculantes son las de `CLAUDE.md`:
espejar los idiomas de git, actualizar los dos README en el mismo cambio,
sólo shell POSIX con `set -eu`, shellcheck limpio, tests bats con asserts
fuertes, y no tocar la landing salvo que el cambio toque alguno de sus cuatro
puntos duplicados (no es el caso aquí: ni tabla comparativa, ni instalación, ni
los comandos de ejemplo `start/next/finish/walkthrough init|build/
reviewworkflow.base`, ni el formato del walkthrough cambian).

**Gate: PASS.** El diseño elegido (texto porcelain estilo git, sin
dependencias nuevas, sin verbos nuevos, salida humana intacta) no viola
ninguna de estas restricciones. No hay violaciones que justificar en
*Complexity Tracking*.

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
bin/
├── git-review                          # dispatcher — sin cambios
├── git-review-lib.sh                   # + helpers de derivación porcelain (ver abajo)
└── git-review-verbs/
    ├── status                          # + --porcelain, --why <path>, exit codes
    └── list                            # + --porcelain

tests/
├── errors.bats                         # + exit codes exactos (2 no-review / 1 error /
│                                       #   1 not-a-repo / 3 cursor fuera de rango)
├── status-porcelain.bats               # NUEVO — todo status --porcelain y --why
│                                       #   (state/entry/uncovered, no-regresión,
│                                       #   paths, read-only, aditividad)
├── list.bats                           # + list --porcelain (inventario)
└── walkthrough.bats                    # sin cambios de comportamiento; puede ganar
                                         # fixtures reutilizadas por los tests porcelain

README.md / README.es.md                # documentar --porcelain / --why y los exit codes
docs/index.html                         # sin cambios (no toca ninguno de los 4 puntos
                                         # duplicados de la landing)
```

**Structure Decision**: Proyecto único (CLI de shell POSIX), estructura ya
existente sin nuevos directorios. El contrato se añade como flags de dos
verbos ya presentes (`status`, `list`) más helpers nuevos en
`bin/git-review-lib.sh`, reutilizando los mecanismos de derivación existentes
(`walk_sequence`, `walk_is_key`/`walk_count_keys`, `walk_why`, `changed_paths`,
`load_step_review_meta`, `load_walk_review_meta`). No se crea ningún verbo
nuevo ni se toca el dispatcher.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

Sin violaciones — la Constitution Check dio PASS. Tabla omitida.
