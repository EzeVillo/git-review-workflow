# Implementation Plan: Superficie completa del panel

**Branch**: `006-superficie-panel-completa` | **Date**: 2026-08-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/006-superficie-panel-completa/spec.md`

## Summary

Extender la extensión VS Code para invocar el resto de la CLI que `005` dejó
fuera: housekeeping (`clean`, `forget`, descarte de orphans), utilidades
(`preview`, `compare`) y autoría (`walkthrough init|build`). Misma filosofía:
lista cerrada de invocaciones, confirmación modal para mutaciones, estado solo
vía porcelain. No se espera porcelain nuevo salvo hueco real al implementar
listados de delta.

## Technical Context

**Language/Version**: TypeScript (extensión VS Code), shell POSIX en CLI (sin
cambios esperados)

**Primary Dependencies**: VS Code Extension API, `git review` en PATH / setting

**Storage**: N/A (estado en git vía CLI)

**Testing**: unit (parser/intent/confirm helpers) + integration
(`@vscode/test-electron`) en `vscode-extension/`; suite CLI existente si se toca
CLI

**Target Platform**: VS Code Desktop (win/mac/linux), misma matriz CI

**Project Type**: extensión de editor + CLI existente

**Performance Goals**: mutaciones locales < 15–30 s típicas; preview como
lectura; stale-delta con timeout de red (300 s como `start`)

**Constraints**: no `git branch -D`; no parsear salida humana para view-model;
confirmación fuera de `MutationLock`; lista cerrada de args

**Scale/Scope**: ~6 comandos nuevos + botones de inventario + 1–2 vistas de
solo lectura; 4 user stories priorizadas

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principio | Estado |
|-----------|--------|
| CLI es fuente de verdad; extensión no deriva estado | PASS — mutaciones vía verbos; refresh porcelain |
| Lista cerrada de invocaciones | PASS — enmienda `cli-invocation.md` |
| Riesgo asimétrico / confirmación | PASS — modal nombra efecto |
| Solo shell POSIX en CLI | PASS — no se cambia CLI salvo hueco |
| Dos README raíz si cambia CLI | PASS — solo si hay cambio CLI |
| README extensión en inglés | PASS — documentar acciones |
| Nombres de `@test` ASCII | PASS |

Post-design: sin violaciones.

## Project Structure

### Documentation (this feature)

```text
specs/006-superficie-panel-completa/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── cli-invocation.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
vscode-extension/
├── src/commands/
│   ├── cleanReview.ts          # NUEVO
│   ├── forgetReview.ts         # NUEVO
│   ├── previewEdits.ts         # NUEVO
│   ├── compareReview.ts        # NUEVO
│   └── walkthrough.ts          # NUEVO
├── src/views/panelHtml.ts      # botones orphan / discard saved
├── src/extension.ts            # registrar comandos + mensajes webview
├── package.json                # contributes.commands
├── test/unit/ …
├── test/integration/ …
└── README.md
```

## Complexity Tracking

Sin violaciones que justifiquen tabla de excepciones.
