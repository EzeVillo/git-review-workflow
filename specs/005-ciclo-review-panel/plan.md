# Implementation Plan: El ciclo de una review, completo desde el panel

**Branch**: `005-ciclo-review-panel` | **Date**: 2026-08-04 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/005-ciclo-review-panel/spec.md`

## Summary

Llevar al panel del editor las dos puntas del ciclo que hoy sólo existen en la
terminal —abrir una review (`start`), cerrarla (`finish`, con su deshacer y su
resume), pausarla (`save`) y cancelarla (`abort`)— sin mover una línea de lógica
a la extensión.

El trabajo se reparte en dos mitades que se condicionan:

- **CLI (habilita).** Tres huecos del contrato porcelain impiden hoy que el panel
  ofrezca estas acciones sin adivinar: (1) no hay forma de leer la configuración
  del repositorio ni las ramas candidatas **sin una review activa**, que es
  justo el estado desde el que se inicia una; (2) no hay forma de fijar esa
  configuración sin que el consumidor escriba `git config` por su cuenta, que
  está prohibido; y (3) los dos estados que produce `finish` —cierre completo
  pendiente y cierre trabado por conflicto— son **invisibles** para el contrato:
  el primero se ve como "no hay ninguna review" y el segundo como una review
  normal y navegable. Se resuelve con un verbo nuevo (`git review config`, con
  su `--porcelain`) y dos registros nuevos (`finish` en `status --porcelain` y en
  `list --porcelain`).
- **Extensión (consume).** Cinco invocaciones mutantes nuevas detrás de
  confirmación, un asistente por pasos para iniciar, y tres estados de panel
  nuevos. Todo con el molde que `002` ya fijó para `continue`: modal fuera del
  lock, progreso del editor, no cancelable, refrescar pase lo que pase, mostrar
  el `stderr` de la CLI verbatim.

La decisión estructural que ordena el resto: **la frontera de `002` no se
mueve**. Enumerar ramas para un selector es el primer dato del panel que no es
estado de review pero sí es estado del repositorio, y se resuelve agregándolo al
contrato en lugar de ampliar la excepción de la integración de git del editor.
Así SC-005 sigue siendo una sola regla verificable de un vistazo.

## Technical Context

**Language/Version**: shell POSIX (`sh`, `set -eu`, sin bashisms) para la CLI;
TypeScript 5 sobre Node 20 / API de VS Code `^1.75.0` para la extensión.

**Primary Dependencies**: git (≥ 2.23 por `git switch`); `cross-spawn` (única
dependencia de runtime de la extensión); esbuild para el bundle.

**Storage**: `git config` por repositorio y refs del propio repositorio — todo
detrás de la CLI. Del lado de la extensión, `vscode.workspace.getConfiguration`
para la única preferencia persistente (el origen), con los scopes user/workspace
que el host ya provee.

**Testing**: bats 1.13.0 para la CLI (en Docker: `./tests/run-docker.sh`);
mocha + `node:assert` para los unitarios puros de la extensión;
`@vscode/test-electron` para los de integración.

**Target Platform**: Windows, macOS y Linux; VS Code 1.75+.

**Project Type**: CLI de shell + extensión de editor en el mismo repositorio,
versionadas por separado (`vscode-extension/` no viaja en el tarball de npm).

**Performance Goals**: el reporte de configuración —incluidas las ramas
candidatas— cuesta un número **constante** de procesos, no uno por rama: es la
misma regla que la Decisión 2 de `002` aplicó a `status` y la razón por la que un
`status` de 50 commits bajo Git Bash pasó de ~9 s a menos de 1 s. Un repositorio
con cientos de ramas tiene que abrir el selector sin latencia perceptible.

**Constraints**: sin red en los tests; `start` es la única operación que accede a
la red y no puede colgarse esperando credenciales que nadie va a tipear; ninguna
operación que ya empezó a mutar el repositorio puede interrumpirse.

**Scale/Scope**: 5 verbos nuevos invocables desde el panel (`start`, `finish`,
`save`, `abort`, `config`), 1 verbo nuevo de CLI, 4 registros nuevos de contrato
(`config`, `candidate` y `delta` en el verbo nuevo; `finish`, compartido por
`status` y `list`), 6 historias de usuario.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` está sin ratificar (es la plantilla con sus
placeholders). En su lugar rigen las convenciones de `../../AGENTS.md`, que este plan
trata como gates duros:

| Gate | Estado | Cómo lo cumple este plan |
|------|--------|---------------------------|
| **Espejar los idioms de git** | PASS | El verbo nuevo es `git review config <clave> [<valor>]` — leer sin valor, escribir con valor, exactamente como `git config`. No se inventa un comando de configuración propio. |
| **Sólo shell POSIX, `set -eu`, sin bashisms** | PASS | El verbo nuevo y los cambios a `status`/`list` siguen la forma de los existentes. |
| **Nada de `A && B \|\| C`** (SC2015) | PASS | Las guardas nuevas van como `if` explícito con la condición invertida. |
| **Los DOS README, siempre los dos** | PASS | Tarea explícita en Fase 3; el verbo nuevo y los registros nuevos entran en ambos en el mismo cambio. |
| **La landing es pitch, no docs** | REVISAR | Toca uno de sus cuatro puntos duplicados: los ejemplos mencionan `reviewworkflow.base`. Se evalúa en Fase 3; el método que muestra sigue siendo válido, así que probablemente no cambie. |
| **Tests con asserts fuertes** | PASS | Cada `@test` afirma exit code + salida + efecto real sobre git; los casos de error afirman código, `stderr` y **ausencia** del efecto colateral. |
| **Nombres de `@test` en ASCII puro** | PASS | `tests/test-names.bats` lo verifica sobre toda la suite. |
| **Documentos de trabajo en español** | PASS | Este plan y sus artefactos; la plantilla en inglés se conserva verbatim. |
| **La extensión no deriva estado** | PASS | Es el gate central de la feature y el motivo de la Decisión 1: todo dato nuevo sale de la CLI. |

