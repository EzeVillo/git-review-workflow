# Implementation Plan: El borrador del revisor, escrito por un agente

**Branch**: `012-prompt-agente-draft` | **Date**: 2026-08-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/012-prompt-agente-draft/spec.md`

## Summary

La 011 le dio al revisor **dónde** escribir su orden de lectura; ésta le da a un
agente **con qué** escribirlo, y al revisor **dónde volver a verlo**.

Cuatro piezas, en este orden:

1. **El esqueleto ubica el cambio.** El generador que hoy escribe las palabras
   literales «base..tip» pasa a escribir un **bloque de instrucciones** con los
   dos extremos ya resueltos (`lower` y `tip` existen como variables en el
   momento de escribirlo) y con los comandos exactos para ver el cambio y el
   contenido resultante de cualquier archivo listado. El bloque es una pieza
   reconocida del formato: un comentario HTML con centinela propio que la
   reescritura de `build`/`draft --build` **conserva regenerándolo** con el rango
   que esa corrida validó —nunca arrastrando el entrante, que envejecería— y que
   `walk_preamble` —el único filtro que existe— sigue descartando al mostrárselo
   al revisor. El bloque registra además con qué origen y rango se generó, que es
   lo que después permite validar y arrancar desde el panel sin cambiar de rango.
2. **Superficies que no obligan a escribir en el gitdir.** `--stdout` emite el
   esqueleto sin tocar el disco; `--build --from <archivo>|-` valida contenido
   externo con exactamente las reglas de hoy y lo instala en la ubicación
   canónica. La atomicidad ya está dada por la forma del `build` actual: la
   única escritura es el `mv` final.
3. **El borrador como objeto reportado.** `config --porcelain` gana un registro
   `draft` por borrador suelto (rama, ruta absoluta, progreso `anotadas/total`);
   `status --porcelain` le agrega la ruta al registro `draft` que ya emite; y
   `list --porcelain` gana un registro de presencia `branch-draft` por fila que
   carga un borrador.
4. **Los clientes lo muestran.** Un bloque nuevo arriba del cuerpo `no-review`
   —que sigue entero debajo—, una fila por borrador con cuatro controles, y el
   asistente que deja de esperar.

Ver [research.md](research.md) para el detalle de cada decisión y para los tres
hallazgos que cambian el coste de la spec (uno la abarata, dos la encarecen).

## Technical Context

**Language/Version**: shell POSIX (`sh`, `set -eu`, sin bashisms — corre bajo
`dash` y Git Bash) para la CLI; TypeScript (esbuild) para la extensión de VS
Code; Kotlin/JDK 21 (Gradle IntelliJ Platform) para el plugin; C# / .NET 8 +
net472 para la extensión de Visual Studio.

**Primary Dependencies**: git, única dependencia de runtime de la CLI. Ninguna
dependencia nueva en ninguno de los cuatro componentes. **Sin red, sin
credenciales y sin integración con ningún servicio de IA**, por decisión de
producto: el único hand-off es el portapapeles.

**Storage**: sin ubicaciones nuevas. El borrador sigue en
`<gitdir>/review-walkthrough/<src>.md` y su archivo pausado en
`<gitdir>/review-saved-walkthrough/<src>.md`. Ninguna clave de config nueva: el
bloque de instrucciones vive **dentro** del archivo y el progreso se cuenta al
vuelo, nunca se persiste.

**Testing**: bats para la CLI (en el contenedor, `./tests/run-docker.sh`); mocha
unit + integración con VS Code headless para la extensión (en el contenedor,
`./vscode-extension/test/run-docker.sh`); `./gradlew test` para el dominio del
plugin; `dotnet test` + `dotnet run --project src/GitReview.VS -- --verify` para
Visual Studio; `node scripts/check-client-product-surface.mjs` y
`npm run check:logo-assets` en CI; shellcheck sobre todo script
(`./lint-docker.sh`).

**Target Platform**: Linux, macOS y Windows — CI corre las suites en runners
reales de los tres.

**Project Type**: monorepo — CLI de shell como única fuente de verdad, más tres
clientes de IDE que sólo leen porcelain e invocan argv.

**Performance Goals**: coste en procesos no peor que el actual en los caminos
calientes. `config --porcelain` se invoca en cada refresco del panel sin review:
la enumeración de borradores es glob de shell (cero procesos) y el progreso de
**todos** los borradores sale de **un solo `awk`**, más un `git rev-parse` para
el gitdir absoluto que sólo se paga cuando hay al menos uno. Cota heredada:
nada de procesos por entrada de walkthrough.

**Constraints**: sin red; el formato del walkthrough gana **una** pieza
reconocida y nada más; contratos porcelain sólo aditivos (los clientes
publicados no pueden romperse); `min_cli_version` sube y sus tres constantes se
mueven a la vez; los dos README se actualizan en el mismo cambio que el
comportamiento.

**Scale/Scope**: N borradores simultáneos por working tree (el namespace ya
admite N); PRs de hasta unos cientos de archivos anotados.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` sigue sin instanciar (es la plantilla en
blanco), así que no impone puertas. Las normas efectivas del proyecto son las de
`../../AGENTS.md`; el diseño se evalúa contra ellas:

