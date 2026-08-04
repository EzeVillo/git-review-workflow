# Implementation Plan: Paridad de información entre la CLI y el panel del editor

**Branch**: `003-paridad-cli-panel` | **Date**: 2026-08-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-paridad-cli-panel/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the
execution workflow.

## Summary

Cerrar el hueco de información entre lo que la CLI imprime y lo que el panel
muestra, en los dos modos donde hoy no hay paridad. Del lado de la CLI, tres
registros porcelain nuevos —`subject`, `author` y `base`— que llevan el asunto y
el autor de cada commit de una review commit por commit, y la base de una review
sin walkthrough. Del lado de la extensión, dibujarlos, más el origen y el tip que
el contrato ya emitía y el panel no usaba.

La decisión de dejar el cuerpo del mensaje afuera (Q3) es la que define la forma
del cambio: sin prosa multi-línea, **todo entra en la consulta de estado que la
extensión ya hace**. Cero invocaciones nuevas, cero superficies nuevas, ninguna
decisión sobre `--why`.

Los tres registros son nuevos en vez de campos agregados a `state`/`entry` por
una razón medida durante la investigación: **el asunto de un commit y el nombre
de un autor pueden contener tabs**, a diferencia de un path, y el separador del
formato porcelain es el tab. Un texto libre sólo es seguro como último campo de
su propio registro.

## Technical Context

**Language/Version**: shell POSIX (`sh`, con `set -eu`) para la CLI, sin
bashisms — corre bajo `dash` y Git Bash. TypeScript 5.x para la extensión,
compilado para el extension host de VS Code.

**Primary Dependencies**: git (plumbing y porcelain de git ya usados por el
proyecto: `git log`, `git rev-list`, `git config`). Del lado de la extensión,
ninguna nueva: el parser porcelain es propio y los registros nuevos se tokenizan
igual que los existentes.

**Storage**: N/A. No se persiste estado nuevo ni se agregan claves de
configuración: los tres datos se derivan en cada invocación, igual que hoy se
derivan para imprimirlos en pantalla.

**Testing**:

- `bats` para la CLI (`tests/`), corrido en el contenedor Linux vía
  `./tests/run-docker.sh`. Cubre los registros nuevos en los tres modos, los
  bytes hostiles (tab en asunto y autor, no ASCII, asunto vacío) y la ausencia
  de regresión en la salida humana.
- `shellcheck` sobre todo script tocado.
- Unit de la extensión (`mocha` + `node:assert`, sin host): parser de los
  registros nuevos, su ausencia con CLI vieja, y la derivación del view-model.
- Integration (`@vscode/test-electron`) sobre repos fixture construidos con la
  CLI real.
- `npm run preview` para el render del panel en sus estados nuevos.

**Target Platform**: la CLI, donde ya corre (Linux, macOS, Windows/Git Bash);
la extensión, VS Code Desktop en los tres SO.

**Project Type**: monorepo con dos artefactos — la suite de verbos POSIX en
`bin/` y la extensión en `vscode-extension/`. Esta feature toca los dos, y ése
es el motivo por el que el contrato y su consumidor se versionan juntos.

**Performance Goals**: consultar el estado de una review de 50 commits no se
percibe como demora al navegar (SC-008), en línea con SC-007 de
`001-contrato-porcelain`. En concreto: el asunto y el autor de N commits se
producen con un número **constante** de procesos git, no con uno por commit.

**Constraints**: aditividad estricta del contrato (FR-002) — un consumidor
construido contra el contrato anterior sigue funcionando sin cambios; cero
invocaciones de CLI adicionales desde la extensión (FR-013); cero derivación de
estado fuera de la CLI (FR-001); la salida humana no cambia (SC-008 de `001`, que
ya tiene un test que lo protege).

**Scale/Scope**: 2 historias de usuario (1×P1, 1×P2); 3 registros porcelain
nuevos; 1 verbo de la CLI modificado (`status`) más los helpers compartidos; del
lado de la extensión, el parser, el view-model, el panel, el selector de la
secuencia y las fixtures del preview.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` sigue siendo la plantilla sin completar de
Spec Kit — no hay principios ratificados para este repo, así que no hay gate
formal que evaluar. El gobierno de facto es `CLAUDE.md`, y esta feature toca
directamente tres de sus reglas:

- **Espejar los idioms de git.** Los registros nuevos siguen el esquema que ya
  usa `git status --porcelain=v2`: líneas etiquetadas, aditividad por etiqueta
  desconocida, y el texto libre como último campo — que es exactamente cómo git
  mismo trata los mensajes de commit en sus formatos legibles por máquina.
- **Sólo shell POSIX, sin bashisms, `set -eu`.** Aplica a todo lo que se toque
  en `bin/`.
- **Los dos README se actualizan juntos.** El formato porcelain está documentado
  en `README.md` y `README.es.md`: los registros nuevos entran en **ambos**, en
  el mismo cambio.

**Re-check post Phase 1**: sin violaciones. El diseño no agrega dependencias, no
persiste estado nuevo, no introduce una tercera superficie de documentación y no
requiere ninguna excepción a las reglas de arriba. La landing (`docs/index.html`)
**no** se toca: el cambio no afecta la tabla comparativa, los métodos de
instalación, los comandos de los ejemplos ni el formato del walkthrough.

## Project Structure

### Documentation (this feature)

```text
specs/003-paridad-cli-panel/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command); su
│                        # status-porcelain-v2.md (delta sobre el contrato de
│                        # 001) fue absorbido por 001-contrato-porcelain/
│                        # contracts/status-porcelain.md en la feature 004
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
bin/
├── git-review-verbs/
│   └── status                    # emite los registros subject/author/base
└── git-review-lib.sh             # helpers: producir asuntos y autores en bloque

tests/
├── porcelain.bats                # (existente) registros nuevos en los tres modos
├── porcelain-bytes.bats          # tab/no-ASCII/vacío en asunto y autor
└── sandbox.sh                    # commits con asunto y autor hostiles

vscode-extension/
├── src/
│   ├── cli/porcelain.ts          # parsea subject/author/base; ausencia ≠ vacío
│   ├── views/panelModel.ts       # los suma al view-model
│   ├── views/panelHtml.ts        # los dibuja: encabezado, asunto, autor
│   └── commands/pickEntry.ts     # asunto en el selector de la secuencia
├── preview/fixtures.ts           # estados nuevos del panel
└── test/
    ├── unit/                     # parser + view-model
    └── integration/              # panel sobre repos fixture reales

README.md                         # formato porcelain: registros nuevos
README.es.md                      # ídem, mismo cambio
```

**Structure Decision**: no hay estructura nueva que decidir. La feature es un
delta sobre dos árboles que ya existen y cuyo layout fijaron `001` y `002`; el
plan se limita a nombrar los archivos que se tocan. La única elección de
ubicación es la de los tests de bytes hostiles, que van a un archivo propio
(`porcelain-bytes.bats`) en vez de sumarse al existente: son la superficie de
riesgo nueva de esta feature y conviene poder correrlos solos.

## Complexity Tracking

*Sin violaciones que justificar — la sección Constitution Check no encontró
ninguna.*