**Re-evaluación post-Fase 1**: sin cambios. Los tres contratos de
`contracts/` no introducen ninguna superficie que lea estado por fuera de la
CLI, y la lista cerrada de invocaciones sigue siendo enumerable y verificable
—ahora también en sus argumentos, que es un gate **más** estricto que el de
`002`, no uno más laxo.

**Complejidad justificada**: ninguna violación. El único costo nuevo real —un
verbo de CLI que en parte envuelve a `git branch`— se registra abajo.

## Project Structure

### Documentation (this feature)

```text
specs/005-ciclo-review-panel/
├── plan.md              # Este archivo
├── research.md          # Fase 0: las decisiones técnicas
├── data-model.md        # Fase 1: entidades y transiciones de estado
├── quickstart.md        # Fase 1: cómo validar la feature a mano
├── contracts/
│   ├── config-porcelain.md   # El verbo nuevo y su salida porcelain
│   ├── finish-state.md       # Los dos registros nuevos de estado de cierre
│   └── cli-invocation.md     # La lista cerrada ampliada (enmienda la de 002)
├── checklists/
│   └── requirements.md
└── tasks.md             # Fase 2 (/speckit-tasks — NO lo crea /speckit-plan)
```

### Source Code (repository root)

```text
bin/
├── git-review                     # dispatcher: el verbo nuevo en el listado de -h
├── git-review-lib.sh              # helpers nuevos: candidate_branches, finish_state
└── git-review-verbs/
    ├── config                     # NUEVO — leer/escribir la configuración del producto
    ├── status                     # + registro `finish` (cierre trabado)
    ├── list                       # + registro `finish` (cierre pendiente por rama)
    └── finish                     # sin cambios de comportamiento; es la fuente del estado nuevo

tests/
├── config.bats                    # NUEVO — el verbo, su forma humana y sus errores
├── config-porcelain.bats          # NUEVO — ramas candidatas, bytes hostiles, repos sin config
├── finish-state.bats              # NUEVO — los dos estados de cierre, en status y en list
├── status-porcelain.bats          # + los casos nuevos
├── list-porcelain.bats            # + los casos nuevos
└── sandbox.sh                     # + ramas en estado de cierre pendiente y trabado

vscode-extension/src/
├── cli/
│   ├── invoke.ts                  # timeouts por clase de invocación; entorno no interactivo
│   ├── porcelain.ts               # + registro `finish`
│   └── configPorcelain.ts         # NUEVO — parser del reporte de configuración
├── review/
│   ├── situation.ts               # + `finish-pending`, `finish-conflict`
│   ├── state.ts                   # + el reporte de configuración
│   ├── mutationLock.ts            # + señal cuando se descarta un pedido duplicado
│   └── staleGuard.ts              # NUEVO — premisa caduca entre decidir y confirmar
├── commands/
│   ├── startReview.ts             # NUEVO — el asistente por pasos
│   ├── finishReview.ts            # NUEVO — cerrar, deshacer, continuar
│   ├── saveReview.ts              # NUEVO
│   ├── abortReview.ts             # NUEVO
│   └── setBase.ts                 # NUEVO — fijar la base desde el panel
└── views/
    ├── panelModel.ts              # + acciones por estado
    └── panelHtml.ts               # + botones y los estados de cierre

README.md, README.es.md            # el verbo nuevo y los registros nuevos, en ambos
vscode-extension/README.md         # las acciones nuevas, en inglés
```

**Structure Decision**: se mantiene la separación que `002` estableció y que
`003`/`004` ya ejercitaron — la CLI en `bin/` con sus tests bats, la extensión
contenida en `vscode-extension/` con su propia cadena de build. Ningún archivo
nuevo cruza esa línea. El verbo nuevo entra como un ejecutable más en
`bin/git-review-verbs/` (privado, no en el `PATH`, alcanzable sólo por el
dispatcher), y los helpers compartidos van a `bin/git-review-lib.sh`, que ya es
el único lugar donde vive lógica común entre verbos.

## Complexity Tracking

> Sin violaciones que justificar. El único ítem se registra por transparencia, no
> por incumplimiento.

| Decisión | Por qué se paga | Alternativa más simple, y por qué se rechazó |
|----------|------------------|-----------------------------------------------|
| Un verbo de CLI que en parte envuelve a `git branch` | Es lo que mantiene la frontera de `002` como una sola regla (SC-005) en vez de una lista de excepciones que crece | Que el panel enumere ramas con la integración de git del editor: más barato, pero convierte la revisión de SC-005 en un juicio caso por caso y abre la puerta al siguiente dato "que tampoco es estado de review" |