| Principio (CLAUDE.md) | Estado | Cómo lo cumple |
| --- | --- | --- |
| Espejar los idioms de git | ✅ | `--stdout` es el nombre que git usa para «emití a la salida estándar en vez de escribir archivos» (`git format-patch --stdout`); `--from <archivo>` con `-` para la entrada estándar espeja `git commit -F` / `git notes -F`; riesgo asimétrico (`--force` sólo donde algo se destruye). Ningún verbo nuevo. |
| Sólo shell POSIX, `set -eu`, sin bashisms | ✅ | Dos helpers nuevos en la lib, flags nuevos en un verbo existente, registros nuevos en tres verbos. `[ -t 0 ]` es POSIX y es builtin. |
| shellcheck limpio (sin `A && B \|\| C`) | ✅ | Guardas con `if` invertido; se verifica con `./lint-docker.sh`. |
| Dos README siempre juntos | ✅ | FR-036..FR-038; tarea explícita en cada fase que cambia comportamiento, no una fase de documentación al final. |
| La landing sólo si cambian sus 4 duplicados | ⚠️ | **Sí cambia uno**: el demo interactivo muestra el formato del walkthrough (`## Heads-up`, `## N. <path>`, badge `key`). El bloque de instrucciones es una pieza nueva del formato, pero **no se muestra nunca** —ni al revisor ni renderizado en el PR—, así que el demo sigue siendo fiel y la landing no se toca. Verificado contra `docs/index.html` en la Fase 1 (tarea de control, no de edición). |
| Tests con asserts fuertes, sin falsos positivos | ✅ | Cada caso afirma status + salida + efecto real sobre el disco/config; los de error afirman exit code, stderr y **ausencia** de efecto colateral (el borrador anterior byte por byte). |
| Nombres de `@test` en ASCII puro | ✅ | Lo verifica `tests/test-names.bats` sobre toda la suite. |
| La CLI es la única fuente de verdad para los clientes | ✅ | FR-021/SC-008: la ruta, la existencia y el progreso salen de registros nuevos. **Esta feature además borra una derivación que hoy existe**: `openDraft` de la extensión arma la ruta con `path.join` + `gitdirFromLink`. |
| Paridad de producto entre clientes, no de píxeles | ✅ | Mismo bloque, mismos controles, mismas etiquetas; vehículo de UI propio de cada plataforma. |
| Documentos de trabajo en español | ✅ | Todos los artefactos de `specs/012-*`. |
| Divergencia deliberada se declara en el contrato | ✅ | No se agrega ninguna. Las cuatro acciones nuevas son controles del cuerpo del panel, existen en los tres clientes. |

**Resultado**: sin violaciones. *Complexity Tracking* queda vacío a propósito.

