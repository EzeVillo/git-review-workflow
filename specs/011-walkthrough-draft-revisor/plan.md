# Implementation Plan: Walkthrough del revisor (draft local)

**Branch**: `011-walkthrough-draft-revisor` | **Date**: 2026-08-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/011-walkthrough-draft-revisor/spec.md`

## Summary

El revisor de un PR sin walkthrough puede armarse el orden de lectura y usarlo,
sin commitear, stagear ni deshacer nada. Un subcomando nuevo
(`git review walkthrough draft`) escribe el esqueleto en el gitdir del working
tree, fuera del árbol versionado; `walk_read` —el punto único por donde el
walkthrough entra a los lectores— resuelve la precedencia borrador-antes-que-
sidecar, con lo que las trece funciones de walk y todos los verbos que cuelgan
de ellas funcionan sobre el borrador sin cambios. `config --porcelain` gana dos
ofertas de lectura para que el asistente de inicio ofrezca armarlo o continuarlo
en el mismo paso donde hoy se elige cómo leer el PR, y los dos clientes agregan
el aviso no bloqueante que espera mientras el revisor lo completa. Ver
[research.md](research.md) para el detalle de cada decisión.

## Technical Context

**Language/Version**: shell POSIX (`sh`, `set -eu`, sin bashisms — corre bajo
`dash` y Git Bash) para la CLI; TypeScript (esbuild) para la extensión de VS
Code; Kotlin/JDK 25 (Gradle IntelliJ Platform, IDEA 2026.2) para el plugin.

**Primary Dependencies**: git (única dependencia de runtime de la CLI). Ninguna
dependencia nueva en ninguno de los tres componentes. **Sin red y sin
integración con ningún servicio de IA**, por decisión de producto.

**Storage**: archivos bajo el gitdir del working tree
(`<gitdir>/review-walkthrough/`, `<gitdir>/review-saved-walkthrough/`) y las
claves de config por rama que ya usa el modelo de estado. Ningún formato nuevo:
el borrador usa el mismo formato de walkthrough que el sidecar.

**Testing**: bats para la CLI (en el contenedor, `./tests/run-docker.sh`);
mocha unit + suite de integración con VS Code headless para la extensión (en el
contenedor, `./vscode-extension/test/run-docker.sh`); JUnit vía `./gradlew test`
y `platformTest` para el plugin. shellcheck sobre todo script (`./lint-docker.sh`).

**Target Platform**: Linux, macOS y Windows — CI corre las suites en runners
reales de los tres.

**Project Type**: monorepo — CLI de shell como fuente de verdad, más dos
clientes de IDE que sólo leen porcelain e invocan argv.

**Performance Goals**: coste en procesos no peor que el actual. La resolución de
precedencia usa un builtin (`[ -f ]`) y el camino con borrador ahorra el `git
show` que hoy paga cada `walk_read`. Cota dura heredada: nada de procesos por
entrada del walkthrough (regresión conocida de segundos bajo Git Bash).

**Constraints**: sin red; formato de walkthrough sin cambios; contratos
porcelain sólo aditivos (clientes publicados no deben romperse);
`contracts/client-product-surface.yaml` sin cambios de `panel_layout`; los dos
README se actualizan en el mismo cambio.

**Scale/Scope**: un borrador por rama bajo review. PRs de hasta unos cientos de
archivos anotados (mismo orden que el walkthrough del autor).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` está sin instanciar (es la plantilla en
blanco), así que no impone puertas. Las normas efectivas del proyecto son las de
`CLAUDE.md`; el diseño se evalúa contra ellas:

| Principio (CLAUDE.md) | Estado | Cómo lo cumple |
| --- | --- | --- |
| Espejar los idioms de git | ✅ | El borrador vive donde git pone los archivos de trabajo editables (`COMMIT_EDITMSG`, `MERGE_MSG`); `<branch>` posicional con default a la rama actual y `--` como en `start`; riesgo asimétrico (`--force` para sobrescribir). |
| Sólo shell POSIX, `set -eu`, sin bashisms | ✅ | Un subcomando en un verbo existente y helpers en la lib; nada nuevo fuera de ese molde. |
| shellcheck limpio (sin `A && B \|\| C`) | ✅ | Guardas con `if` invertido; se verifica con `./lint-docker.sh`. |
| Dos README siempre juntos | ✅ | FR-022; tarea explícita en la fase de documentación. |
| La landing no se toca salvo que cambien sus 4 duplicados | ✅ | No cambian la tabla comparativa, ni la instalación, ni los comandos del ejemplo, ni el formato de walkthrough del demo. |
| Tests con asserts fuertes, sin falsos positivos | ✅ | Cada caso afirma status + salida + efecto real sobre el estado de git; los de error afirman exit code, stderr y ausencia de efecto colateral. |
| Nombres de `@test` en ASCII puro | ✅ | Verificado por `tests/test-names.bats` sobre toda la suite. |
| La CLI es la única fuente de verdad para los clientes | ✅ | Los clientes no leen ni parsean el borrador: la viabilidad llega por `offer` y el marcado por un registro de `status --porcelain`. |
| Paridad de producto entre clientes, no de píxeles | ✅ | Mismo flujo y mismos textos; vehículo de UI propio de cada plataforma. |
| Documentos de trabajo en español | ✅ | Todos los artefactos de `specs/011-*`. |

