# Implementation Plan: Listado de archivos del rango en modo whole

**Branch**: `004-listado-archivos-whole` | **Date**: 2026-08-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-listado-archivos-whole/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Que ninguna superficie que enumere los archivos de una review esconda archivos del
rango. Concretamente: `whole` pasa a listar los archivos que toca el PR (en la
salida humana y como registros `entry` del porcelain, sin cursor), `walk` deja de
filtrar el sidecar del orden de lectura, y el contrato del porcelain se consolida
en un único documento vigente que sigue siendo v1.

El enfoque técnico es reusar, no construir: la lista es `changed_paths` —el punto
único de normalización de paths del lado git— aplicado al mismo par
`(HEAD, tip)` que `walk` ya usa. En `whole` eso es una invocación de git más por
`status`, y el filtro que se quita es un `grep -v` en tres puntos. El grueso del
trabajo no es el cálculo: es propagar el registro nuevo por el parser de la
extensión, el modelo del panel y su render, y actualizar las dos superficies de
documentación más los tests que hoy afirman el comportamiento contrario.

## Technical Context

**Language/Version**: shell POSIX (`sh`, corriendo bajo `dash` y Git Bash) para la
CLI; TypeScript sobre Node para la extensión del editor, empaquetada con esbuild.

**Primary Dependencies**: `git` (plumbing: `diff --name-only`, `config`,
`for-each-ref`); la API de extensiones de VS Code; `cross-spawn` para invocar la
CLI. No se agrega ninguna dependencia.

**Storage**: N/A. La feature no persiste nada — sin claves de configuración, sin
refs, sin archivos de estado (FR-009). Todo se re-deriva en cada invocación.

**Testing**: `bats` 1.13.0 vía `./tests/run-docker.sh` y `shellcheck` para la CLI;
`npm test` (unit + `@vscode/test-electron`) para la extensión.

**Target Platform**: Linux, macOS y Windows, los tres cubiertos en CI. Windows es
el que impone las restricciones reales (fork emulado bajo Git Bash, bytes de path
no ASCII).

**Project Type**: suite de comandos de CLI, más una extensión de editor que la
consume por su salida porcelain.

**Performance Goals**: cantidad de procesos **constante** respecto del tamaño del
PR. El listado de `whole` cuesta exactamente una invocación de git más por
`status`; el filtro que se quita en `walk` no cambia la cuenta. Es la restricción
que ya gobierna la rama `step` del mismo verbo, donde una implementación por
posición costaba segundos bajo Git Bash.

**Constraints**: sin bashisms; sin `A && B || C` (SC2015); `sed` in-place vía
archivo temporal; nombres de `@test` en ASCII puro; los dos README se actualizan
juntos; la extensión no deriva estado de la review por su cuenta.