## Project Structure

### Documentation (this feature)

```text
specs/012-prompt-agente-draft/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   ├── walkthrough-prompt-block.md    # el bloque de instrucciones como pieza del formato
│   ├── cli-walkthrough-draft-io.md    # --stdout, --build --from <archivo>|-
│   ├── config-porcelain-drafts.md     # registro draft (rama, ruta, progreso)
│   ├── porcelain-draft-custody.md     # status: ruta en el registro draft; list: branch-draft
│   ├── client-draft-panel.md          # bloque del panel, cuatro controles, asistente acortado
│   └── cli-invocation-draft-panel.md  # enmienda a la lista cerrada de invocaciones
├── checklists/
│   └── requirements.md  # /speckit-specify output
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
bin/
├── git-review-lib.sh
│   ├── walk_emit_prompt_block     # (nuevo) GENERA el bloque; único generador, tres llamadores
│   ├── walk_prompt_block          # (nuevo) consume el bloque entrante para no duplicarlo
│   ├── walk_draft_progress        # (nuevo) "ruta<TAB>anotadas<TAB>total" de N borradores en UN awk
│   ├── walk_gitdir_abs_init       # (nuevo) gitdir absoluto, una vez por proceso
│   ├── walk_preamble              # SIN CAMBIOS — sigue filtrando todo comentario
│   └── emit_draft_records         # (nuevo) los registros `draft` de config --porcelain
│                                  #   (no invoca awk ni gitdir si la lista viene vacía)
└── git-review-verbs/
    ├── walkthrough                # bloque de instrucciones; --stdout; --build --from
    ├── config                     # registros `draft` (con y sin rama)
    ├── status                     # ruta en el registro `draft` de --porcelain
    └── list                       # registro `branch-draft` en --porcelain

tests/
├── walkthrough-prompt-block.bats  # (nuevo) contenido, regeneración, filtrado, autor vs revisor
├── walkthrough-draft-io.bats      # (nuevo) --stdout, --from archivo/stdin, atomicidad, TTY
├── walkthrough-draft-progress.bats# (nuevo) conteo, denominador, drift sin cruzar rango
├── config-offers-draft.bats       # + registros `draft`
├── status-porcelain.bats          # + campo ruta del registro `draft`
├── list.bats                      # + registro `branch-draft`
└── walkthrough-draft*.bats        # los tres de 011: no deben cambiar de comportamiento

contracts/client-product-surface.yaml
├── min_cli_version: 0.7.0
├── panel_layout.no-review         # + {block: draft_block, when: has_drafts} como PRIMER bloque
└── draft_controls:                # (nuevo mapa) los cuatro controles de la fila

scripts/check-client-product-surface.mjs
└── collectCanonicalControls()     # + los controles de draft_controls (como inventory_controls)

vscode-extension/
├── src/cli/version.ts             # MIN_CLI_VERSION
├── src/cli/configPorcelain.ts     # DraftRecord + parseo
├── src/cli/porcelain.ts           # ruta en el registro draft
├── src/review/state.ts            # drafts en ReviewState
├── src/views/panelModel.ts        # PanelDraft[] en PanelModel
├── src/views/panelHtml.ts         # renderDrafts() arriba del cuerpo no-review
├── src/views/walkthroughViewProvider.ts # PANEL_MESSAGES + 4 ids
├── src/commands/draftActions.ts   # (nuevo) los cuatro comandos del bloque
├── src/commands/startReview.ts    # asistente que termina; openDraft usa la ruta de la CLI
└── src/review/draftFlow.ts        # el bucle de espera se retira; queda el paso corto

jetbrains-plugin/src/main/kotlin/com/ezevillo/gitreview/
├── domain/Version.kt              # MIN_CLI_VERSION
├── domain/ConfigPorcelain.kt      # DraftRecord
├── domain/Porcelain.kt            # ruta en draft
├── domain/PanelModel.kt           # PanelDraft
├── domain/PanelLayout.kt          # ControlId × 4, Block.DraftRows
├── ui/PanelRenderer.kt            # dibujo del bloque
└── ui/StartWizard.kt              # asistente que termina

visualstudio-extension/src/GitReview.Domain/  (mismos archivos, port mecánico)
└── ... + GitReview.VS/PanelView.cs, Wizards/StartWizard.cs

README.md, README.es.md            # los dos, en el mismo cambio que cada fase
```