**Resultado**: sin violaciones. La sección *Complexity Tracking* queda vacía a
propósito.

## Project Structure

### Documentation (this feature)

```text
specs/011-walkthrough-draft-revisor/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   ├── cli-walkthrough-draft.md        # superficie del subcomando nuevo
│   ├── config-porcelain-draft.md       # enmienda: offers draft / draft-resume
│   ├── status-porcelain-draft.md       # enmienda: registro de presencia
│   └── client-draft-flow.md            # flujo del asistente en ambos clientes
├── checklists/
│   └── requirements.md  # /speckit-specify output
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
bin/
├── git-review-lib.sh                 # walk_read (precedencia), walk_use_draft,
│                                     # walk_draft_path, walk_is_draft,
│                                     # emit_reading_offers (+2 ids)
└── git-review-verbs/
    ├── walkthrough                   # subcomando draft [--build]
    ├── save                          # mueve el borrador al namespace guardado
    ├── continue                      # lo devuelve al namespace activo
    ├── clean                         # poda sólo el namespace activo
    ├── forget                        # --saved borra el guardado
    ├── status                        # registro de presencia + "(draft)"
    ├── config                        # sin cambios (delega en emit_reading_offers)
    └── start                         # nota accionable cuando no hay walkthrough

tests/
├── walkthrough-draft.bats            # subcomando: crear, validar, --force, errores
├── walkthrough-draft-lifecycle.bats  # save/continue/clean/forget + finish limpio
├── walkthrough-draft-read.bats       # precedencia y paridad entre superficies
└── config-offers-draft.bats          # ids nuevos y su viabilidad

vscode-extension/
├── src/cli/configPorcelain.ts        # ids nuevos en el tipo OfferId
├── src/review/layoutOffers.ts        # OFFER_META / OFFER_ORDER
├── src/commands/startReview.ts       # rama del asistente: crear, abrir, esperar
├── src/review/draftFlow.ts           # (nuevo) máquina del bucle, pura y testeable
├── src/views/panelHtml.ts            # badge de "draft" (texto, sin bloque nuevo)
└── test/                             # unit del flujo + integración del asistente

jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/
├── domain/ConfigPorcelain.kt         # ids nuevos
├── domain/LayoutOffers.kt            # OFFER_META / OFFER_ORDER
├── domain/DraftFlow.kt               # (nuevo) misma máquina, dominio puro
├── ui/StartWizard.kt                 # rama del asistente
└── ui/DraftWaitDialog.kt             # (nuevo) DialogWrapper no modal

contracts/client-product-surface.yaml # min_cli_version (sin cambios de layout)
README.md, README.es.md               # superficie nueva, en el mismo cambio
```

**Structure Decision**: se respeta la estructura del monorepo tal cual está —
CLI de shell en `bin/`, suites bats en `tests/`, y un proyecto por cliente. No
se crean módulos ni capas nuevas. Las dos únicas piezas nuevas de código de
cliente (`draftFlow.ts` / `DraftFlow.kt`) existen para que el bucle de
validación sea lógica pura testeable sin editor, igual que hoy `layoutOffers` y
`reviewIntent`; el resto son ampliaciones de archivos existentes.

## Fases de entrega

El orden no es preferencia: el registro `offer` es dependencia dura de los dos
clientes, y ninguno puede derivarlo por su cuenta.

1. **CLI** — subcomando, precedencia en `walk_read`, ciclo de vida, offers,
   marcado en `status`, nota en `start`, ambos README. Entregable por sí solo:
   cubre la User Story 1 completa.
2. **Extensión de VS Code** — ids nuevos, rama del asistente, aviso no
   bloqueante, badge. Cubre la User Story 2.
3. **Plugin de IntelliJ** — lo mismo con `DialogWrapper` no modal. Cubre la
   User Story 3.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

Sin violaciones que justificar.
