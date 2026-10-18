# Implementation Plan: Comentarios portables de una review

**Branch**: `main` | **Date**: 2026-10-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/016-comentarios-review/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Incorporar `git review comments` y su acceso desde VS Code, JetBrains, Visual
Studio y TUI. Cada contexto tiene dos documentos Markdown independientes,
Local y Compartido. La CLI interpreta y escribe el formato; los clientes
capturan texto y ubicación, presentan registros y abren archivos o diferencias.
Cada captura exige elegir destino, también si todavía no existe.

Durante una review o comparación ambos documentos viven en el gitdir del
worktree. Se separan preparación, contenido previo para descartar y resultado
conservado. Esto permite navegar en step sin bancar prosa como código, guardar
y retomar ambos documentos y abortar respetando lo anterior. En compare,
`comments save` conserva sólo prosa, sin cerrar. Al completar `finish`, el
Compartido modificado se prepara como `.review/comments.md` en la rama de
salida, sin commit ni push y verificando el destino contra sus bytes iniciales.

Cada entrada puede llevar referencias resueltas base/head y ubicación. Su
número expresa el orden físico, nunca identidad. Renumerar modifica sólo esos
dígitos; el histórico se calcula con objetos ya disponibles, sin guardar código
ni sustituir una revisión ausente por la actual.

Las decisiones y alternativas están en [research.md](research.md). La identidad
se define por documento y linaje Git; los casos ambiguos requieren inicialización
explícita. No se promete identificar números de PR de un proveedor.

## Technical Context

**Language/Version**: shell POSIX y awk POSIX; TypeScript con la toolchain actual;
Kotlin 2.3.20/JDK 21 y plataforma 2026.1/261; C# con dominio/host .NET 8 y VSIX
net472; Go según `tui/go.mod` (actualmente 1.25.14). Sin actualizar toolchains.

**Primary Dependencies**: Git y utilidades POSIX existentes, APIs públicas de
los hosts y `bubbles/textarea` ya disponible. Sin Python, Node ni biblioteca
Markdown nuevos en runtime de la CLI. Node sigue siendo herramienta de gates.

**Storage**: `<absolute-git-dir>/review-comments/`: contextos, sesiones,
resultados por generaciones y locks. Custodia en config de rama, leída
con `|| true`. Único archivo versionable nuevo: `.review/comments.md`.
Sin refs, bundles ni objetos nuevos para retener código histórico.

**Testing**: bats 1.13.0 y shellcheck en contenedores; fixtures de bytes y
compatibilidad GNU/BSD awk; suites de dominio, host e integración de los cuatro
clientes; gates del canónico. Afirmar estado de Git, presencia y bytes además
de exit code/stdout/stderr. Nombres de tests bats ASCII; pines intactos.

**Target Platform**: Linux, macOS y Windows/Git Bash para CLI/TUI; plataformas
actuales de los IDE. El VSIX se construye con MSBuild en Windows.

**Project Type**: función transversal del monorepo existente: CLI autoritativa
y cuatro adaptadores, sin servicio ni integración de proveedor.

**Performance Goals**: recorrido lineal del documento, sin procesos Git por
entrada al contar/renumerar y sin resolver históricos al refrescar presencia.
Aceptación con 100 entradas; la spec no exige un SLA temporal. Reutilizar
vigilancia/refresco vigentes y Refresh, sin sondeo nuevo de comments.

**Constraints**: preservar prosa/BOM/CRLF/LF final al renumerar; temporal hermano
y reemplazo completo; locks entre escritores CLI y comprobación optimista
frente a editores externos; elección por captura; sin estados ni ids de
comentarios, Ctrl+click, agentes o sesiones históricas. Los problemas de prosa
no impiden navegar/extraer código. Un fallo de entrega informa resultado parcial.

**Scale/Scope**: 6 historias, FR-001..FR-056, SC-001..SC-014; dos documentos por
contexto; ocho subcomandos de comments; dos acciones reales nuevas, `addComment`
y `saveComments`: 27 → 29. Cinco controles de documento no aumentan la cuenta.
La entrega incluye CLI y cuatro clientes; la CLI se publica primero.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

La constitución sigue siendo una plantilla sin ratificar. Sus ejemplos no
son normas; no se modifica en esta fase. Rigen `AGENTS.md`, D01..D21 y los
contratos vigentes. `BRANCH=016-comentarios-review` en el setup identifica la
feature; la rama Git real sigue siendo `main`.

| Gate | Antes de Phase 0 | Después de Phase 1 |
|------|------------------|--------------------|
| CLI única autoridad | Cumple | `comments status/entries/diff --porcelain`; sin parser Markdown en clientes |
| POSIX y dispatcher único | Cumple | Verbo privado y helpers sin efectos al sourcear |
| Dos documentos independientes | Cumple | Dos rutas/presencias; destino por captura y ninguna copia implícita |
| Prosa fuera de índice/banco step | Cumple | Sesiones en gitdir y entrega posterior a extracción de código |
| Normalización por puertas vigentes | Cumple | `walk_normalize` y `changed_paths`, sin duplicarlas |
| Custodia y descarte | Cumple | Baselines distintos de resultados y dueño por sesión/worktree |
| Histórico con refs resueltas | Cumple | OID completos, sin retención ni fallback a HEAD |
| Copy, confirmaciones y revelado | Cumple | 29 acciones y `comments_rows`; puertas canónicas |
| Documentación bilingüe | Cumple | Ambos README/CLI y documentación de clientes en implementación |
| Pisos publicados | Cumple | Secuencia de release; no adelantar constantes |
| Tests reales en contenedores | Cumple | Matriz del quickstart; pines bats intactos |