**Structure Decision**: se respeta la estructura del monorepo tal cual está. No
se crean módulos ni capas nuevas; la única pieza de código de cliente nueva es
`draftActions.ts` y sus dos espejos, por la misma razón que existen
`draftFlow.ts` / `DraftFlow.kt`: lo que hay que poder probar sin editor es qué
argv sale de cada control, no cómo se dibuja la fila.

## Fases de entrega

El orden no es preferencia. Los clientes no pueden consumir una superficie que
la CLI todavía no expone, y las tres fases de CLI son entregables por sí solas
para un usuario de terminal — que es el usuario de la User Story 1 y 2.

### Fase 1 — CLI: el esqueleto ubica el cambio (US1, P1)

**Qué entrega**: un agente que recibe el esqueleto puede anotar el PR
correctamente desde la terminal, hoy, sin ningún cliente. Es la corrección de un
error silencioso: es la fase que se puede cortar sola.

- `bin/git-review-lib.sh`: `walk_prompt_block`.
- `bin/git-review-verbs/walkthrough`: el generador escribe el bloque con
  `lower`/`tip` resueltos y los comandos de la forma de dos argumentos; la
  situación del árbol de trabajo se decide por «¿HEAD está en `review/*`?» y no
  por `from_review` (ver research, Decisión 3); la reescritura de `build` emite
  `walk_prompt_block` entre el encabezado y el preámbulo.
- Los dos README: qué es el bloque, que no se muestra y que sobrevive.
- Control (no edición): `docs/index.html` — el demo sigue siendo fiel.
- **Tests**: `tests/walkthrough-prompt-block.bats` (bats, contenedor) +
  `./lint-docker.sh`.

### Fase 2 — CLI: entrada y salida sin tocar el gitdir (US2, P1)

**Qué entrega**: el circuito completo con un agente en sandbox, desde la
terminal. Depende de la Fase 1 sólo para que lo que se emite por `--stdout` ya
traiga el bloque; el resto es independiente.

- `walkthrough`: `--stdout`, `--from <archivo>|-`, la matriz de compatibilidad
  de flags, la guarda de TTY, el rechazo de entrada vacía, `--force` para pisar.
- Los dos README: el circuito recomendado con un agente (FR-038).
- **Tests**: `tests/walkthrough-draft-io.bats` (bats, contenedor).

### Fase 3 — CLI: el borrador como objeto reportado (US3 lado CLI, P2)

**Qué entrega**: nada visible para el revisor de terminal salvo el progreso;
existe para que las fases 4-6 tengan qué leer. **No se puede cortar acá sin
dejar trabajo muerto**, así que se planifica pegada a la Fase 4.

- `bin/git-review-lib.sh`: `walk_draft_progress`, `walk_gitdir_abs_init`,
  `emit_draft_records`.
- `config`: registros `draft`. `status`: ruta en el registro `draft`. `list`:
  registro `branch-draft`.
- `./bump-version.sh 0.7.0` (VERSION + `bin/git-review` + `package.json`).
- Los dos README: la sección de formato porcelain de los tres verbos.
- **Tests**: `tests/walkthrough-draft-progress.bats`, más los casos nuevos en
  `config-offers-draft.bats`, `status-porcelain.bats`, `list.bats`;
  `tests/version-consistency.bats` ya cubre el bump.

### Fase 4 — Extensión de VS Code (US3 + US4, P2)

**Qué entrega**: la historia 3 y la 4 completas en el cliente de referencia.

