# Implementation Plan: Plugin de IntelliJ IDEA (paridad VS Code)

**Branch**: `009-plugin-intellij` | **Date**: 2026-08-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/009-plugin-intellij/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the
execution workflow.

## Summary

Segundo cliente de la CLI `git-review-workflow` dentro de **IntelliJ IDEA**:
tool window nativo (Swing), paridad total de situaciones y acciones con la
extensión VS Code, mismo contrato porcelain y mismas reglas de invocación.
Código en `jetbrains-plugin/`; capa de dominio JVM pura + host JetBrains;
fuente canónica anti-drift multi-cliente; tests JUnit espejo de la capa unit
de la extensión. Orden de entrega por capas hasta paridad, sin big-bang
sin tests.

## Technical Context

**Language/Version**: Kotlin (JVM), JDK alineado a IntelliJ Platform **2026.2**
(branch **262** — la numeración JetBrains es `20YY.N → (YY)(N)`: 2025.2 → 252,
2026.1 → 261, 2026.2 → **262**). El **único lugar** donde ese par vive es
`jetbrains-plugin/gradle.properties`; plan, research y quickstart lo citan pero
no lo fijan. T001 verifica la línea estable y su JDK contra la tabla oficial de
build ranges **del día de implementación**: si 2026.2 no está en runners ni en
el canal estable, se pinnea la última línea estable publicada y se actualiza
`gradle.properties` + `since-build` en el mismo PR — sin ensanchar a IDEs
viejos “por si acaso”. CLI sigue en shell POSIX; extensión VS Code intacta
salvo hooks anti-drift.

**Primary Dependencies**: IntelliJ Platform Gradle Plugin **2.x** (~2.18.1),
Git4Idea (bundled), JUnit 5, Kotlin coroutines solo si el host las usa para
EDT/background (domain puro sin coroutines obligatorias).

**Storage**: estado de review = solo CLI; persistencia IDE =
`PersistentStateComponent` (settings) + lastOpened map; sin DB.

**Testing**: JUnit 5 unit (domain) en los tres SO; **platform tests acotados
headless en CI Linux** (wiring del tool window, activación perezosa de SC-006,
una lectura de estado end-to-end contra la CLI del checkout) — no es
“donde sea estable”, es parte de la definición de terminado; smoke manual
multi-OS del quickstart para invoke + paths antes del release. Preview
standalone del panel.

**Target Platform**: IntelliJ IDEA 2026.2+ (solo IDEA), OS: Windows, macOS,
Linux.

**Project Type**: monorepo plugin + CLI + VS Code extension.

**Performance Goals**: primer paint del panel tras el show del tool window
**&lt; 1 s** con CLI local sana (un único número; no hay un segundo techo
“de diseño”). No es un Success Criterion medido en CI: se verifica
cualitativamente en el smoke del quickstart. Timeouts duros 15/120/300 s
(+30 s del git de apoyo); coalescencia de refresh; why diferido.

**Constraints**: UTF-8 explícito; un solo cwd; no estado desde VCS API; no
JCEF en v1; activación perezosa; porcelain aditivo; dos README si cambia
docs; CLAUDE.md (POSIX CLI, asserts fuertes); multi-cliente anti-drift.

**Scale/Scope**: paridad de **27 acciones** (los 27 `contributes.commands` de
la extensión al 2026-08-08) + 8 situaciones + asistentes start/compare;
~2.5k LOC domain port + host/UI nuevos; CI tri-lingüe.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` está **sin ratificar** (es la plantilla con
placeholders `[PRINCIPLE_N_NAME]`), así que no hay principios MUST que violar.
Los gates de abajo **no** son principios constitucionales: son las reglas
vigentes de `CLAUDE.md` y de los contratos de la CLI, usadas como sustituto
explícito. Si algún día se ratifica una constitución, esta tabla se rehace
contra ella:

| Gate | Estado | Nota |
|------|--------|------|
| CLI única fuente de verdad | ✅ | FR-001; plugin no mueve refs |
| Espejar idioms git / riesgo asimétrico | ✅ | confirmaciones + argv |
| Paths / encoding multiplataforma | ✅ | UTF-8, PathRef, sh workaround |
| Docs trabajo en español | ✅ | esta feature |
| Dos README si superficie documentada | ✅ | planificado |
| Tests con asserts fuertes | ✅ | JUnit espejo unit TS + platform tests Linux |
| No inventar estado | ✅ | porcelain only |
| Landing | ✅ | solo si se documenta plugin en las 4 superficies |

**Sin violaciones.** Complexity Tracking vacío.

### Re-evaluación post Phase 1

- Contratos `cli-invocation`, `plugin-surface`, `client-product-surface`
  cierran paridad y anti-drift sin tocar wire format de la CLI.
- Capas domain/host/ui permiten SC-007 sin IDE.
- Pin 2026.2/262 es decisión de alcance (última línea), no violación.
- La superficie de paridad se re-verifica contra la extensión antes de cerrar
  el release (T063a), porque la extensión puede moverse durante la
  implementación y la spec la congela al 2026-08-08.

## Project Structure

### Documentation (this feature)

```text
specs/009-plugin-intellij/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── cli-invocation.md
│   ├── plugin-surface.md
│   └── client-product-surface.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
contracts/
└── client-product-surface.yaml    # canónico anti-drift (nuevo)

jetbrains-plugin/
├── build.gradle.kts
├── settings.gradle.kts
├── gradle.properties              # ÚNICA fuente del pin: 2026.2 / branch 262
├── src/main/
│   ├── kotlin/com/…/gitreview/
│   │   ├── domain/                # puro: porcelain, situation, panel, intent…
│   │   ├── cli/                   # invoke GeneralCommandLine (puede vivir en host)
│   │   ├── host/                  # project service, refresh, lock, actions
│   │   ├── vcs/                   # sole target, listeners (Git4Idea)
│   │   ├── diff/                  # name-status + DiffManager
│   │   ├── ui/                    # ToolWindow, Swing panel, dialogs
│   │   └── settings/
│   └── resources/META-INF/plugin.xml
├── src/test/kotlin/…/domain/      # JUnit espejo de test/unit TS
├── preview/                       # main Swing con fixtures
└── README.md

vscode-extension/                  # tests anti-drift leen el YAML canónico
.github/workflows/                 # job Gradle + check surface
```

**Structure Decision**: módulo Gradle `jetbrains-plugin/` en monorepo;
domain sin dependencias de platform en `compileOnly`/source set separado o
paquete `domain` con regla de arquitectura (test que falle si importa
`com.intellij`).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
