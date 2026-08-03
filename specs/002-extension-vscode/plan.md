# Implementation Plan: Extensión de VS Code para revisar con walkthrough

**Branch**: `002-extension-vscode` | **Date**: 2026-08-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-extension-vscode/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the
execution workflow.

## Summary

Una extensión de VS Code que muestra la review en curso (leída íntegramente vía
`git review status --porcelain` / `list --porcelain` / `status --why`, el
contrato de la feature 001) como un panel dedicado a **la entrada actual**: en
qué posición de la secuencia está, sus marcas, y el *why* que el autor escribió
como cuerpo de la vista. La secuencia completa y los archivos sin cobertura se
alcanzan por `QuickPick`, y hay comandos para saltar al archivo,
avanzar/retroceder y leer el *why* completo. La extensión no deriva estado por su
cuenta ni muta refs/config directamente — todo pasa por invocar
`git review <verbo>` y releer su salida estructurada. Vive en su propio
subdirectorio (`vscode-extension/`), con cadena de construcción y tests
independientes del paquete npm de la CLI.

## Technical Context

**Language/Version**: TypeScript 5.x, compilado para el extension host de VS
Code (Node.js ≥18, el que empaqueta VS Code).

**Primary Dependencies**: API de extensión de VS Code (`vscode`, vía
`@types/vscode` + `engines.vscode`); `node:child_process` (`execFile`) para
invocar la CLI — sin cliente HTTP ni dependencias de red. Build con `esbuild`.
Empaquetado local con `@vscode/vsce`. Sin dependencias de parseo externas: el
formato porcelain es tab-separado y trivial de tokenizar a mano (ver
`research.md`, Decisión 2).

**Storage**: N/A. FR-001/FR-002 lo prohíben explícitamente — ningún estado de
review se persiste ni se deriva del lado de la extensión; cada refresco
re-invoca la CLI.

**Testing**:

- Unit (sin host de VS Code): `mocha` + `node:assert` sobre el parser
  porcelain, el des-citado de paths, la comparación de versiones y la
  derivación del view-model del panel — funciones puras, corren igual en los
  tres SO.
- Integration: `@vscode/test-electron` levantando un VS Code real contra
  repos fixture (creados con la CLI del propio proyecto) para probar el
  view-model que recibe el panel, los comandos y el ciclo de refresco
  end-to-end.

**Target Platform**: VS Code Desktop (motor mínimo a fijar en Phase 0) en
Windows, macOS y Linux (FR-028).

**Project Type**: Extensión de editor, proyecto único, subdirectorio propio
del monorepo (`vscode-extension/`) — ver Assumptions del spec.

**Performance Goals**: El panel refresca sin percibirse como demora para
reviews de cientos de entradas (consistente con SC-007 de
`001-contrato-porcelain`, que ya mide esto del lado de la CLI); el editor
permanece utilizable mientras una invocación está en curso (FR-030).

**Constraints**: Cero derivación de estado fuera de la CLI (FR-001, SC-005:
verificable por revisión de código, no en runtime); cero mutación directa de
refs/config/índice (FR-002); invocaciones que cambian estado no se solapan
(FR-020); funciona offline salvo por abrir la URL de instalación (FR-021).

**Scale/Scope**: 6 historias de usuario (2×P1, 3×P2, 1×P3); un panel, dos
`QuickPick`, un puñado de comandos, y los 5 estados vacíos/de error de la
Historia 5.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` sigue siendo la plantilla sin completar de
Spec Kit — no hay principios ratificados para este repo. No hay gate que
evaluar; el gobierno de facto del proyecto es lo que documenta `CLAUDE.md`
(espejar idioms del host, dos READMEs sincronizados, sólo POSIX `sh` para la
CLI). Ninguna de esas reglas de `CLAUDE.md` aplica a un proyecto TypeScript en
su propio subdirectorio salvo la primera — mirroreada acá hacia los idioms de
VS Code (ver `research.md`, Decisiones 4 y 5). Sin violaciones que registrar.

**Re-check post Phase 1**: sin cambios — el diseño no introdujo nada que
requiera una excepción.

**Re-check tras el rediseño del panel** (Decisión 4 revisada: webview en lugar
de `TreeView`): la regla de espejar los idioms del host sigue cumplida, pero de
forma más exigente. Un webview *puede* ignorar el host, así que el cumplimiento
pasa de gratuito a explícito y verificable — variables `--vscode-*` en lugar de
colores propios, `QuickPick` nativo para elegir de una lista, `<button>` reales
para el foco por teclado. Es la excepción que la decisión documenta y el motivo
de FR-031/SC-010.

## Project Structure

### Documentation (this feature)

```text
specs/002-extension-vscode/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
vscode-extension/
├── src/
│   ├── extension.ts                  # activation: registra vista, comandos, watchers
│   ├── cli/
│   │   ├── invoke.ts                 # execFile('git', ['review', ...]) + timeout/cancel
│   │   ├── porcelain.ts              # parser de records state/entry/uncovered/branch
│   │   ├── unquote.ts                # des-citado de paths con comillas de git (FR-012)
│   │   └── version.ts                # `--version` vs versión mínima del contrato
│   ├── review/
│   │   ├── repository.ts             # resuelve a qué carpeta del workspace corresponde
│   │   ├── state.ts                  # ReviewState/Situation, refresco + watcher de .git
│   │   └── mutationLock.ts           # serializa next/prev (FR-020)
│   ├── views/
│   │   ├── panelModel.ts                 # view-model plano, sin dependencia de vscode
│   │   ├── panelHtml.ts                  # el HTML/CSS/JS del panel, también sin vscode
│   │   ├── walkthroughViewProvider.ts    # WebviewViewProvider: lo monta y postea el modelo
│   │   └── whyContentProvider.ts         # TextDocumentContentProvider virtual (US3)
│   └── commands/
│       ├── navigate.ts               # next / prev
│       ├── openEntry.ts              # abrir archivo de una entrada
│       ├── pickEntry.ts              # QuickPick de la secuencia y de lo no cubierto
│       └── installOrUpdateCli.ts     # US5: sin CLI / CLI vieja
├── test/
│   ├── unit/                         # porcelain.ts, unquote.ts, version.ts — sin host
│   └── integration/                  # @vscode/test-electron + repos fixture
├── package.json                      # manifest: contributes.views/commands, activationEvents
├── esbuild.js
├── tsconfig.json
└── .vscodeignore
```

**Structure Decision**: proyecto nuevo y autocontenido en `vscode-extension/`,
con su propio `package.json`/cadena de build — no entra en `files` del
`package.json` de raíz (el de la CLI/npm), igual que `docs/` no viaja en el
tarball. Dentro del subdirectorio se sigue una estructura de capas simple
(`cli/` invoca al proceso externo y parsea; `review/` arma el view-model;
`views/`+`commands/` son la superficie de VS Code) en vez de la Option 1/2/3
genérica del template, porque ninguna de esas opciones (biblioteca+CLI, web
app, mobile+API) describe una extensión de editor.

## Complexity Tracking

*Sin violaciones que justificar — la sección Constitution Check no encontró
ninguna.*