- **Primera tarea, atómica**: `min_cli_version: "0.7.0"` en
  `contracts/client-product-surface.yaml` **y** las tres constantes
  (`version.ts`, `Version.kt`, `Version.cs`) en el mismo commit — el verificador
  las compara todas contra el YAML, así que no se pueden mover por separado.
  Que JetBrains y Visual Studio exijan 0.7.0 antes de ofrecer la feature es
  correcto y no rompe nada: 0.7.0 ya existe desde la Fase 3.
- `panel_layout.no-review` + `draft_controls:` en el YAML, y los controles
  nuevos en `collectCanonicalControls()` del verificador.
- Parseo (`configPorcelain.ts`, `porcelain.ts`), modelo (`state.ts`,
  `panelModel.ts`), dibujo (`panelHtml.ts`), protocolo
  (`walkthroughViewProvider.ts`), comandos (`draftActions.ts`).
- `startReview.ts`: el asistente termina al crear el borrador, **sin abrirlo**; `openDraft` deja
  de derivar la ruta y usa la que reporta la CLI; la copy de la oferta se
  reescribe (FR-033).
- `preview/fixtures.ts`: el estado nuevo entra en el preview del panel.
- **Tests**: `npm run test:unit` (parseo, modelo, argv de los cuatro controles,
  copy del portapapeles) + `./vscode-extension/test/run-docker.sh` (el bloque se
  dibuja, cada control invoca lo suyo, el asistente cierra sin dejar aviso) +
  `node scripts/check-client-product-surface.mjs`.

### Fase 5 — Plugin de JetBrains (US5, P3)

Mismo bloque en `PanelLayout.kt` + `PanelRenderer.kt`, mismo asistente en
`StartWizard.kt`. **Tests**: `./gradlew test` (incluye
`PanelLayoutContractTest`, que compara contra el mismo YAML) y `platformTest`.

### Fase 6 — Extensión de Visual Studio (US5, P3)

Port mecánico del dominio + `PanelView`. **Tests**: `dotnet test`
(`PanelLayoutContractTests`), `dotnet run --project src/GitReview.VS -- --verify`
y `./build-vsix.ps1` (el gate de net472).

### Fase 7 — Cierre

**Las versiones, decididas** (no quedan como `X.Y.Z` para que las elija quien
implemente: de una de ellas depende lo que se publica):

| | De | A | Por qué |
| --- | --- | --- | --- |
| CLI | `0.6.0` | **`0.7.0`** | superficies nuevas, compatibles hacia atrás |
| VS Code | `0.1.3` | **`0.2.0`** | el panel gana un bloque y cuatro controles, y el asistente cambia de forma: es minor, no patch |
| JetBrains | `0.1.3` | **`0.2.0`** | ídem |
| Visual Studio | `0.1.0` | **`0.2.0`** | ídem; salta `0.1.x` porque no hay nada intermedio que publicar |

Los tres clientes versionan **aparte entre sí y aparte de la CLI**; que los tres
lleguen a `0.2.0` es consecuencia de que los tres reciben la misma feature, no
una regla.

`./vscode-extension/bump-version.sh 0.2.0`,
`./jetbrains-plugin/bump-version.sh 0.2.0` y
`./visualstudio-extension/bump-version.sh 0.2.0`, más el heading
`## [0.2.0]` en `jetbrains-plugin/CHANGELOG.md`.

**Ese heading es el único punto donde equivocar el número no falla en ningún
lado.** `build.gradle.kts` busca la sección de `pluginVersion` para el
`<change-notes>` del descriptor —la pestaña *What's New* del Marketplace y el
diálogo que el IDE muestra antes de actualizar— y `release-jetbrains.yml` extrae
la misma sección para el cuerpo del GitHub Release. Si no la encuentra **no
rompe**: hay un fallback deliberado que cae a `[Unreleased]` y, si tampoco, a un
enlace al CHANGELOG. O sea que el build sale verde, CI sale verde, y el error se
ve recién en la tienda. Por eso el número va decidido acá y no en la tarea.

Repaso final de los dos README.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

Sin violaciones que justificar.