Sin violaciones ni aclaraciones de producto pendientes. Los contratos declaran
los límites de identidad Git, objetos faltantes y concurrencia POSIX.

## Project Structure

### Documentation (this feature)

```text
specs/016-comentarios-review/
├── spec.md
├── decisiones-pendientes.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── comments-format.md
│   ├── cli-porcelain.md
│   ├── lifecycle.md
│   └── client-surface.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
bin/git-review                          # ayuda
bin/git-review-verbs/comments           # nuevo verbo privado
bin/git-review-lib.sh                    # helpers comments_*
bin/git-review-verbs/{start,compare,save,continue,finish,abort,clean,forget}
completions/git-review-workflow.{bash,zsh,fish}
contracts/client-product-surface.yaml    # 29 acciones y comments_rows
scripts/check-client-product-surface.mjs # gates nuevos
tests/comments*.bats                     # familias nuevas
tests/fixtures/comments/                 # bytes y registros esperados
vscode-extension/src/{commands,review,views}/
jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/{domain,host,diff,ui}/
visualstudio-extension/src/{GitReview.Domain,GitReview.Host,GitReview.VS}/
tui/internal/{domain,host,ui}/
README.md / README.es.md / CLI.md / CLI.es.md
CONTRIBUTING.md / decisiones.md
```

**Structure Decision**: conservar dispatcher, libexec y separación dominio/host/UI.
La CLI no delega Markdown a un runtime nuevo. El mapa de integración por cliente
está en [client-surface.md](contracts/client-surface.md).

### Secuencia de implementación prevista

1. **Formato y contrato CLI.** Fixtures, parser/renumeración propios,
   `init/status/add/entries/diff`, tokens y consulta histórica. Probar bytes,
   fences, ordinales duplicados, cancelación y paths literales.
2. **Custodia y ciclo.** Contextos, baselines, generaciones y locks; integración
   con verbos existentes; `comments save/prepare`; entrega idempotente de
   finish y reversión. Probar los tres modos y compare antes de activar controles.
3. **Puerta de release de CLI.** Verificar y publicar la CLI con los argv y
   registros nuevos antes de integrar consumidores que los necesiten. El número
   se decide al cortar ese release; este plan no publica ni inventa versiones.
4. **Cuatro clientes y canónico.** Registros, guardado estricto del documento,
   compositor, controles y diff histórico. Actualizar canónico y gates junto
   con los adaptadores, y en ese mismo cambio cada mínimo y constante local
   contra la CLI ya publicada. Declarar los límites de captura de cada host.
5. **Validación y documentación.** Suites, escenarios del quickstart y smoke de
   los IDE; ambos README/CLI, completions, ayudas y docs de clientes. La landing
   sólo cambia si se toca una de sus cuatro duplicaciones; esta función no lo exige.
6. **Release de clientes.** Publicar los cuatro clientes con sus changelogs,
   después de validar la entrega integral y los pisos publicados. La CLI ya
   salió en el paso 3; no se integran clientes con un piso adelantado o falso.

### Trazabilidad de validación

| Requisitos | Diseño principal | Quickstart / evidencia prevista |
|------------|------------------|---------------------------------|
| FR-001..FR-012 | Formato y parser | §1–2; bytes, fences y 100 entradas; SC-001..SC-003 |
| FR-013..FR-018 | Dos documentos y entrega protegida | §1, §5, §7; SC-005, SC-008, SC-011 |
| FR-019..FR-024 | Custodia y referencias | §3, §6; SC-004, SC-009, SC-012, SC-013 |
| FR-025..FR-035 | CLI y cuatro clientes | §1, §6–8; SC-006..SC-008 |
| FR-036..FR-040 | Offline, límites, decisiones y docs | Sandbox sin red, contratos y revisión bilingüe; SC-010 |
| FR-041..FR-045 | Preparación, destino y descarte | §1, §3–5; SC-004, SC-011, SC-013 |
| FR-046..FR-052 | Histórico ligero y límites de hosts | §6, §8; SC-007, SC-012 |
| FR-053..FR-056 | Compare, entrega e identidad | §4–5, §7; SC-009, SC-013, SC-014 |

La secuencia alimenta `/speckit-tasks`. Esta fase termina con el diseño;
no genera `tasks.md` ni cambia código de producto.

### Validación de esta fase

Setup y `check-prerequisites.sh --json` ejecutados en contenedor: feature activa
correcta y research, modelo, contratos y quickstart detectados. Revisión
documental de las tres investigaciones consolidada; corregidos guard inicial,
límites de add, declaración explícita de contexto, comparación de prosa y
hilos de guardado JetBrains. Comprobación UTF-8, enlaces locales, encabezados
de plantilla, ausencia de marcadores pendientes y trazabilidad FR/SC.

`git diff --check` del alcance pasa con la configuración CRLF/filemode del
checkout Windows trasladada al contenedor. Los archivos nuevos se verifican
también directamente, porque el diff de Git no incluye archivos sin seguimiento.
No se ejecutan suites de comportamiento para esta entrega documental; las
aceptaciones futuras y los smoke están descritos en quickstart.

No hay `.specify/extensions.yml`; los hooks before_plan/after_plan se omiten.
La rama real permanece en `main` y se conserva la selección previa de feature.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

Sin violaciones; no corresponde completar la tabla.