**Scale/Scope**: PRs de hasta cientos de archivos. Nueve archivos de producto entre
CLI y extensión, cinco archivos de tests, dos README y el contrato consolidado.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` está sin completar (es la plantilla original), así
que no aporta gates. Los gates aplicables son las reglas vigentes del proyecto,
tomadas de `../../AGENTS.md` y de los contratos de `001`/`002`:

| Gate | Estado | Nota |
|------|--------|------|
| Espejar los idioms de git | ✅ | Listar los archivos de un cambio es lo que hace `git status`; no se inventa ningún verbo ni flag nuevo. |
| Shell POSIX, sin bashisms, `set -eu` | ✅ | Lo que se agrega es una invocación de `changed_paths` y un bucle `while read`, ambos ya usados en el mismo archivo. |
| Sin `A && B || C` | ✅ | Ninguna guarda nueva; el `grep -v` que se quita no participa de ninguna. |
| Dos puntos únicos de normalización de paths | ✅ | El listado sale de `changed_paths` y de ningún otro lado. La feature no agrega un tercero — de hecho hace pasar por ahí una superficie que antes no listaba nada. |
| La extensión no deriva estado | ✅ | La lista viaja por el `status --porcelain` que el panel ya invoca; no se agrega ninguna invocación (contracts/cli-invocation.md sigue intacto). |
| Los dos README se actualizan juntos | ✅ | Planificado como una sola tarea que toca los dos (FR-019). |
| Tests con asserts fuertes | ✅ | Todo `@test` nuevo afirma `status` y efecto observable; los que hoy afirman lo contrario se invierten, no se borran. |
| Nombres de `@test` en ASCII | ✅ | Verificado por `tests/test-names.bats` en toda la suite. |
| Aditividad del porcelain | ✅ | Registro ya existente (`entry`) en un modo que no lo emitía; un consumidor viejo lo ignora o lo lee sin flags. Ver research.md Decisión 3. |
| La landing es pitch, no docs | ✅ | El cambio no toca ninguna de las cuatro cosas que `docs/index.html` duplica; la landing no se toca. |

**Sin violaciones.** La sección *Complexity Tracking* queda vacía a propósito.

### Re-evaluación después de la Fase 1

Ninguna decisión de diseño introdujo una violación, y dos gates quedaron **mejor**
que antes del diseño:

- *Dos puntos únicos de normalización*: la Decisión 2 crea un helper compartido
  (`range_files`) donde hoy hay una expresión repetida, de modo que el filtro que se
  quita se quita en un solo lugar observable.
- *Aditividad del porcelain*: la compatibilidad se verificó en el parser real
  (`porcelain.ts:177` acumula `entry` en cualquier modo) en vez de asumirse, y la
  compatibilidad de las reviews `walk` en curso pasa de propiedad accidental a
  requisito con test propio (FR-023, research.md Decisión 7).

El único punto donde el diseño amplía el alcance por encima de lo mínimo es la
Decisión 6 —quitar el filtro también de las dos listas de degradación, no sólo del
orden de lectura—, y no es complejidad sino consistencia: dejarlas filtrando haría
que dos superficies contradijeran a una tercera sobre el mismo rango. Está señalado
al usuario como decisión recortable.

## Project Structure

### Documentation (this feature)

```text
specs/004-listado-archivos-whole/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── consolidacion-porcelain.md   # NO es un contrato de formato: es el plan
│                                    # de consolidación. El contrato vigente
│                                    # queda en 001 (ver US3).
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
bin/
├── git-review-lib.sh              # walk_reading_order: se le quita el filtro
│                                  # del sidecar; range_files: helper nuevo
└── git-review-verbs/
    ├── status                     # whole: listado humano + registros entry
    ├── start                      # lista de archivos sin cubrir al degradar
    ├── compare                    # idem
    └── walkthrough                # NO cambia (FR-022) — se verifica, no se toca

vscode-extension/src/
├── cli/porcelain.ts               # entry en whole: id como PathRef
├── views/panelModel.ts            # los archivos llegan al modelo del panel
├── views/panelHtml.ts             # whole deja de dibujar el estado vacío
├── commands/openEntry.ts          # abrir una entrada de whole por path
└── extension.ts                   # wiring del mensaje del webview

vscode-extension/preview/fixtures.ts   # el estado de whole, ahora con archivos

tests/
├── status-porcelain.bats          # se invierte el test de "zero entry lines"
├── porcelain-bytes.bats           # paths hostiles, ahora también en whole
├── walk.bats                      # totales +1 con el sidecar contado
├── walkthrough.bats               # build sigue sin proponer .review/
└── review.bats                    # salida humana de whole

vscode-extension/test/
├── unit/                          # parser y modelo
└── integration/                   # el panel en whole, y abrir un archivo

README.md, README.es.md            # los dos, en el mismo cambio
specs/001-contrato-porcelain/contracts/status-porcelain.md   # consolidado
specs/003-paridad-cli-panel/contracts/status-porcelain-v2.md # se elimina
```

**Structure Decision**: no hay estructura nueva. La feature toca tres capas ya
existentes —los verbos de shell, el parser/modelo de la extensión y la
documentación— y el reparto entre ellas lo fija la regla de que la CLI es la única
fuente de estado: todo lo que se calcula, se calcula en `bin/`, y la extensión
solo proyecta. El único archivo que cambia de rol es
`specs/001-contrato-porcelain/contracts/status-porcelain.md`, que pasa de ser "el
contrato de la feature 001" a ser **el** contrato vigente del verbo, absorbiendo el
delta que hoy vive en `003`.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

Sin violaciones que justificar.
